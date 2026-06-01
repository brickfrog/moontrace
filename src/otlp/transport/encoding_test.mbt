///|
fn encoding_test_span(name : String) -> @otlp.OtlpSpan {
  @otlp.OtlpSpan::{
    trace_id: "0000000000000000000000000000000a",
    span_id: "000000000000000b",
    parent_span_id: "",
    flags: 0,
    name,
    kind: 1,
    start_time_unix_nano: (100 : UInt64),
    end_time_unix_nano: (200 : UInt64),
    attributes: [],
    links: [],
    status_code: 1,
    status_message: "",
  }
}

///|
fn encoding_test_log_record(body : String) -> @otlp.OtlpLogRecord {
  @otlp.OtlpLogRecord::{
    time_unix_nano: (100 : UInt64),
    severity_number: 9,
    severity_text: "INFO",
    body,
    attributes: [],
  }
}

///|
fn decode_payload_body(payload : @transport.OtlpPayload) -> String {
  @utf8.decode(payload.body) catch {
    _ => abort("invalid UTF-8 payload body")
  }
}

///|
fn parse_payload_json(payload : @transport.OtlpPayload) -> Json {
  let text = decode_payload_body(payload)
  @json.parse(text) catch {
    err => abort("invalid OTLP JSON payload: \{err}")
  }
}

///|
fn assert_json_eq(actual : Json, expected : Json) -> Unit {
  if actual.stringify() != expected.stringify() {
    abort("expected \{expected.stringify()}, got \{actual.stringify()}")
  }
}

///|
priv struct DecodedAnyValue {
  string_value : String?
  bool_value : Bool?
  int_value : Int64?
  double_value : Double?
}

///|
priv struct DecodedKeyValue {
  key : String
  value : DecodedAnyValue
}

///|
priv struct DecodedResource {
  attributes : Array[DecodedKeyValue]
}

///|
priv struct DecodedScope {
  name : String
  version : String
  attributes : Array[DecodedKeyValue]
}

///|
priv struct DecodedStatus {
  message : String
  code : UInt
}

///|
priv struct DecodedSpan {
  trace_id : Bytes
  span_id : Bytes
  parent_span_id : Bytes
  flags : UInt
  name : String
  kind : UInt
  start_time_unix_nano : UInt64
  end_time_unix_nano : UInt64
  attributes : Array[DecodedKeyValue]
  status : DecodedStatus
}

///|
priv struct DecodedScopeSpans {
  scope : DecodedScope
  spans : Array[DecodedSpan]
}

///|
priv struct DecodedResourceSpans {
  resource : DecodedResource
  scope_spans : Array[DecodedScopeSpans]
}

///|
priv struct DecodedTraceRequest {
  resource_spans : Array[DecodedResourceSpans]
}

///|
priv struct DecodedLogRecord {
  time_unix_nano : UInt64
  severity_number : UInt
  severity_text : String
  body : DecodedAnyValue
  attributes : Array[DecodedKeyValue]
}

///|
priv struct DecodedScopeLogs {
  scope : DecodedScope
  log_records : Array[DecodedLogRecord]
}

///|
priv struct DecodedResourceLogs {
  resource : DecodedResource
  scope_logs : Array[DecodedScopeLogs]
}

///|
priv struct DecodedLogsRequest {
  resource_logs : Array[DecodedResourceLogs]
}

///|
fn decoded_any_default() -> DecodedAnyValue {
  { string_value: None, bool_value: None, int_value: None, double_value: None }
}

///|
fn decoded_status_default() -> DecodedStatus {
  { message: "", code: 0 }
}

///|
fn decoded_resource_default() -> DecodedResource {
  { attributes: [] }
}

///|
fn decoded_scope_default() -> DecodedScope {
  { name: "", version: "", attributes: [] }
}

///|
fn assert_wire_type(actual : UInt, expected : UInt, context : String) -> Unit {
  if actual != expected {
    abort(
      "unexpected protobuf wire type for " +
      context +
      ": expected " +
      expected.to_string() +
      ", got " +
      actual.to_string(),
    )
  }
}

///|
fn decode_fail(context : String, message : String) -> Unit {
  abort("protobuf decode failed for " + context + ": " + message)
}

