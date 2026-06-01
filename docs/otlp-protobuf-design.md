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

For `moontrace-cg9.7.4`, `moon add moonbitlang/protobuf` resolved
`moonbitlang/protobuf@0.1.1`; the local registry index contained `0.1.0` and
`0.1.1`, making `0.1.1` the latest available runtime at implementation time.
A spike that wrote and read length-delimited bytes/string, varint, fixed64,
and fixed32 values through the official runtime passed
`moon build --target native --release` and `moon test --target native` against
moontrace's current `moonbitlang/async@0.19.0`.

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

The long-term preference remains an official generated-binding layer from
OpenTelemetry's `.proto` definitions, backed by `moonbitlang/protobuf`, once
the MoonBit protobuf generator and generated package surface are mature enough
for moontrace to own confidently.

For `moontrace-cg9.7.4`, the chosen implemented path is option 2 with an
important constraint: moontrace hand-rolls only the minimal OTLP trace and log
messages it emits, but delegates all primitive protobuf writing to the official
`moonbitlang/protobuf@0.1.1` runtime. It does not vendor or depend on
`ryota0624/opentelemetry_proto_mbt`, and it does not introduce a codegen step.

The implementation writes:

- Traces:
  `ExportTraceServiceRequest.resource_spans`,
  `ResourceSpans.resource`, `ResourceSpans.scope_spans`,
  `ScopeSpans.scope`, `ScopeSpans.spans`, `Span`, `Span.Link`, and `Status`.
- Logs:
  `ExportLogsServiceRequest.resource_logs`, `ResourceLogs.resource`,
  `ResourceLogs.scope_logs`, `ScopeLogs.scope`, `ScopeLogs.log_records`, and
  `LogRecord`.
- Supporting messages:
  `Resource`, `InstrumentationScope`, `KeyValue`, and `AnyValue` for the
  current moontrace value variants: string, bool, int64, and double.

Field numbers and wire types are copied from the read-only generated
moonbit_otel bindings. Trace IDs and span IDs are decoded from hex strings to
protobuf bytes. Span timestamps and log timestamps are fixed64. Span flags are
field 16 with fixed32 wire type. Enum-valued Moontrace integers are encoded as
varints after rejecting negative values. Nested messages are written into a
temporary buffer, then length-prefixed into their parent.

The JSON encoder path remains unchanged and still delegates to
`@otlp.wrap_spans` and `@otlp.wrap_log_records`.

## Integration Points

This bead adds the non-invasive slot:

- `OtlpPayload` is the encoded body plus content type.
- `OtlpEncoder` chooses JSON or protobuf.
- JSON encoding delegates to `@otlp.wrap_spans` and
  `@otlp.wrap_log_records`, then UTF-8 encodes the stringified JSON into bytes.
- Protobuf encoding now returns `application/x-protobuf` with binary
  `ExportTraceServiceRequest` or `ExportLogsServiceRequest` bytes.
- Protobuf encoding can return `EncodingError::ProtobufEncodeFailed` if an ID
  is not valid hex, an enum-like integer is negative, or the runtime writer
  raises an error.

Future transport work can wire these pieces into the send path without
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

Span flags now have the dedicated mapping check this design called out.
moontrace stores `OtlpSpan.flags` as an `Int`; protobuf rejects negative values
and writes non-zero flags as `Span.flags` field 16 with fixed32 wire type.

## Implemented Bead

`moontrace-cg9.7.4` implements OTLP protobuf export behind the encoder seam.

Scope:

- Evaluated `moonbitlang/protobuf@0.1.1` with moontrace's toolchain and
  `moonbitlang/async@0.19.0`.
- Added `moonbitlang/protobuf@0.1.1` as a dependency.
- Implemented protobuf `encode_spans` and `encode_logs` by hand-writing the
  minimal OTLP messages moontrace emits with official runtime writer
  primitives.
- Kept the existing string JSON client path intact.
- Added round-trip decoder tests that inspect key trace, log, resource, scope,
  status, attributes, timestamps, IDs, and flags.
- Added a golden-byte test for one representative `ExportTraceServiceRequest`.
  The golden fixture was produced from a Python `google.protobuf` 7.34.1 dynamic
  descriptor for the same OTLP subset. This checks field numbers, wire types,
  nested length prefixes, and canonical field ordering for the representative
  trace request.

Dependencies and exit criteria:

- No dependency is taken on `ryota0624/opentelemetry_proto_mbt`, and no
  `protoc-gen-mbt` or `buf` codegen toolchain is wired into moontrace.
- `moon info && moon fmt` must leave generated interfaces clean.
- `moon test --target native` and `moon build --target native --release` must
  pass.
