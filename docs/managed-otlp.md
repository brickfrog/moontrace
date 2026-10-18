# Managed OTLP JSON export

`brickfrog/moontrace/otlp/transport` offers `managed_json_exporter(tx)` for
applications that want timed batches and a bounded delivery queue. It reuses the
OTLP batcher and HTTP transport's retry and partial-success handling. Existing
exporter and transport APIs remain available. The worker/example run on native and
JavaScript with the async runtime; wasm-gc builds retain the existing HTTP-client
limitation and do not provide an async executable runtime.

Run the self-contained example (synthetic client, no collector or network):

```sh
moon run src/cmd/managed_json --target native
moon run src/cmd/managed_json --target js
```

The [example source](../src/cmd/managed_json/main.mbt) shows subscriber and completed
span observer setup, caller-owned structured concurrency, flush, and shutdown.
For HTTP delivery, supply `async_http_client()` to `transport(client, endpoint)`
instead of the example's synthetic client. Keep that client alive until managed
shutdown completes, then call `client.shutdown()`.

## Ownership and limits

Construction and logging start no tasks. Spawn `exporter.run()` in your task
group; it owns one sender and a timer scoped to that task. Only one `run()` may
be active. It is safe to spawn the worker and immediately call flush/shutdown.
Without a worker, flush and shutdown drive sending in the calling task.

The adapter owns the supplied transport's lifecycle. Do not export through that
transport or shut it down separately while the adapter is active. The HTTP client
remains caller-owned and may have a longer lifetime. Use this adapter on one
async event loop; it does not provide cross-thread synchronization.

Defaults are `batch_size=64`, `queue_capacity=64`, `max_payload_bytes=262144`,
`max_pending_bytes=1048576`, and `flush_interval_ms=1000`. Limits below one clamp
to one, and the per-payload limit cannot exceed the pending-byte limit.

- Queue capacity and pending-byte gauges include the batch currently in flight,
  including transport retries. Bytes are measured as UTF-8 JSON payload bytes.
- Each signal may additionally retain one partial batch, bounded by the same
  per-payload limit and by the record count. Envelope metadata counts toward the
  payload limit. Serialization can use additional transient memory.
- A full batch/pending-byte budget drops the newest batch. Oversized individual
  records are dropped before buffering. Logging callbacks never wait for network
  or queue space, though they perform synchronous conversion/serialization.
- Normal capacity, timer, and explicit flushes use this same drop-new policy.
  There is no durable disk spool, detached worker, or protobuf transport.

## Flush, shutdown, and cancellation

`flush()` serializes partial batches, then waits for every batch accepted through
its barrier to reach a terminal outcome. Later batches do not extend the barrier.
Concurrent lifecycle calls are serialized. The returned stats are a cumulative
snapshot, not a per-flush delivery receipt: failures and drops do not raise by
themselves. Inspect the counters and diagnostics.

`shutdown()` closes intake immediately and stops timer flushes. It drains accepted
batches before flushing the final log and span partial batches individually, so a
full queue does not discard those final partial batches. It then closes the queue,
joins the running sender/timer, and shuts down the transport. Repeated shutdown is
safe. Events/completed spans submitted after intake closes count as dropped records.

Both operations are cancellable; use the async runtime's timeout facilities if
you need a deadline. Cancelling `run()` or an inline drain propagates cancellation,
counts its in-flight batch as failed with **unknown delivery**, and never replays
that batch automatically. Unsent queued and buffered work remains available to a
later worker or drain. Cancelling shutdown leaves intake closed; call shutdown
again from an uncancelled task to finish. Flush reports an error while shutdown is
incomplete, rather than claiming the remaining partial buffers were flushed.
A custom client must cooperate with async cancellation for deadlines to work.

## Observability

`stats()` returns enqueued, delivered, failed, and dropped batch counts, dropped
record count, pending batch/byte gauges, buffered log/span counts, and lifecycle
flags. A fully accepted response (including a warning) counts as delivered; partial
rejection counts as a failed batch. Dropped batches include their record counts;
an individually oversized or post-close record increments only `dropped_records`.

`last_report()` retains the latest completed transport report, including collector
rejected counts/messages; a failure/cancellation without a report clears it.
`last_error()` retains the latest delivery failure diagnostic. Successful sends
need not mean the collector persisted the data, and cancellation cannot prove
whether an in-flight request was accepted.