///|
fn read_bytes_field(reader : @protobuf.BytesReader, context : String) -> Bytes {
  (reader |> @protobuf.read_bytes()) catch {
    err => {
      decode_fail(context, "\{err}")
      Bytes::default()
    }
  }
}

///|
fn read_string_field(
  reader : @protobuf.BytesReader,
  context : String,
) -> String {
  (reader |> @protobuf.read_string()) catch {
    err => {
      decode_fail(context, "\{err}")
      ""
    }
  }
}

///|
fn read_uint32_field(reader : @protobuf.BytesReader, context : String) -> UInt {
  (reader |> @protobuf.read_uint32()) catch {
    err => {
      decode_fail(context, "\{err}")
      0
    }
  }
}

///|
fn read_fixed32_field(reader : @protobuf.BytesReader, context : String) -> UInt {
  (reader |> @protobuf.read_fixed32()) catch {
    err => {
      decode_fail(context, "\{err}")
      0
    }
  }
}

///|
fn read_fixed64_field(
  reader : @protobuf.BytesReader,
  context : String,
) -> UInt64 {
  (reader |> @protobuf.read_fixed64()) catch {
    err => {
      decode_fail(context, "\{err}")
      0UL
    }
  }
}

///|
fn read_bool_field(reader : @protobuf.BytesReader, context : String) -> Bool {
  (reader |> @protobuf.read_bool()) catch {
    err => {
      decode_fail(context, "\{err}")
      false
    }
  }
}

///|
fn read_int64_field(reader : @protobuf.BytesReader, context : String) -> Int64 {
  (reader |> @protobuf.read_int64()) catch {
    err => {
      decode_fail(context, "\{err}")
      0L
    }
  }
}

///|
fn read_double_field(
  reader : @protobuf.BytesReader,
  context : String,
) -> Double {
  (reader |> @protobuf.read_double()) catch {
    err => {
      decode_fail(context, "\{err}")
      0.0
    }
  }
}

///|
fn skip_unknown(
  reader : @protobuf.BytesReader,
  wire_type : UInt,
  context : String,
) -> Unit {
  (reader |> @protobuf.read_unknown(wire_type)) catch {
    err => decode_fail(context, "\{err}")
  }
}

///|
fn decode_any_value(body : Bytes) -> DecodedAnyValue {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut value = decoded_any_default()
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 2, "AnyValue.string_value")
          value = {
            string_value: Some(
              read_string_field(reader, "AnyValue.string_value"),
            ),
            bool_value: value.bool_value,
            int_value: value.int_value,
            double_value: value.double_value,
          }
        }
        2 => {
          assert_wire_type(wire_type, 0, "AnyValue.bool_value")
          value = {
            string_value: value.string_value,
            bool_value: Some(read_bool_field(reader, "AnyValue.bool_value")),
            int_value: value.int_value,
            double_value: value.double_value,
          }
        }
        3 => {
          assert_wire_type(wire_type, 0, "AnyValue.int_value")
          value = {
            string_value: value.string_value,
            bool_value: value.bool_value,
            int_value: Some(read_int64_field(reader, "AnyValue.int_value")),
            double_value: value.double_value,
          }
        }
        4 => {
          assert_wire_type(wire_type, 1, "AnyValue.double_value")
          value = {
            string_value: value.string_value,
            bool_value: value.bool_value,
            int_value: value.int_value,
            double_value: Some(
              read_double_field(reader, "AnyValue.double_value"),
            ),
          }
        }
        _ => skip_unknown(reader, wire_type, "AnyValue")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("AnyValue", "\{err}")
  }
  value
}

///|
fn decode_key_value(body : Bytes) -> DecodedKeyValue {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut key = ""
  let mut value = decoded_any_default()
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 2, "KeyValue.key")
          key = read_string_field(reader, "KeyValue.key")
        }
        2 => {
          assert_wire_type(wire_type, 2, "KeyValue.value")
          value = decode_any_value(read_bytes_field(reader, "KeyValue.value"))
        }
        _ => skip_unknown(reader, wire_type, "KeyValue")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("KeyValue", "\{err}")
  }
  { key, value }
}

