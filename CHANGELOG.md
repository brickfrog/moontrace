# Changelog

All notable changes to moontrace are documented here.

The format is based on [Keep a Changelog 1.1.0](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

Upgrade notes:

- `OtlpHttpTransport` has new `encoder` and `compression` fields; build it with `transport(...)` rather than a struct literal (#93).
- `FileSubscriberConfig` literals need `rotate_every` and `max_age_ms`; prefer `FileSubscriberConfig::new(...)` (#99).
- `Span` literals need `level` and `enabled` fields; use `level: None, enabled: true` (#108).

### Added

- OTLP protobuf and gzip export: `transport(encoder=ProtobufEncoder, compression=GzipCompression)` sends `application/x-protobuf` and/or gzip bodies from `export_spans`, `export_logs`, and their `_report` variants, with the same retry handling. `parse_protobuf_export_response` reads protobuf partial-success replies. `OtlpHttpClient` gains `post_bytes` (with a default that forwards UTF-8 bodies to `post`), implemented by `AsyncHttpClient`. `transport_from_otel_config` applies `OTEL_EXPORTER_OTLP_PROTOCOL` and `OTEL_EXPORTER_OTLP_COMPRESSION`; the managed exporter uses the configured compression (#93).
- Time-based file rotation: `rotate_every=Daily | Hourly` archives the active file by UTC period as `path.<stamp>[.n][.gz]`, size limits within a period add sequence numbers, and `max_age_ms` plus `max_files` prune dated archives. `file_subscriber(clock=...)` and `FileSubscriber::new(config, clock=...)` take an injectable millisecond clock (#99).
- `brickfrog/moontrace/queue`: `queued(sink, capacity?, max_batch?)` puts a bounded, non-blocking queue in front of any async batch sink, with `run`, `flush`, `shutdown`, and `enqueued`/`delivered`/`failed`/`dropped` counters (#99).
- Span levels: `level=` on `span`, `child_span`, `span_with_trace`, `span_from_remote_context`, the `with_span*` wrappers, and the `span_async` helpers is checked against the global and package filters for the caller's package. Disabled spans keep IDs and propagation but emit no lifecycle events and reach no observers, and their children are parented to the nearest enabled ancestor. `Span::is_enabled` reports the result (#108).
- `OTEL_*` environment configuration: `@otlp.parse_otel_config(lookup)` and `otel_config_from_env()` read service name, resource attributes, endpoints (with per-signal semantics), headers, timeout, protocol, compression, sampler, batch settings, and `OTEL_SDK_DISABLED` into an `OtelConfig`, ignoring invalid values with warnings. `OtelConfig::resource()` and `OtelConfig::span_sampler()` apply them, and `@transport.transport_from_otel_config` and `managed_exporter_from_otel_config` build the exporter; a disabled SDK makes that exporter accept nothing (#94).
- `managed_json_exporter(max_queue_records?)` caps the records held in queued and in-flight batches (#94).
- `@otlp.default_resource()` adds `service.name` (default `unknown_service`) and `telemetry.sdk.{name,language,version}`; `Resource::merge` layers resources (#94).
- W3C Baggage: immutable `Baggage` with `get`, `set`, `remove`, `entries`, and `to_header`, plus `parse_baggage`, which never fails. Values are percent-encoded, properties are validated and preserved, and the W3C minimum limits (64 members, 8192 bytes) are enforced (#96).
- Header-map propagation: `inject_headers(headers, ctx, baggage?, format?)`, `inject_span_headers`, and `extract_headers(headers) -> (SpanContext?, Baggage)` with case-insensitive names and W3C, B3 single, and B3 multi formats; injecting removes stale trace headers of every format (#96).
- Console output options: `pretty=true` writes fields on indented lines for local development, and `format=fn(event) { ... }` replaces the layout entirely. Both are accepted by `@console.subscriber`, `@console.initialize`, and (for `pretty`) `@console.initialize_from_env`. `@moontrace.format_event_pretty` exposes the pretty layout (#98).
- `@console.span_observer(min_duration_ms?)` prints one line per completed span with its duration, status, and fields; `@moontrace.format_span_close` exposes the layout (#98).
- `burst_sampler(inner, first, thereafter, window_ns, key?, buckets?, clock?)` keeps the first `first` events per key in each window, then every `thereafter`-th, with bounded hash-bucket counters and `kept()`/`dropped()` (#100).
- `breadcrumbs(inner, capacity?, trigger?)` holds recent events below `trigger` (default `Error_`) and forwards them, oldest first, only when a triggering event arrives; `flush()`, `clear()`, `len()`, `flushed()`, and `dropped()` manage and report the ring (#100).

## [0.16.0] - 2026-10-31

Requires the MoonBit 0.10.18 toolchain. Upgrade notes for code that constructs
moontrace values directly or relies on previous defaults:

- `Event` literals need `file` and `line` fields; use `file: "", line: 0` when there is no call site, or `{ ..event, fields }` to copy an existing event (#90).
- JSON output and OTLP log records now include the caller's location (`file`/`line` keys and `code.file.path`/`code.line.number` attributes) for events logged through the public API (#90).
- Span observers, including the OTLP and flame exporters, no longer receive unsampled spans (#92).

### Added

- Head sampling at span creation: `set_span_sampler`, `with_span_sampler`, and `reset_span_sampler` install a `SpanSampler` that `span`, `span_with_trace`, `child_span`, and `span_from_remote_context` consult to set the sampled flag. Built-ins are `always_on_sampler`, `always_off_sampler`, `trace_id_ratio_sampler` (same trace-ID hash as `trace_sampler`), `parent_based_sampler`, and `span_sampler` for custom decisions over `SamplingInput`. `Span::is_sampled` reports the decision (#92).
- Events record the caller's `file` (relative to the module root) and `line` from `SourceLoc`. JSON output adds `file` and `line` keys, OTLP log records add `code.file.path` and `code.line.number` attributes unless the event already has fields with those keys, and the console subscriber, `@console.initialize`, `@console.initialize_from_env`, `Event::format`, and `format_event` accept `location=true` to show `file:line`. Span lifecycle events have no location (#90).
- JSON subscriber options for log shippers: `timestamp=Rfc3339`, `flatten=true` (fields become top-level keys; colliding keys are prefixed with `fields.` until unique), `trace_ids=true` (span `trace_id`/`span_id` become top-level keys), and `keys=json_keys(...)` for renaming top-level keys. `@json.event_json` builds the record directly; defaults are unchanged (#97).
- `brickfrog/moontrace/logfmt` package with `subscriber`, `initialize`, and `format_event` for logfmt output (#40).
- `format_timestamp_rfc3339` formats millisecond timestamps as RFC 3339 UTC.

### Changed

- Span observers, and therefore the OTLP and flame exporters, no longer receive unsampled spans. Unsampled spans still get IDs and propagate their sampled flag. The default sampler, `parent_based_sampler(always_on_sampler())`, matches the previous flag behavior (#92).

## [0.15.0] - 2026-10-31

Requires the MoonBit 0.10.18 toolchain. Upgrade notes for code that constructs
moontrace values directly or relies on previous defaults:

- `Span` and `OtlpSpan` literals need `events: []`, and `OtlpLogRecord` literals need `trace_id` and `span_id` (#84, #89, #95).
- `OtlpValue` has new `ArrayVal` and `KvlistVal` variants; exhaustive matches need new arms (#95).
- Root spans are now sampled by default (#83), and module filters now also apply to subpackages (#85).
- Promoted trait methods such as `level.compare(other)` are deprecated (#82).

### Added

- Explicit bound loggers: `logger(fields?, span?)` binds fields and optional span correlation, `Logger::bind` derives independent children, `Logger::in_span` associates a span, and `trace`/`debug`/`info`/`warn`/`error`/`event` emit through the existing filters and subscriber. Bound JSON is copied for isolation.
- `@console.initialize_from_env()` installs a stderr console subscriber with Info default, automatic color, and `MOONTRACE_LOG` filters; invalid filters are rejected before any state changes.
- `with_span`, `with_span_ctx`, and `with_child_span` accept raising callbacks, recording the failure and closing the span exactly once while preserving the original error type and non-raising callers (#75).
- `ExportReport` and the `export_json_report`/`export_spans_report`/`export_logs_report` transport methods expose OTLP partial-success details (`rejected_spans`, `rejected_log_records`, `error_message`) (#79).
- `ManagedJsonExporter` (`managed_json_exporter`) connects synchronous tracing to bounded, timed OTLP/HTTP JSON delivery with `run`, `flush`, `shutdown`, and delivery statistics; see [docs/managed-otlp.md](docs/managed-otlp.md) (#80).
- `with_remote_span_async` runs async request work in a span parented by incoming trace context, with the same lifecycle guarantees as the other async span helpers (#81).
- `enabled(level)` reports whether an event from the caller's package would reach the installed subscriber, so callers can skip building expensive messages and fields (#87).
- Bound loggers can carry their own minimum level via `logger(min_level=...)` or `Logger::with_min_level`, replacing the global and module filters for their events so one request or component can be more verbose or stricter. Children inherit it, and `Logger::enabled` applies the same rule (#91).
- Subscriber combinators `map_events`, `filter_events`, `enrich`, and `with_directives` transform, filter, add computed fields to, or apply package directives to a single subscriber (#88).
- `Span::record_exception(err)` records a raised error as error status plus an `exception` span event with OpenTelemetry `exception.type`/`exception.message` attributes, and `exception_fields(err)` produces the same attributes for log events. Spans gain `events` and `Span::add_event`; the `with_span` family and `span_async` wrappers record raised errors this way. Code constructing `Span` literals directly must add `events: []` (#89).
- OTLP span export includes span events (`OtlpSpanEvent`, JSON `events`, protobuf `Span.events`), and nested JSON field values export as OTLP `arrayValue`/`kvlistValue` instead of stringified JSON. `OtlpSpan` gains an `events` field and `OtlpValue` gains `ArrayVal` and `KvlistVal`, so code constructing spans or matching values exhaustively must be updated (#95).

### Changed

- Pinned CI toolchain moves from MoonBit 0.10.10 to 0.10.18 (`moonc v0.10.18+6c83a7f62`, `moon 0.1.20261028`), via 0.10.11 (#71), 0.10.13 (#72), and 0.10.15 (#75). The removed `f!()`, `for { }`, `fn name[T]`, alias, and `type!` forms were already absent; for 0.10.18, builtin `.to_json()` calls now use `Json(value)`, blackbox tests in `@moontrace/test` qualify package names with `@test.`, and generated interfaces print `Int` as `Int32` with no API change (#82).
- The managed OTLP exporter's fallback error message now reports `status=503` rather than `status=Some(503)`, and reports no status when none was received.
- `moonbitlang/core/json` is now a test-only import of `@moontrace/otlp`; it is used solely by `exporter_test.mbt`, and 0.10.13 reports the package-level import as unused.
- `parse_traceparent` now has regression coverage for non-ASCII headers. Rejection rests on its length and hex validation, which 0.10.13's bracket-slice clamping does not reach: the fixed separator checks keep any surrogate pair wholly inside a slice, so no slice trims and behavior is unchanged.

### Deprecated

- MoonBit 0.10.18 deprecates implicitly promoting trait implementations to regular methods. `Show::to_string` on `Event`, `Field`, `Span`, and `TraceFlags`, and `OtlpHttpClient::post` on `AsyncHttpClient`, are now explicit public methods. Promoted `Eq` (`equal`, `not_equal`), `Compare` (`compare`, `op_lt`, `op_le`, `op_gt`, `op_ge`), `Debug::to_repr`, and `Show::output` methods remain only as deprecated, hidden compatibility methods and will be removed in a later release; use `==`, `<`, `Compare::compare(a, b)`, `@debug.to_string`, or the trait methods instead.

### Fixed

- Simple tracestate keys must start with a lowercase letter, per the W3C key grammar; keys such as `1vendor` were previously accepted. Digit-leading tenant IDs in multi-tenant keys such as `1tenant@vendor` remain valid (#74).
- OTLP conversion now converts moontrace's millisecond clocks to nanoseconds for events and spans, saturating on overflow; previously milliseconds were written into nanosecond fields. HTTP 200 responses reporting a partial rejection now mark the export unsuccessful and non-retryable instead of being discarded (#79).
- Root spans from `span` and `span_with_trace` are now sampled by default (W3C flags `01`), matching the OpenTelemetry default `ParentBased(AlwaysOn)`. Previously they were created with flags `00`, so `traceparent_from_span` told downstream OpenTelemetry services to drop the trace. Child spans and spans from remote context still inherit their parent's flags (#83).
- OTLP log records from span-associated events now carry top-level `traceId`/`spanId` (protobuf fields 9 and 10) so backends link logs to traces; previously correlation existed only as attributes. Only valid W3C IDs are promoted. `OtlpLogRecord` gains `trace_id` and `span_id` fields, so code constructing it directly must set them (empty strings omit them) (#84).
- Module filters, `MOONTRACE_LOG`, and env-filter directives now apply to subpackages: `my/app=debug` also matches `my/app/db` (but not `my/apple`), and the longest matching package wins. Previously only the exact package matched, so parent filters silently did nothing for subpackages (#85).
- Deny-list redaction now also applies to keys inside nested JSON objects and arrays, so secrets inside structured field values are no longer passed through. Allow-list policies keep their top-level behavior (#86).
- Completed-span observations now deep-copy nested JSON in span fields, link fields, and span event fields, so later span changes or other observers cannot alter an already delivered observation.

## [0.14.0] - 2026-08-26

### Changed

- Requires the MoonBit 0.10.10 toolchain. `moonbitlang/protobuf` 0.1.1 and `moonbitlang/async` 0.19.0 no longer parse under it, so dependencies move to `moonbitlang/protobuf@0.1.2` and `moonbitlang/async@0.21.1`, and the pinned CI toolchain moves from 0.10.6 to 0.10.10 (#69).
- `Retry-After` is now read from the OTLP HTTP response with a case-insensitive lookup (`moonbitlang/async/http` 0.21 keys headers by `CaseInsensitiveString`), replacing the previous two-literal `retry-after` / `Retry-After` probe. Casings such as `Retry-after` are now honored. The public `parse_retry_after_ms(Map[String, String])` signature is unchanged (#69).
- `with_trace_state`, `with_span_async`, and `with_child_span_async` now release their scope with `defer` instead of a catch-all handler that re-raised. State restore and span exit now also run on async cancellation paths that a catch-all will stop capturing in a future compiler. Error-message recording still runs in `catch`, which is the only construct that can observe the error value (#69).

## [0.13.1] - 2026-08-01

### Security

- Human-readable event messages, field keys, and trace-context diagnostics now render C0/C1 control codes as visible escapes, preventing injected line breaks and terminal control sequences while leaving structured JSON unchanged.
- W3C `traceparent` and `tracestate` parsing now rejects inputs over 512 characters before eager allocation; `tracestate` also rejects duplicate wire keys instead of applying last-write-wins behavior.
- Trace and span identifier generation now seeds ChaCha8 from 32 bytes of platform entropy when available, with the existing clock-derived seed retained only as a documented fallback.
- Newly created native file-subscriber logs and gzip rotations request owner-only `0600` permissions on Unix. Existing file modes are not changed.
- The default OTLP HTTP client now streams response bodies with a 64 KiB ceiling. Oversized responses fail as non-retryable request errors.
- GitHub workflows now install a pinned MoonBit toolchain and core from versioned archives whose SHA-256 digests are verified before extraction, replacing the mutable remote installer pipeline.

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
