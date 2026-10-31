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

Span sampling does not filter events. Span enter and exit events, and events
logged inside unsampled spans, still reach the subscriber. To drop those too,
wrap the subscriber in `trace_sampler` at the same ratio.

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

Tail sampling is intentionally deferred. It needs a buffered trace store so the
decision can be made after a trace completes; these layers only make immediate
event or head-trace decisions.