///|
fn decode_resource(body : Bytes) -> DecodedResource {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let attributes : Array[DecodedKeyValue] = []
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 2, "Resource.attributes")
          attributes.push(
            decode_key_value(read_bytes_field(reader, "Resource.attributes")),
          )
        }
        _ => skip_unknown(reader, wire_type, "Resource")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("Resource", "\{err}")
  }
  { attributes, }
}

///|
fn decode_scope(body : Bytes) -> DecodedScope {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut name = ""
  let mut version = ""
  let attributes : Array[DecodedKeyValue] = []
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 2, "InstrumentationScope.name")
          name = read_string_field(reader, "InstrumentationScope.name")
        }
        2 => {
          assert_wire_type(wire_type, 2, "InstrumentationScope.version")
          version = read_string_field(reader, "InstrumentationScope.version")
        }
        3 => {
          assert_wire_type(wire_type, 2, "InstrumentationScope.attributes")
          attributes.push(
            decode_key_value(
              read_bytes_field(reader, "InstrumentationScope.attributes"),
            ),
          )
        }
        _ => skip_unknown(reader, wire_type, "InstrumentationScope")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("InstrumentationScope", "\{err}")
  }
  { name, version, attributes }
}

///|
fn decode_status(body : Bytes) -> DecodedStatus {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut status = decoded_status_default()
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        2 => {
          assert_wire_type(wire_type, 2, "Status.message")
          status = {
            message: read_string_field(reader, "Status.message"),
            code: status.code,
          }
        }
        3 => {
          assert_wire_type(wire_type, 0, "Status.code")
          status = {
            message: status.message,
            code: read_uint32_field(reader, "Status.code"),
          }
        }
        _ => skip_unknown(reader, wire_type, "Status")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("Status", "\{err}")
  }
  status
}

///|
fn decode_span(body : Bytes) -> DecodedSpan {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut trace_id = Bytes::default()
  let mut span_id = Bytes::default()
  let mut parent_span_id = Bytes::default()
  let mut flags = 0U
  let mut name = ""
  let mut kind = 0U
  let mut start_time_unix_nano = 0UL
  let mut end_time_unix_nano = 0UL
  let attributes : Array[DecodedKeyValue] = []
  let mut status = decoded_status_default()
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 2, "Span.trace_id")
          trace_id = read_bytes_field(reader, "Span.trace_id")
        }
        2 => {
          assert_wire_type(wire_type, 2, "Span.span_id")
          span_id = read_bytes_field(reader, "Span.span_id")
        }
        4 => {
          assert_wire_type(wire_type, 2, "Span.parent_span_id")
          parent_span_id = read_bytes_field(reader, "Span.parent_span_id")
        }
        5 => {
          assert_wire_type(wire_type, 2, "Span.name")
          name = read_string_field(reader, "Span.name")
        }
        6 => {
          assert_wire_type(wire_type, 0, "Span.kind")
          kind = read_uint32_field(reader, "Span.kind")
        }
        7 => {
          assert_wire_type(wire_type, 1, "Span.start_time_unix_nano")
          start_time_unix_nano = read_fixed64_field(
            reader, "Span.start_time_unix_nano",
          )
        }
        8 => {
          assert_wire_type(wire_type, 1, "Span.end_time_unix_nano")
          end_time_unix_nano = read_fixed64_field(
            reader, "Span.end_time_unix_nano",
          )
        }
        9 => {
          assert_wire_type(wire_type, 2, "Span.attributes")
          attributes.push(
            decode_key_value(read_bytes_field(reader, "Span.attributes")),
          )
        }
        15 => {
          assert_wire_type(wire_type, 2, "Span.status")
          status = decode_status(read_bytes_field(reader, "Span.status"))
        }
        16 => {
          assert_wire_type(wire_type, 5, "Span.flags")
          flags = read_fixed32_field(reader, "Span.flags")
        }
        _ => skip_unknown(reader, wire_type, "Span")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("Span", "\{err}")
  }
  {
    trace_id,
    span_id,
    parent_span_id,
    flags,
    name,
    kind,
    start_time_unix_nano,
    end_time_unix_nano,
    attributes,
    status,
  }
}

