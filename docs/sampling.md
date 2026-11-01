# Sampling

moontrace sampling is opt-in subscriber composition. The core emit path still
builds and dispatches events normally; applications decide whether to wrap their
subscriber with sampling layers.

## Event Ratio Sampling

```moonbit
let sampled = @moontrace.ratio_sampler(
  @json.subscriber(),
  0.10,
)
@moontrace.set_subscriber(sampled.subscriber())

// later
println("kept=\{sampled.kept()} dropped=\{sampled.dropped()}")
```

`ratio_sampler` clamps ratios into `[0.0, 1.0]`. A ratio of `0.0` drops every
event, `1.0` keeps every event, and intermediate values use a random source.
Tests and deterministic applications can inject `rand=fn() { ... }`.

## Fixed-Window Rate Limiting

```moonbit
let limited = @moontrace.rate_limiter(
  @json.subscriber(),
  100,
  1_000_000_000UL,
)
@moontrace.set_subscriber(limited.subscriber())

println("kept=\{limited.kept()} dropped=\{limited.dropped()}")
```

`rate_limiter` keeps at most `limit` events per fixed `window_ns`. The default
clock is `@env.now`; tests can inject `clock=fn() { ... }` to advance windows
deterministically.

## Burst Sampling

```moonbit
let burst = @moontrace.burst_sampler(
  @json.subscriber(),
  10,              // keep the first 10 per key in each window
  100,             // then every 100th
  1_000_000_000UL, // one-second windows
)
@moontrace.set_subscriber(burst.subscriber())
```

`burst_sampler` limits repeated log lines without silencing them entirely, like
zap's `Initial`/`Thereafter` sampler. The default key is the event's level and
message; pass `key=fn(event) { ... }` to group differently. `thereafter = 0`
drops everything past `first` until the window resets. Counts live in a fixed
number of hash buckets (`buckets=4096` by default), so memory stays bounded;
keys that share a bucket share a count. `kept()` and `dropped()` report totals,
and `clock=` makes windows deterministic in tests.

## Breadcrumbs

```moonbit
let crumbs = @moontrace.breadcrumbs(@json.subscriber(), capacity=50)
@moontrace.set_subscriber(@moontrace.compose([
  @console.subscriber(min_level=@moontrace.Info),
  crumbs.subscriber(),
]))
```

`breadcrumbs` holds the most recent events below `trigger` (default `Error_`)
and forwards nothing until a triggering event arrives. That event first flushes
the held events, oldest first, then is forwarded itself, so the JSON output
above contains each error with up to 50 events of lead-up context. The oldest
held event is discarded when the ring is full (`dropped()`). `flush()` forwards
held events on demand, for example at shutdown, and `clear()` discards them.

## Head Trace Sampling

```moonbit
let traced = @moontrace.trace_sampler(@json.subscriber(), 0.25)
@moontrace.set_subscriber(traced.subscriber())
```

`trace_sampler` reads the event's `"trace_id"` field, which span-correlated
events carry automatically, and uses deterministic head sampling for that trace
ID. Events without a `"trace_id"` field pass through unchanged. The pure
predicate is available directly:

```moonbit
let keep = @moontrace.should_sample_trace(trace_id, 0.25)
let parent_aware = @moontrace.sample_trace_decision(
  parent_flags,
  trace_id,
  0.25,
)
```

`sample_trace_decision` honors a provided parent `TraceFlags` sampled bit. When
no parent flags are available, it falls back to `should_sample_trace`.

## Span Sampling

Event samplers decide which events reach a subscriber. A span sampler decides,
when a span is created, whether the span is sampled:

```moonbit
@moontrace.set_span_sampler(
  @moontrace.parent_based_sampler(@moontrace.trace_id_ratio_sampler(0.25)),
)
```

`span`, `span_with_trace`, `child_span`, and `span_from_remote_context` run the
installed sampler and store the result in the span's sampled trace flag. Spans
that are not sampled still get trace and span IDs and still propagate through
`traceparent`, with the sampled flag cleared, so downstream services see the
decision. Span observers, including the OTLP and flame exporters, do not receive
them. `Span::is_sampled()` reports the decision.

