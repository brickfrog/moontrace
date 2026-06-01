# OTLP Protobuf Export Design

## Requirement

moontrace already exports OTLP-shaped JSON for traces and logs. The existing
`brickfrog/moontrace/otlp/transport` package posts JSON strings through
`OtlpHttpClient::post`, and the OTLP envelopes are built by
`@otlp.wrap_spans` and `@otlp.wrap_log_records`.

OTLP protobuf export is the same transport family, but it is not a string-body
variant of the current path:

- The HTTP body is binary protobuf bytes, not JSON text.
- The content type is `application/x-protobuf`, not `application/json`.
- Trace export uses the
  `opentelemetry.proto.collector.trace.v1.ExportTraceServiceRequest` message,
  whose top-level field is repeated `ResourceSpans`.
- Log export uses the
  `opentelemetry.proto.collector.logs.v1.ExportLogsServiceRequest` message,
  whose top-level field is repeated `ResourceLogs`.
- The existing resource and instrumentation-scope envelope builders map
  directly to `ResourceSpans.resource`, `ResourceSpans.scope_spans`,
  `ResourceLogs.resource`, and `ResourceLogs.scope_logs`.

The important boundary for this bead is that protobuf support needs a future
binary encoder and a bytes-capable client/body path. It should not disturb the
current JSON transport, which remains string based and already tested.

## Prior Art And Runtime Maturity

The read-only `ryota0624/moonbit_otel` reference generates MoonBit OTLP
bindings with `buf` plus a local `protoc-gen-mbt.exe` plugin. Its
`buf.gen.yaml` targets a generated MoonBit project named
`opentelemetry_proto_mbt`, with `json=true`, `async=false`, and username
`ryota0624`.

The generated packages import `moonbitlang/protobuf`, aliased as `@protobuf`.
Generated code uses `@protobuf.Sized`, `@protobuf.Read`, `@protobuf.Write`,
`@protobuf.Enum`, `@protobuf.Writer`, `@protobuf.size_of`, `read_message`,
`write_varint`, `write_uint32`, `write_fixed32`, `write_fixed64`,
`write_bytes`, `write_string`, and JSON helpers such as `base64_encode` and
`base64_decode`. The reference module pins `moonbitlang/protobuf` at `0.1.1`
and `moonbitlang/async` at `0.16.6`, while moontrace currently uses
`moonbitlang/async@0.19.0`.

That makes the protobuf ecosystem promising but still immature for direct
adoption here. There is a real runtime package and generated bindings can emit
OTLP collector request messages, but the generator is custom, the generated
surface is large, and the reference stack is older than moontrace's current
async dependency. Treat it as a design signal, not something moontrace should
vendor or depend on casually.

## Options

### 1. buf plus protoc-gen-mbt codegen

This path follows the moonbit_otel shape: run `buf` against
`opentelemetry-proto`, generate MoonBit packages for the collector, trace, log,
resource, and common schemas, and depend on `moonbitlang/protobuf`.

Pros:

- Best long-term alignment with OpenTelemetry's canonical `.proto` files.
- Avoids manually tracking numeric tags, wire types, and nested message shapes.
- Gives moontrace a path to logs, traces, and later metrics without repeatedly
  writing bespoke serializers.
- Reuses a real protobuf runtime instead of carrying local wire-format code.

Cons and risks:

- Adds a protobuf runtime dependency and a code generation step.
- Requires deciding whether generated code is checked in, regenerated in CI, or
  kept in a separate mooncake.
- The currently observed generator is custom (`protoc-gen-mbt.exe`) and the
  reference pins older dependencies.
- Generated APIs may expose more OTLP surface than moontrace wants to support
  at first, so a small mapping layer is still needed.

### 2. Hand-roll a minimal OTLP protobuf writer

This path writes only the fields moontrace currently emits:
`ExportTraceServiceRequest`, `ResourceSpans`, `ScopeSpans`, `Span`, `Status`,
`Resource`, `InstrumentationScope`, `KeyValue`, `AnyValue`,
`ExportLogsServiceRequest`, `ResourceLogs`, `ScopeLogs`, and `LogRecord`.
The implementation would encode varints plus length-delimited, fixed32, and
fixed64 fields directly into `Bytes`.

Pros:

- Small dependency footprint: no protobuf runtime and no code generation.
- Can be scoped tightly to moontrace's current trace/log model.
- Easy to keep the public API narrow.

Cons and risks:

- High correctness burden. OTLP protobuf is unforgiving: hex IDs become bytes,
  timestamps have fixed64 wire tags, strings are length-delimited, enum values
  are varints, and nested messages need exact size prefixes.