///|
fn decode_scope_spans(body : Bytes) -> DecodedScopeSpans {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut scope = decoded_scope_default()
  let spans : Array[DecodedSpan] = []
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 2, "ScopeSpans.scope")
          scope = decode_scope(read_bytes_field(reader, "ScopeSpans.scope"))
        }
        2 => {
          assert_wire_type(wire_type, 2, "ScopeSpans.spans")
          spans.push(decode_span(read_bytes_field(reader, "ScopeSpans.spans")))
        }
        _ => skip_unknown(reader, wire_type, "ScopeSpans")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("ScopeSpans", "\{err}")
  }
  { scope, spans }
}

///|
fn decode_resource_spans(body : Bytes) -> DecodedResourceSpans {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut resource = decoded_resource_default()
  let scope_spans : Array[DecodedScopeSpans] = []
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 2, "ResourceSpans.resource")
          resource = decode_resource(
            read_bytes_field(reader, "ResourceSpans.resource"),
          )
        }
        2 => {
          assert_wire_type(wire_type, 2, "ResourceSpans.scope_spans")
          scope_spans.push(
            decode_scope_spans(
              read_bytes_field(reader, "ResourceSpans.scope_spans"),
            ),
          )
        }
        _ => skip_unknown(reader, wire_type, "ResourceSpans")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("ResourceSpans", "\{err}")
  }
  { resource, scope_spans }
}

///|
fn decode_trace_request(body : Bytes) -> DecodedTraceRequest {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let resource_spans : Array[DecodedResourceSpans] = []
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(
            wire_type, 2, "ExportTraceServiceRequest.resource_spans",
          )
          resource_spans.push(
            decode_resource_spans(
              read_bytes_field(
                reader, "ExportTraceServiceRequest.resource_spans",
              ),
            ),
          )
        }
        _ => skip_unknown(reader, wire_type, "ExportTraceServiceRequest")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("ExportTraceServiceRequest", "\{err}")
  }
  { resource_spans, }
}

///|
fn decode_log_record(body : Bytes) -> DecodedLogRecord {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut time_unix_nano = 0UL
  let mut severity_number = 0U
  let mut severity_text = ""
  let mut body_value = decoded_any_default()
  let attributes : Array[DecodedKeyValue] = []
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 1, "LogRecord.time_unix_nano")
          time_unix_nano = read_fixed64_field(
            reader, "LogRecord.time_unix_nano",
          )
        }
        2 => {
          assert_wire_type(wire_type, 0, "LogRecord.severity_number")
          severity_number = read_uint32_field(
            reader, "LogRecord.severity_number",
          )
        }
        3 => {
          assert_wire_type(wire_type, 2, "LogRecord.severity_text")
          severity_text = read_string_field(reader, "LogRecord.severity_text")
        }
        5 => {
          assert_wire_type(wire_type, 2, "LogRecord.body")
          body_value = decode_any_value(
            read_bytes_field(reader, "LogRecord.body"),
          )
        }
        6 => {
          assert_wire_type(wire_type, 2, "LogRecord.attributes")
          attributes.push(
            decode_key_value(read_bytes_field(reader, "LogRecord.attributes")),
          )
        }
        _ => skip_unknown(reader, wire_type, "LogRecord")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("LogRecord", "\{err}")
  }
  {
    time_unix_nano,
    severity_number,
    severity_text,
    body: body_value,
    attributes,
  }
}

///|
fn decode_scope_logs(body : Bytes) -> DecodedScopeLogs {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut scope = decoded_scope_default()
  let log_records : Array[DecodedLogRecord] = []
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 2, "ScopeLogs.scope")
          scope = decode_scope(read_bytes_field(reader, "ScopeLogs.scope"))
        }
        2 => {
          assert_wire_type(wire_type, 2, "ScopeLogs.log_records")
          log_records.push(
            decode_log_record(read_bytes_field(reader, "ScopeLogs.log_records")),
          )
        }
        _ => skip_unknown(reader, wire_type, "ScopeLogs")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("ScopeLogs", "\{err}")
  }
  { scope, log_records }
}