Built-in samplers:

- `always_on_sampler()` and `always_off_sampler()` ignore the parent.
- `trace_id_ratio_sampler(ratio)` keeps a deterministic fraction of trace IDs.
  It uses the same hash as `trace_sampler` and `should_sample_trace`, so a span
  sampler and an event `trace_sampler` at the same ratio keep the same traces.
- `parent_based_sampler(root)` follows the parent's sampled flag, whether the
  parent is a local `Span` or a remote `SpanContext`, and uses `root` only for
  spans without a parent.
- `span_sampler(fn(input) { ... })` wraps a custom decision. `SamplingInput`
  carries the trace ID, span name, kind, initial fields, parent flags, and
  whether the parent is remote.

The default is `parent_based_sampler(always_on_sampler())`: root spans are
sampled and children follow their parent. `reset_span_sampler()` restores it,
and `with_span_sampler(sampler, f)` and `with_trace_state` scope it.

Span sampling does not filter events. Events logged inside unsampled spans and
the Trace-level `span.enter`/`span.exit` lifecycle events still reach the
subscriber. Span-correlated events (`Span::info`, `Logger::in_span`, and the
other span-aware helpers) carry a `"trace_id"` field, so wrapping the subscriber
in `trace_sampler` at the same ratio drops them for the same traces. Lifecycle
events carry no `"trace_id"`, so `trace_sampler` passes them through; keep the
minimum level above `Trace` or drop them with `filter_events` if they are not
wanted.

## Composing Layers

Sampling layers wrap regular subscribers, so they can be combined with filters,
redaction, buffers, exporters, and fan-out:

```moonbit
let sampled = @moontrace.trace_sampler(
  @moontrace.redact(@json.subscriber()),
  0.20,
)
let limited = @moontrace.rate_limiter(sampled.subscriber(), 500, 1_000_000_000UL)

@moontrace.set_subscriber(@moontrace.compose([
  limited.subscriber(),
  @console.subscriber(min_level=@moontrace.Warn),
]))
```

## Tail Sampling

Head sampling decides when a trace starts. Tail sampling waits until the trace
has finished, so it can keep exactly the traces that turned out to matter, as
Honeycomb Refinery and the OpenTelemetry collector's tail sampler do:

```moonbit
let exporter = @otlp.exporter(span_output=fn(_json) { () })
let tail = @moontrace.tail_sampler(
  exporter.span_observer(),
  policy=@moontrace.tail_policy(min_duration_ms=500UL, ratio=0.01),
)
@moontrace.set_span_observer(tail.observer())
@moontrace.set_subscriber(tail.subscriber(@json.subscriber()))
// At shutdown:
tail.flush()
```

The sampler buffers each trace's completed spans until every span of the trace
created in this process has closed, then calls the policy with a
`TraceSummary` (the spans, whether any errored, the longest duration, and
whether the decision was forced). Kept traces reach the inner observer as
completed spans, through `on_closed` only, which suits exporters built on
`completed_span_observer`. Events carrying a pending trace's `trace_id` are
held and forwarded only if it is kept. Events for recently dropped traces are
discarded, and events without a trace pass straight through.

`tail_policy(keep_errors?, min_duration_ms?, ratio?)` keeps errors by default,
optionally slow traces, and a deterministic ratio of the rest; any
`(TraceSummary) -> Bool` works as a policy.

Memory is bounded. Past `max_traces` pending traces, the oldest is decided
early. A trace is decided early when it reaches `max_spans_per_trace`, and
traces pending longer than `trace_timeout_ms` (default 30s), such as ones with
spans that never close, are decided on the next callback. These early
decisions set `TraceSummary.forced`; `kept()`, `dropped()`, `forced()`, and
`pending()` report totals. Combine tail sampling with head sampling to bound
the volume reaching the buffer in the first place.