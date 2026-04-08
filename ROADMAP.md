# moontrace Roadmap

Feature gap analysis vs Rust's `tracing` and Python's `loguru`, prioritized for MoonBit's constraints.

## Current State (v0.6.0)

- Events: info/warn/error/debug/trace with structured fields
- Automatic source location via `#callsite(autofill(loc~))` + `SourceLoc`
- Event.source field populated with package name
- Spans: enter/exit/duration, record(), with_field(), with_span_ctx, with_child_span
- Span IDs: trace_id (32 hex), span_id (16 hex), parent_span_id — auto-generated, propagated
- SpanKind (Internal/Server/Client/Producer/Consumer), SpanStatus (Unset/Ok/SpanError)
- span_with_trace() for custom trace ID injection (cross-process correlation)
- Span error integration: set_status(), record_error(), error fields in exit events
- Subscribers: JSON, console, OTLP JSON export
- Composition: compose(), with_filter(), noop(), intercept(), EventBuffer
- Performance: global level gate (set_min_level), per-module filtering (set_module_filter)
- Global context fields: set_global_field/get_global_field/remove_global_field/clear_global_fields
- Serialization: to_json() on Event/Span/Field, Event.format(color?)
- Show trait on all types, Level.from_string()
- Cross-platform: native, JS, WASM-GC
- CI: GitHub Actions testing all 3 backends

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

## ~~Phase 4: Error Integration~~ DONE (v0.5.0)

- [x] `Span.set_status(status, message?)` — set SpanStatus on a span
- [x] `Span.record_error(msg)` — records error message and auto-sets status to SpanError
- [x] Error fields included in span exit events
- [x] `with_span` variants that catch errors and auto-record them on the span

```moonbit
@moontrace.with_span_ctx("db_query", fn(s) {
  match run_query() {
    Ok(result) => s.set_status(Ok)
    Err(e) => s.record_error(e.to_string())  // sets SpanError + records message
  }
})
```

## Phase 5: File Management (`@moontrace/file`)

Production log file output with rotation and retention. **Native-only initially.**

### Research Findings (2026-03-25)

**Available:** `@moonbitlang/async/fs` provides full async file I/O on native target:
- `open()`, `write()`, `read()` with append mode
- `File::size()` for rotation checks
- `readdir()` for retention cleanup
- `File::lock()` for multi-process safety
- `BufferedWriter` for batched writes

**Architecture challenge:** Subscriber interface is synchronous `(Event) -> Unit` but file I/O is async. Solution: buffer events synchronously (EventBuffer already exists), flush to disk asynchronously on timer/capacity.

**Target support:**
| Feature | Native | JS | WASM-GC |
|---------|--------|-----|---------|
| File I/O | `@moonbitlang/async/fs` | Node.js fs via JS FFI | No WASI support |
| Compression | External `gzip` process | Node.js zlib | Not available |

**No compression packages** exist in mooncakes. Options: external `gzip` process, C FFI to zlib, or skip compression initially.

### Implementation Plan

- [ ] Native-only file subscriber using `@moonbitlang/async/fs`
- [ ] Synchronous buffering → async flush pattern (keeps `(Event) -> Unit` interface)
- [ ] Size-based rotation via `File::size()`
- [ ] Retention via `readdir()` + `remove()`
- [ ] Compression via external `gzip` process (optional)
- [ ] JS target support via Node.js `fs/promises` FFI (later)

**Priority: Low.** Most MoonBit apps log to stdout/console. File management is a production deployment feature — important eventually but not blocking anyone right now.

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
- **Filesystem access** — native only via `@moonbitlang/async/fs`, JS via FFI, no WASM support
- **Async subscriber gap** — file I/O is async but subscriber interface is sync; bridge via buffering