///|
fn decode_resource_logs(body : Bytes) -> DecodedResourceLogs {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let mut resource = decoded_resource_default()
  let scope_logs : Array[DecodedScopeLogs] = []
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(wire_type, 2, "ResourceLogs.resource")
          resource = decode_resource(
            read_bytes_field(reader, "ResourceLogs.resource"),
          )
        }
        2 => {
          assert_wire_type(wire_type, 2, "ResourceLogs.scope_logs")
          scope_logs.push(
            decode_scope_logs(
              read_bytes_field(reader, "ResourceLogs.scope_logs"),
            ),
          )
        }
        _ => skip_unknown(reader, wire_type, "ResourceLogs")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("ResourceLogs", "\{err}")
  }
  { resource, scope_logs }
}

///|
fn decode_logs_request(body : Bytes) -> DecodedLogsRequest {
  let reader = @protobuf.BytesReader::from_bytes(body)
  let resource_logs : Array[DecodedResourceLogs] = []
  try {
    for ;; {
      let (field, wire_type) = reader |> @protobuf.read_tag()
      match field {
        1 => {
          assert_wire_type(
            wire_type, 2, "ExportLogsServiceRequest.resource_logs",
          )
          resource_logs.push(
            decode_resource_logs(
              read_bytes_field(reader, "ExportLogsServiceRequest.resource_logs"),
            ),
          )
        }
        _ => skip_unknown(reader, wire_type, "ExportLogsServiceRequest")
      }
    }
  } catch {
    @protobuf.EndOfStream => ()
    err => decode_fail("ExportLogsServiceRequest", "\{err}")
  }
  { resource_logs, }
}

///|
fn bytes_from_hex(value : String) -> Bytes {
  if value.length() % 2 != 0 {
    abort("odd-length hex fixture")
  }
  let bytes = Buffer(size_hint=value.length() / 2)
  for index = 0; index < value.length(); {
    let pair = value[index:index + 2].to_owned()
    let byte = @string.parse_int(pair, base=16) catch {
      _ => abort("invalid hex fixture")
    }
    bytes.write_byte(byte.to_byte())
    continue index + 2
  }
  bytes.to_bytes()
}

///|
fn find_attribute(
  attributes : Array[DecodedKeyValue],
  key : String,
) -> DecodedAnyValue {
  for attribute in attributes {
    if attribute.key == key {
      return attribute.value
    }
  }
  abort("missing attribute " + key)
}

///|
fn assert_string_value(value : DecodedAnyValue, expected : String) -> Unit {
  match value.string_value {
    Some(actual) =>
      if actual != expected {
        abort("expected string value " + expected + ", got " + actual)
      }
    None => abort("expected string value " + expected)
  }
}

///|
fn assert_bool_value(value : DecodedAnyValue, expected : Bool) -> Unit {
  match value.bool_value {
    Some(actual) => if actual != expected { abort("unexpected bool value") }
    None => abort("expected bool value")
  }
}

///|
fn assert_int_value(value : DecodedAnyValue, expected : Int64) -> Unit {
  match value.int_value {
    Some(actual) => if actual != expected { abort("unexpected int value") }
    None => abort("expected int value")
  }
}

///|
fn assert_double_value(value : DecodedAnyValue, expected : Double) -> Unit {
  match value.double_value {
    Some(actual) => if actual != expected { abort("unexpected double value") }
    None => abort("expected double value")
  }
}

///|
fn unwrap_payload(
  result : Result[@transport.OtlpPayload, @transport.EncodingError],
) -> @transport.OtlpPayload {
  match result {
    Ok(payload) => payload
    Err(err) => abort("expected protobuf payload, got \{err}")
  }
}

///|
fn protobuf_test_resource() -> @otlp.Resource {
  @otlp.resource(service_name="svc", service_version="1.2.3", attributes=[
    @otlp.OtlpAttribute::{ key: "resource.bool", value: @otlp.BoolVal(true) },
  ])
}

///|
fn protobuf_test_scope() -> @otlp.InstrumentationScope {
  @otlp.instrumentation_scope(name="moontrace-test", version="0.12.0", attributes=[
    @otlp.OtlpAttribute::{
      key: "scope.attr",
      value: @otlp.StringVal("scope-value"),
    },
  ])
}

