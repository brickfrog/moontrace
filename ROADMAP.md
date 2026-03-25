# moontrace Roadmap

Feature gap analysis vs Rust's `tracing` and Python's `loguru`, prioritized for MoonBit's constraints.

## Current State (v0.4.0)

- Events: info/warn/error/debug/trace with structured fields
- Automatic source location via `#callsite(autofill(loc~))` + `SourceLoc`
- Event.source field populated with package name
- Spans: enter/exit/duration, record(), with_field(), with_span_ctx, with_child_span
- Span IDs: trace_id (32 hex), span_id (16 hex), parent_span_id — auto-generated, propagated
- SpanKind (Internal/Server/Client/Producer/Consumer), SpanStatus (Unset/Ok/SpanError)
- span_with_trace() for custom trace ID injection (cross-process correlation)
- Subscribers: JSON, console, OTLP JSON export
- Composition: compose(), with_filter(), noop(), tap(), EventBuffer
- Performance: global level gate (set_min_level), per-module filtering (set_module_filter)
- Global context fields: set_global_field/get_global_field/remove_global_field/clear_global_fields
- Serialization: to_json() on Event/Span/Field, Event.format(color?)
- Show trait on all types, Level.from_string()
- Cross-platform: native, JS, WASM-GC
- CI: GitHub Actions testing all 3 backends
- 107 tests

## ~~Phase 1: OTLP Alignment (Core)~~ DONE (v0.3.0)

- [x] Add `SpanKind` enum to core
- [x] Add `SpanStatus` enum to core
- [x] Move trace/span ID generation from otlp to core
- [x] Add `trace_id` and `span_id` fields to core `Span` struct
- [x] `with_child_span` propagates trace_id and sets parent_span_id
- [x] `span_with_trace()` for custom trace ID injection

## ~~Phase 2: Context System~~ DONE (v0.4.0)

- [x] Global context: `set_global_field(key, value)`, `get_global_field(key)`
- [x] Auto-inject global context fields into emitted events
- [x] `remove_global_field(key)`, `clear_global_fields()` for cleanup/test isolation
- [x] Fast-path: zero overhead when no context is set
- [x] Explicit fields override context on key collision (dedup)
- [x] Span-bound context via existing `span.record()` — no separate API needed

## ~~Phase 3: Per-Module Filtering~~ DONE (v0.4.0)

- [x] `set_module_filter(package_name, level)` for per-package min levels
- [x] Automatic source location via `#callsite(autofill(loc~))` + `SourceLoc`
- [x] `Event.source` field populated from SourceLoc package name
- [x] `clear_module_filters()` for test isolation
- [x] Span events bypass module filtering (use global `set_min_level` only)

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
