# moontrace Roadmap

Feature gap analysis vs Rust's `tracing` and Python's `loguru`, prioritized for MoonBit's constraints.

## Current State (v0.3.0)

- Events: info/warn/error/debug/trace with structured fields
- Spans: enter/exit/duration, record(), with_field(), with_span_ctx, with_child_span
- Span IDs: trace_id (32 hex), span_id (16 hex), parent_span_id — auto-generated, propagated
- SpanKind (Internal/Server/Client/Producer/Consumer), SpanStatus (Unset/Ok/SpanError)
- span_with_trace() for custom trace ID injection (cross-process correlation)
- Subscribers: JSON, console, OTLP JSON export
- Composition: compose(), with_filter(), noop(), tap(), EventBuffer
- Performance: global level gate (set_min_level)
- Serialization: to_json() on Event/Span/Field, Event.format(color?)
- Show trait on all types, Level.from_string()
- Cross-platform: native, JS, WASM-GC
- CI: GitHub Actions testing all 3 backends
- 94 tests

## ~~Phase 1: OTLP Alignment (Core)~~ DONE (v0.3.0)

- [x] Add `SpanKind` enum to core (Internal, Server, Client, Producer, Consumer)
- [x] Add `SpanStatus` enum to core (Unset, Ok, SpanError)
- [x] Move trace/span ID generation from otlp to core — auto-generate in `span()`
- [x] Add `trace_id` and `span_id` fields to core `Span` struct
- [x] Ensure `with_child_span` propagates trace_id and sets parent_span_id
- [x] `span_with_trace()` for custom trace ID injection

## Phase 2: Context System (`@moontrace/context`)

MoonBit has no task-local storage. Provide an explicit context API instead.

- [ ] Global context for single-threaded apps: `set_global(key, value)`, `get_global(key)`
- [ ] Span-bound context: `bind_to_span(span, key, value)`
- [ ] Auto-inject global context fields into emitted events
- [ ] Child spans inherit parent context fields
- [ ] `clear_global()` for test isolation

```moonbit
// Single-threaded convenience
@context.set_global("request_id", "abc-123".to_json())
@moontrace.info("handling")  // automatically includes request_id

// Async-safe explicit passing
@moontrace.with_span_ctx("op", fn(span) {
  @context.bind_to_span(span, "user_id", "42".to_json())
  @moontrace.with_child_span(span, "query", fn(child) {
    // child inherits user_id from parent context
  })
})
```

## Phase 3: Per-Module Filtering

Go beyond global min_level to target-specific filtering.

- [ ] Filter string parsing: `"db=debug,api=warn,default=info"`
- [ ] `set_filter_string(s)` for programmatic configuration
- [ ] `set_filter_fn(f: (String, Level) -> Bool)` for custom logic
- [ ] Module/target name on events (requires source location or manual tagging)

```moonbit
@moontrace.set_filter_string("db=trace,http=warn")
```

## Phase 4: File Management (`@moontrace/file`)

Production log file output with rotation and retention.

- [ ] File subscriber: write events to a file path
- [ ] Rotation by size or time interval
- [ ] Retention policies: max files, max age
- [ ] Compression of rotated logs (gzip)
- [ ] Multiple files with different levels/formats

```moonbit
@file.initialize("app.log", rotation=Size(100_000_000), retention=MaxFiles(5))
```

**Note:** Depends on MoonBit's filesystem APIs. May be native-only initially.

## Phase 5: Error Integration

- [ ] `error_event(msg, err)` that auto-extracts error message and type
- [ ] Span status auto-set to Error when recording an error
- [ ] Stack trace capture (if MoonBit adds support)

## Lower Priority

### Rich Field Builders
- [ ] Fluent API: `@moontrace.fields().add("key", val).build()`
- [ ] Lazy field evaluation (only compute if event will be emitted)

### Sampling
- [ ] Random sampling (sample N% of traces)
- [ ] Rate-limited sampling (max N events per second)
- [ ] Head-based vs tail-based sampling

### Test Utilities
- [ ] `TestSubscriber` that captures events with query helpers
- [ ] Mock timestamp injection for deterministic tests
- [ ] Test isolation helpers (auto clear_subscriber + set_min_level)

### Field Redaction
- [ ] Auto-redact sensitive fields by key pattern (password, token, secret)
- [ ] Field allow/deny lists per subscriber

### Metrics
- [ ] Event counts by level
- [ ] Span duration histograms
- [ ] Subscriber latency tracking

## Design Principles

1. **Libraries use core only** — `@moontrace` has zero deps, minimal API
2. **Apps opt into features** — context, file, otlp are separate packages
3. **OTLP-compatible** — core types map to OpenTelemetry semantics
4. **Explicit over implicit** — no magic, especially around async
5. **Zero-cost when disabled** — level gate skips allocation

## Constraints

- **No task-local storage** in MoonBit (and no plans for it)
- **No compile-time macros** — can't eliminate function call overhead for disabled levels
- **Filesystem access** varies by target (native vs JS vs WASM)