///|
fn protobuf_test_span() -> @otlp.OtlpSpan {
  @otlp.OtlpSpan::{
    trace_id: "0000000000000000000000000000000a",
    span_id: "000000000000000b",
    parent_span_id: "000000000000000c",
    flags: 1,
    name: "work",
    kind: 1,
    start_time_unix_nano: (100 : UInt64),
    end_time_unix_nano: (200 : UInt64),
    attributes: [
      @otlp.OtlpAttribute::{ key: "answer", value: @otlp.IntVal(42L) },
      @otlp.OtlpAttribute::{ key: "ratio", value: @otlp.DoubleVal(2.5) },
    ],
    links: [],
    status_code: 2,
    status_message: "boom",
  }
}

///|
fn protobuf_test_log_record() -> @otlp.OtlpLogRecord {
  @otlp.OtlpLogRecord::{
    time_unix_nano: (300 : UInt64),
    severity_number: 17,
    severity_text: "ERROR",
    body: "log body",
    attributes: [
      @otlp.OtlpAttribute::{ key: "log.attr", value: @otlp.StringVal("value") },
      @otlp.OtlpAttribute::{ key: "log.ok", value: @otlp.BoolVal(true) },
    ],
  }
}

///|
test "json encoder encodes spans with JSON content type bytes" {
  let span = encoding_test_span("work")
  match @transport.json_encoder().encode_spans([span]) {
    Ok(payload) => {
      assert_eq(payload.content_type, @transport.otlp_json_content_type())
      assert_true(payload.body.length() > 0)
      assert_json_eq(parse_payload_json(payload), @otlp.wrap_spans([span]))
    }
    Err(err) => abort("expected JSON span payload, got \{err}")
  }
}

///|
test "json encoder encodes logs with JSON content type bytes" {
  let record = encoding_test_log_record("hello")
  match @transport.json_encoder().encode_logs([record]) {
    Ok(payload) => {
      assert_eq(payload.content_type, @transport.otlp_json_content_type())
      assert_true(payload.body.length() > 0)
      assert_json_eq(
        parse_payload_json(payload),
        @otlp.wrap_log_records([record]),
      )
    }
    Err(err) => abort("expected JSON log payload, got \{err}")
  }
}

///|
test "protobuf encoder encodes spans with protobuf content type bytes" {
  let resource = protobuf_test_resource()
  let scope = protobuf_test_scope()
  let span = protobuf_test_span()
  let payload = unwrap_payload(
    @transport.protobuf_encoder().encode_spans([span], resource~, scope~),
  )
  assert_eq(payload.content_type, @transport.otlp_protobuf_content_type())
  assert_true(payload.body.length() > 0)

  let request = decode_trace_request(payload.body)
  assert_true(request.resource_spans.length() == 1)
  let resource_spans = request.resource_spans[0]
  assert_string_value(
    find_attribute(resource_spans.resource.attributes, "service.name"),
    "svc",
  )
  assert_string_value(
    find_attribute(resource_spans.resource.attributes, "service.version"),
    "1.2.3",
  )
  assert_bool_value(
    find_attribute(resource_spans.resource.attributes, "resource.bool"),
    true,
  )
  assert_true(resource_spans.scope_spans.length() == 1)

  let scope_spans = resource_spans.scope_spans[0]
  assert_eq(scope_spans.scope.name, "moontrace-test")
  assert_eq(scope_spans.scope.version, "0.12.0")
  assert_string_value(
    find_attribute(scope_spans.scope.attributes, "scope.attr"),
    "scope-value",
  )
  assert_true(scope_spans.spans.length() == 1)

  let decoded_span = scope_spans.spans[0]
  assert_true(
    decoded_span.trace_id == bytes_from_hex("0000000000000000000000000000000a"),
  )
  assert_true(decoded_span.span_id == bytes_from_hex("000000000000000b"))
  assert_true(decoded_span.parent_span_id == bytes_from_hex("000000000000000c"))
  assert_eq(decoded_span.name, "work")
  assert_true(decoded_span.kind == 1)
  assert_true(decoded_span.start_time_unix_nano == 100UL)
  assert_true(decoded_span.end_time_unix_nano == 200UL)
  assert_true(decoded_span.flags == 1)
  assert_eq(decoded_span.status.message, "boom")
  assert_true(decoded_span.status.code == 2)
  assert_int_value(find_attribute(decoded_span.attributes, "answer"), 42L)
  assert_double_value(find_attribute(decoded_span.attributes, "ratio"), 2.5)
}

