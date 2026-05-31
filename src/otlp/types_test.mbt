///|
fn otlp_json_object(json : Json, label : String) -> Map[String, Json] {
  match json {
    Object(obj) => obj
    _ => abort("expected JSON object for \{label}")
  }
}

///|
fn otlp_json_field(obj : Map[String, Json], key : String) -> Json {
  match obj.get(key) {
    Some(value) => value
    None => abort("missing JSON field \{key}")
  }
}

///|
fn assert_otlp_json_eq(actual : Json, expected : Json) -> Unit {
  if actual.stringify() != expected.stringify() {
    abort("expected \{expected.stringify()}, got \{actual.stringify()}")
  }
}

///|
fn assert_no_otlp_json_field(obj : Map[String, Json], key : String) -> Unit {
  match obj.get(key) {
    Some(_) => abort("unexpected JSON field \{key}")
    None => ()
  }
}

///|
test "otlp attribute to_json" {
  let attr = @otlp.OtlpAttribute::{
    key: "service",
    value: @otlp.StringVal("test"),
  }
  let j = attr.to_json().stringify()
  assert_true(j.contains("\"key\":\"service\""))
  assert_true(j.contains("\"stringValue\":\"test\""))
}

///|
test "otlp span to_json has required fields" {
  let span = @otlp.OtlpSpan::{
    trace_id: "0000000000000000000000000000000a",
    span_id: "000000000000000b",
    parent_span_id: "",
    flags: 0,
    name: "test",
    kind: 1,
    start_time_unix_nano: (100 : UInt64),
    end_time_unix_nano: (200 : UInt64),
    attributes: [],
    status_code: 1,
    status_message: "",
  }
  let obj = otlp_json_object(span.to_json(), "span")
  assert_otlp_json_eq(
    otlp_json_field(obj, "traceId"),
    "0000000000000000000000000000000a".to_json(),
  )
  assert_otlp_json_eq(
    otlp_json_field(obj, "spanId"),
    "000000000000000b".to_json(),
  )
  assert_otlp_json_eq(otlp_json_field(obj, "name"), "test".to_json())
  assert_otlp_json_eq(otlp_json_field(obj, "kind"), (1).to_json())
  assert_otlp_json_eq(otlp_json_field(obj, "flags"), (0).to_json())
  assert_otlp_json_eq(
    otlp_json_field(obj, "startTimeUnixNano"),
    "100".to_json(),
  )
  assert_otlp_json_eq(otlp_json_field(obj, "endTimeUnixNano"), "200".to_json())
  assert_no_otlp_json_field(obj, "parentSpanId")
  let status = otlp_json_object(otlp_json_field(obj, "status"), "status")
  assert_otlp_json_eq(otlp_json_field(status, "code"), (1).to_json())
}

///|
test "otlp span to_json includes parentSpanId when set" {
  let span = @otlp.OtlpSpan::{
    trace_id: "0000000000000000000000000000000a",
    span_id: "000000000000000b",
    parent_span_id: "000000000000000c",
    flags: 1,
    name: "child",
    kind: 1,
    start_time_unix_nano: (100 : UInt64),
    end_time_unix_nano: (200 : UInt64),
    attributes: [],
    status_code: 1,
    status_message: "",
  }
  let obj = otlp_json_object(span.to_json(), "span")
  assert_otlp_json_eq(
    otlp_json_field(obj, "parentSpanId"),
    "000000000000000c".to_json(),
  )
  assert_otlp_json_eq(otlp_json_field(obj, "flags"), (1).to_json())
}

///|
test "otlp log record to_json" {
  let record = @otlp.OtlpLogRecord::{
    time_unix_nano: (12345 : UInt64),
    severity_number: 9,
    severity_text: "INFO",
    body: "hello",
    attributes: [],
  }
  let j = record.to_json().stringify()
  assert_true(j.contains("\"severityNumber\":9"))
  assert_true(j.contains("\"severityText\":\"INFO\""))
  assert_true(j.contains("\"stringValue\":\"hello\""))
}
