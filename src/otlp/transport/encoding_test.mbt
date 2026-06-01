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
test "json encoder encodes spans as application/json bytes" {
  let span = encoding_test_span("work")
  match @transport.json_encoder().encode_spans([span]) {
    Ok(payload) => {
      assert_eq(payload.content_type, "application/json")
      assert_true(payload.body.length() > 0)
      assert_json_eq(parse_payload_json(payload), @otlp.wrap_spans([span]))
    }
    Err(err) => abort("expected JSON span payload, got \{err}")
  }
}

///|
test "json encoder encodes logs as application/json bytes" {
  let record = encoding_test_log_record("hello")
  match @transport.json_encoder().encode_logs([record]) {
    Ok(payload) => {
      assert_eq(payload.content_type, "application/json")
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
test "protobuf encoder reports structured not implemented errors" {
  match
    @transport.protobuf_encoder().encode_spans([encoding_test_span("work")]) {
    Ok(_) => abort("protobuf span encoding should be stubbed")
    Err(@transport.ProtobufNotImplemented(@transport.Traces)) => ()
    Err(err) => abort("unexpected protobuf span error: \{err}")
  }
  match
    @transport.protobuf_encoder().encode_logs([
      encoding_test_log_record("hello"),
    ]) {
    Ok(_) => abort("protobuf log encoding should be stubbed")
    Err(@transport.ProtobufNotImplemented(@transport.Logs)) => ()
    Err(err) => abort("unexpected protobuf log error: \{err}")
  }
  assert_eq(
    @transport.ProtobufNotImplemented(@transport.Traces).to_string(),
    "protobuf OTLP traces encoding is not implemented",
  )
  assert_eq(
    "\{@transport.ProtobufNotImplemented(@transport.Logs)}",
    "protobuf OTLP logs encoding is not implemented",
  )
}