///|
test "protobuf trace request matches golden bytes" {
  let resource = protobuf_test_resource()
  let scope = protobuf_test_scope()
  let span = protobuf_test_span()
  let payload = unwrap_payload(
    @transport.protobuf_encoder().encode_spans([span], resource~, scope~),
  )
  let golden = bytes_from_hex(
    "0af8010a480a150a0c736572766963652e6e616d6512050a037376630a1a0a0f736572766963652e76657273696f6e12070a05312e322e330a130a0d7265736f757263652e626f6f6c1202100112ab010a350a0e6d6f6f6e74726163652d746573741206302e31322e301a1b0a0a73636f70652e61747472120d0a0b73636f70652d76616c756512720a100000000000000000000000000000000a1208000000000000000b2208000000000000000c2a04776f726b300139640000000000000041c8000000000000004a0c0a06616e737765721202182a4a120a05726174696f12092100000000000004407a081204626f6f6d1802850101000000",
  )
  assert_true(payload.body == golden)
}

///|
test "protobuf encoder encodes logs with protobuf content type bytes" {
  let resource = protobuf_test_resource()
  let scope = protobuf_test_scope()
  let record = protobuf_test_log_record()
  let payload = unwrap_payload(
    @transport.protobuf_encoder().encode_logs([record], resource~, scope~),
  )
  assert_eq(payload.content_type, @transport.otlp_protobuf_content_type())
  assert_true(payload.body.length() > 0)

  let request = decode_logs_request(payload.body)
  assert_true(request.resource_logs.length() == 1)
  let resource_logs = request.resource_logs[0]
  assert_string_value(
    find_attribute(resource_logs.resource.attributes, "service.name"),
    "svc",
  )
  assert_string_value(
    find_attribute(resource_logs.resource.attributes, "service.version"),
    "1.2.3",
  )
  assert_bool_value(
    find_attribute(resource_logs.resource.attributes, "resource.bool"),
    true,
  )
  assert_true(resource_logs.scope_logs.length() == 1)

  let scope_logs = resource_logs.scope_logs[0]
  assert_eq(scope_logs.scope.name, "moontrace-test")
  assert_eq(scope_logs.scope.version, "0.12.0")
  assert_string_value(
    find_attribute(scope_logs.scope.attributes, "scope.attr"),
    "scope-value",
  )
  assert_true(scope_logs.log_records.length() == 1)

  let decoded_record = scope_logs.log_records[0]
  assert_true(decoded_record.time_unix_nano == 300UL)
  assert_true(decoded_record.severity_number == 17)
  assert_eq(decoded_record.severity_text, "ERROR")
  assert_string_value(decoded_record.body, "log body")
  assert_string_value(
    find_attribute(decoded_record.attributes, "log.attr"),
    "value",
  )
  assert_bool_value(find_attribute(decoded_record.attributes, "log.ok"), true)
}

///|
test "protobuf encoder reports invalid id errors" {
  let span = @otlp.OtlpSpan::{
    trace_id: "bad",
    span_id: "000000000000000b",
    parent_span_id: "",
    flags: 1,
    name: "work",
    kind: 1,
    start_time_unix_nano: (100 : UInt64),
    end_time_unix_nano: (200 : UInt64),
    attributes: [],
    links: [],
    status_code: 2,
    status_message: "boom",
  }
  match @transport.protobuf_encoder().encode_spans([span]) {
    Ok(_) => abort("invalid protobuf span id should fail")
    Err(err) =>
      assert_eq(
        err.to_string(),
        "protobuf OTLP traces encoding failed: invalid hex bytes for span.trace_id: bad",
      )
  }
}

///|
test "protobuf encoding errors have manual show text" {
  assert_eq(
    @transport.ProtobufNotImplemented(@transport.Traces).to_string(),
    "protobuf OTLP traces encoding is not implemented",
  )
  assert_eq(
    "\{@transport.ProtobufEncodeFailed(@transport.Logs, "bad wire")}",
    "protobuf OTLP logs encoding failed: bad wire",
  )
}