- Maintenance cost grows whenever moontrace adds events, links, trace state,
  dropped counts, schema URL, metrics, or richer AnyValue support.
- Tests must compare against canonical protobuf fixtures or a collector/parser;
  otherwise a green suite could still produce invalid wire bytes.
- It duplicates work that the protobuf runtime and generator are meant to own.

### 3. Vendor or reuse moonbit_otel generated bindings

This path copies or depends on `ryota0624/opentelemetry_proto_mbt` and maps
moontrace's `@otlp` structs into those generated message structs.

Pros:

- Fastest way to get complete OTLP message structs and serializers.
- The generated trace/log collector requests already match the message names
  moontrace needs.
- Gives a concrete integration example for `application/x-protobuf` and
  `Bytes` HTTP bodies.

Cons and risks:

- The reference stack is pinned to older async/protobuf packages.
- Vendoring generated code would add a large maintenance surface to moontrace.
- Depending directly on the reference package couples moontrace's compatibility
  to another project's release cadence.
- Generated code shape may change if the custom plugin changes.

## Recommendation

Use option 1, but do it as a follow-up implementation bead rather than inside
this design bead.

The recommended path is to introduce an official generated-binding layer from
OpenTelemetry's `.proto` definitions, backed by `moonbitlang/protobuf`, and
keep moontrace's own hand-written code limited to mapping existing
`@otlp.OtlpSpan`, `@otlp.OtlpLogRecord`, `Resource`, and
`InstrumentationScope` values into the generated request messages.

This keeps moontrace aligned with OTLP, avoids local wire-format ownership, and
preserves the current JSON path. The risk is dependency maturity, so the next
bead should first prove the current `moonbitlang/protobuf` package and generator
against moontrace's current toolchain before committing to generated code in
the main package.

Hand-rolling is tempting because moontrace currently emits a small subset of
OTLP, but it creates the exact long-term maintenance trap protobuf codegen is
supposed to avoid. Vendoring moonbit_otel is useful as a reference, but its
older-stack pinning and broad generated surface make it a risky default.

## Integration Points

This bead adds the non-invasive slot:

- `OtlpPayload` is the encoded body plus content type.
- `OtlpEncoder` chooses JSON or protobuf.
- JSON encoding delegates to `@otlp.wrap_spans` and
  `@otlp.wrap_log_records`, then UTF-8 encodes the stringified JSON into bytes.
- Protobuf encoding is intentionally stubbed with
  `EncodingError::ProtobufNotImplemented`.

The follow-up protobuf bead should wire these pieces into transport without
rewriting today's JSON code:

- Add a bytes-capable HTTP client method or body variant, for example a
  separate `post_bytes(url, body : Bytes, headers)` method or a request body
  enum with `StringBody(String)` and `BytesBody(Bytes)`.
- Use `OtlpEncoder::content_type()` to set `Content-Type` at the final send
  boundary.
- Preserve `export_spans` and `export_logs` JSON defaults, then add explicit
  protobuf construction/configuration so applications opt into binary export.
- Keep JSON envelope builders as the source of truth for JSON; do not route JSON
  through generated protobuf JSON helpers.

Span flags need a dedicated mapping check. moontrace currently stores
`OtlpSpan.flags` as an `Int` and JSON emits it as `flags`. OTLP protobuf's
`Span.flags` is field 16 and is written as fixed32 in the generated
moonbit_otel bindings. The follow-up must define the conversion from
moontrace's span trace flags to the OTLP fixed32 value and test sampled versus
unsampled spans explicitly.

## Proposed Follow-up Bead

`moontrace-cg9.7.4`: implement OTLP protobuf export behind the encoder seam.

Scope:

- Evaluate the current `moonbitlang/protobuf` release with moontrace's toolchain
  and `moonbitlang/async@0.19.0`.
- Generate or import only the OTLP packages needed for traces and logs:
  collector trace/logs, trace/logs, resource, and common.
- Add generated bindings in a contained package or dependency; do not place
  generated code inside `src/otlp/transport`.
- Implement protobuf `encode_spans` and `encode_logs` by mapping moontrace OTLP
  structs into generated `ExportTraceServiceRequest` and
  `ExportLogsServiceRequest` messages.
- Add a bytes-capable transport send path with `application/x-protobuf`, while
  keeping the existing string JSON client path intact.
- Verify against golden protobuf bytes generated by a known-good implementation
  or by decoding the produced bytes through generated `@protobuf.Read`.
- Include collector-level integration smoke tests if a lightweight local
  collector fixture is practical.

Dependencies and exit criteria:

- No protobuf dependency is added until codegen compiles and native tests pass.
- `moon info && moon fmt` must leave generated interfaces clean.
- `moon test --target native` and `moon build --target native --release` must
  pass.
