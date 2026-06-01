# Changelog

All notable changes to moontrace are documented here.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.13.0] - 2026-06-01

### Added

- OTLP protobuf export: the `ProtobufEncoder` in `@moontrace/otlp/transport` now encodes `ExportTraceServiceRequest` / `ExportLogsServiceRequest` to protobuf wire bytes (`application/x-protobuf`), hand-rolled against the `moonbitlang/protobuf` runtime — no codegen or external OTLP bindings. Trace/span IDs are written as bytes, timestamps as fixed64, span flags as fixed32; the wire format is checked by round-trip decode and a golden fixture generated from `google.protobuf`. Select the encoding via `OtlpEncoder`; the JSON path is unchanged (#63).

## [0.12.0] - 2026-06-01

Adds the native buffered file subscriber package.

### Added

- `@moontrace/file` native buffered file subscriber (#60): a synchronous, non-blocking subscriber that enqueues into a bounded queue (drops + counts on overflow, never blocks the logging call site) paired with an async worker that drains in bounded batches and yields cooperatively. Supports append, size-based rotation, retention cleanup, and optional gzip of rotated files (via `moonbitlang/async/gzip`). Explicit async `flush()` / `shutdown()` that always terminate (falling back to a direct drain if the worker has stopped) and expose `dropped()` / `written()` counts. Native-only — non-native targets fail loudly with a clear error rather than silently dropping. See `docs/file.md`.

## [0.11.0] - 2026-06-01

Adds output-side subscriber layers for field redaction and sampling, plus a folded-stack flame exporter.

### Added

- Field redaction: a composable `redact(inner, policy?)` subscriber wrapper with `RedactionPolicy` (case-insensitive substring deny, case-insensitive exact allowlist, `Redact`/`Drop` modes; defaults deny `password`/`token`/`secret`). Builds a fresh redacted event without mutating the original, so other composed subscribers still see unredacted fields (#56).
- `@moontrace/flame` folded/flame exporter: `fold_spans(Array[Span]) -> String` produces deterministic collapsed-stack output (per-span self-time, identical stacks summed, trace-scoped, cycle-safe, names sanitized) plus a `FlameExporter` driven by the span lifecycle observer. `docs/flame.md` shows piping the output to inferno / flamegraph.pl (#57).
- Composable sampling layers: `RatioSampler` (percentage, injectable random), `RateLimiter` (fixed-window, injectable clock), and `TraceSampler` plus the pure `should_sample_trace(trace_id, ratio)` predicate and `sample_trace_decision` (honors a parent `TraceFlags` sampled bit). Each exposes kept/dropped counts; decisions are deterministic via injected sources. Tail sampling is deferred (see `docs/sampling.md`) (#58).

## [0.10.0] - 2026-06-01

Adds distributed tracing support, environment-driven filtering, and the OTLP
export/transport stack. Includes one filtering-semantics change covered in
Migration.

### Added

- Span lifecycle observers: `SpanLifecycleObserver`, `set_span_observer` / `clear_span_observer`, `completed_span_observer`, and `compose_span_observers` (#42).
- Scoped state guards that snapshot and restore global tracing state: `with_subscriber`, `with_min_level`, `with_module_filter`, `with_global_field` / `with_global_fields`, and `with_trace_state` (#43).
- Span-scoped event correlation: `info_in_span` / `debug_in_span` / `warn_in_span` / `error_in_span` / `trace_in_span` / `event_in_span` and the `Span::info` / `debug` / `warn` / `error` / `event` methods, which stamp `trace_id` / `span_id` / `parent_span_id` onto events (#46).
- `@moontrace/test` `TestSubscriber` and assertion utilities for testing instrumentation (#47).
- `@moontrace/span_async` optional async span instrumentation package (#48).
- W3C trace-context propagation: validated `TraceId`, `SpanId`, `TraceFlags`, `TraceState`, and `SpanContext` types; `parse_traceparent` / `format_traceparent`, `parse_tracestate` / `format_tracestate`, `parse_span_context`; and `span_from_remote_context` for creating a child span from a remote context while preserving the sampled flag (#49).
- EnvFilter-style directive parsing: `parse_env_filter`, `set_filter_from_directives`, and `initialize_from_env` (reads `MOONTRACE_LOG`), with a structured `EnvFilterError` for invalid directives (#50).
- OTLP `Resource` and `InstrumentationScope` attributes wired into the export envelope (`service.name` / `service.version`), plus an explicit batch-exporter `shutdown()` lifecycle (#51).
- `@moontrace/otlp/transport`: OTLP HTTP JSON transport over `moonbitlang/async/http` with an injectable `OtlpHttpClient`, a pure retry classifier, and bounded retry/backoff (async confined to this package; native + js only) (#52).
- OTLP protobuf encoder seam (`OtlpEncoder`, `OtlpPayload`) with a working JSON encoder and an explicitly stubbed protobuf path, plus `docs/otlp-protobuf-design.md` (#53).
- Span links and follows-from: links are stored on the span, created from a local span or a remote `SpanContext` (`Span::link` / `follows_from` / `link_context` / `follows_from_context`), and exported as OTLP `links` and in the JSON span output, distinct from the parent relationship (#54).

### Changed

- Per-package level filters now **override** the global minimum level for matching packages in both directions — a package directive can be more verbose *or* stricter than the global default — instead of being AND-gated below it (#50). See Migration.
- `OtlpSpan` gained `flags : Int` (#49/#51) and `links : Array[OtlpLink]` (#54) fields.

### Migration

- **Filtering semantics:** previously a per-package filter could only further restrict events below the global `set_min_level`; now a package's configured level is the authoritative threshold for that package. This is what makes `MOONTRACE_LOG=info,my/pkg=debug` emit `debug` from `my/pkg` while everything else stays at `info`. If you relied on the global minimum acting as a hard floor over module filters, set the per-package levels (or global minimum) accordingly.
- **`OtlpSpan` construction:** if you build `OtlpSpan` via a struct literal, add the new `flags` and `links` fields.

## [0.9.3] - 2026-05-23

### Changed

- Migrated project metadata to the active `moon.mod` format.
- Upgraded `moonbitlang/async` from `0.17.1` to `0.19.0`.
- Updated `Show` implementation declarations to the current trait syntax.

## [0.9.1] - 2026-05-13

### Changed

- MoonBit 2026-05-12 toolchain compatibility (`moon 0.1.20260512`, `moonc v0.9.2`); replaced deprecated `StringBuilder::new()` with `StringBuilder()`. No API or formatting changes.

## [0.9.0] - 2026-04-29

### Added

- `Debug` derive on public data types (`Event`, `Field`, `Level`, `Span`, `SpanKind`, `SpanStatus`, and the OTLP value/export types), matching the MoonBit `Show` → `Debug` migration. Manual `Show` formatting is unchanged.

### Changed

- April 27 MoonBit toolchain compatibility; bumped `moonbitlang/async` to `0.17.1`.
- Replaced deprecated `StringView.to_string()` calls with `to_owned()`.

## [0.8.0] - 2026-04-12

### Changed

- Trace and span IDs are now generated by a ChaCha8 PRNG seeded from process startup time, removing the same-nanosecond collision risk of the old timestamp+counter scheme. IDs are no longer temporally ordered; OTLP zero-value checks are enforced.
- `with_child_span` no longer pushes a redundant `"parent"` event field; the parent relationship is carried by `parent_span_id`.

### Migration

- Trace IDs are no longer sortable by time.
- Read `span.parent_span_id` instead of a `"parent"` event field.

## [0.7.0] - 2026-04-08

### Added

- `SpanKind` wired to `Span`: `kind` field (default `Internal`), `with_kind()` builder, and a `kind?` parameter on `span()` / `span_with_trace()`. OTLP export uses the span kind.
- `format_timestamp_utc` (replaces the now-deprecated `format_timestamp_hms`).

### Changed

- `span_to_otlp()` takes a single `Span` parameter, reading `trace_id` / `parent_span_id` / `status` / `status_message` / `kind` directly.
- `json_to_otlp_value` maps integral numbers to `IntVal` and fractional to `DoubleVal`.
- `Span::enter()` returns early if already active (symmetry with `exit()`).
- `with_child_span` records the parent `span_id` instead of the parent name.

### Migration

- `span_to_otlp()` dropped its `trace_id?` / `parent_span_id?` / `status_code?` / `status_message?` override params for a single `Span` argument.

## [0.6.0] - 2026-04-05

### Added

- `field()` constructor with `ToJson` trait dispatch; `Span::record()`, `Span::with_field()`, and `set_global_field()` accept any `ToJson` value.

### Changed

- `tap()` renamed to `intercept()` (runs the callback before the subscriber; use `compose()` for passive observation).
- `set_status()` clears `status_message` on non-error status.
- Stdlib modernization and idiomatic cleanups; `emit()` returns early when no subscriber is set.

### Migration

- Replace `tap()` with `intercept()` (or `compose()` for passive taps).

## [0.5.1] - 2026-03-28

### Fixed

- Console timestamp unit mismatch: `format_timestamp_hms` divided by 1,000,000 assuming nanoseconds, but `@env.now()` returns milliseconds.

## [0.5.0] - 2026-03-27

### Added

- Error integration: `Span::set_status(status, message?)` and `Span::record_error(msg)`; status is included in span exit events, `to_json()`, and `Show` output.
- Console visual overhaul: human-readable `HH:MM:SS.mmm` timestamps, pipe-separated columns, automatic source-module display, shared `format_event()`, and `format_timestamp_hms()`.

### Changed

- `Span::exit()` is now idempotent.

## [0.4.1] - 2026-03-27

### Fixed

- `Span::exit` is idempotent (no duplicate events / `end_time` overwrite).
- Removed duplicate ID generation in the OTLP package (trace/span ID collision risk).
- JSON subscriber delegates to `Event::to_json()` for consistent timestamp serialization.

## [0.4.0] - 2026-03-25

### Added

- Global context fields: `set_global_field` / `get_global_field` / `remove_global_field` / `clear_global_fields`, injected into every event (explicit fields override on collision).
- Per-module filtering by package via `set_module_filter` / `clear_module_filters`, using `SourceLoc` package extraction; populates `Event.source`. Span events bypass module filtering and use only the global gate.

## [0.3.0] - 2026-03-25

### Added

- OTLP-aligned spans: native `trace_id` (32 hex) / `span_id` (16 hex), `parent_span_id` propagation via `with_child_span()`, `SpanKind` and `SpanStatus` enums, and `next_trace_id()` / `next_span_id()` in core.

## [0.2.0] - 2026-03-24

### Added

- `@moontrace/otlp` OTLP JSON export: `OtlpSpan` / `OtlpLogRecord` / `OtlpAttribute` / `OtlpValue`, `event_to_log_record()` / `span_to_otlp()` / `field_to_attribute()`, `wrap_log_records()` / `wrap_spans()` envelopes, and a batching `OtlpExporter`.
- `with_span_ctx` / `with_child_span`, `Show` for `Event` / `Span` / `Field`, `Span::with_field()`, `EventBuffer`, `Field::to_json()`, `Level::from_string()`, `set_min_level` / `get_min_level`, `Event::format(color?)`, `level_color()`, and `noop()` / `tap()` subscribers.

## [0.1.0] - 2026-03-24

### Added

- Initial release: structured events at five levels with arbitrary fields; spans with enter/exit duration tracking, `record()`, and `with_field()`; `with_span` / `with_span_ctx` / `with_child_span` helpers; pluggable subscribers.
