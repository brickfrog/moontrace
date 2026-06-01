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
fn otlp_json_array(json : Json, label : String) -> Array[Json] {
  match json {
    Array(items) => items
    _ => abort("expected JSON array for \{label}")
  }
}

///|
fn otlp_json_string(json : Json, label : String) -> String {
  match json {
    String(value) => value
    _ => abort("expected JSON string for \{label}")
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
fn otlp_attribute_string(attributes : Array[Json], key : String) -> String? {
  for attribute_json in attributes {
    let attribute = otlp_json_object(attribute_json, "attribute")
    if otlp_json_string(otlp_json_field(attribute, "key"), "key") == key {
      let value = otlp_json_object(
        otlp_json_field(attribute, "value"),
        "attribute.value",
      )
      match value.get("stringValue") {
        Some(string_value) =>
          return Some(otlp_json_string(string_value, "stringValue"))
        None => abort("attribute \{key} is not a string attribute")
      }
    }
  }
  None
}

///|
fn assert_otlp_attribute_string(
  attributes : Array[Json],
  key : String,
  expected : String,
) -> Unit {
  match otlp_attribute_string(attributes, key) {
    Some(actual) =>
      if actual != expected {
        abort("expected attribute \{key}=\{expected}, got \{actual}")
      }
    None => abort("missing attribute \{key}")
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
    links: [],
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
  assert_eq(otlp_json_array(otlp_json_field(obj, "links"), "links").length(), 0)
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
    links: [],
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
test "otlp link to_json includes tracestate and attributes" {
  let link = @otlp.OtlpLink::{
    trace_id: "4bf92f3577b34da6a3ce929d0e0e4736",
    span_id: "00f067aa0ba902b7",
    trace_state: "rojo=00f067aa0ba902b7",
    attributes: [
      @otlp.OtlpAttribute::{ key: "edge", value: @otlp.StringVal("remote") },
    ],
  }
  let obj = otlp_json_object(link.to_json(), "link")
  assert_otlp_json_eq(
    otlp_json_field(obj, "traceId"),
    "4bf92f3577b34da6a3ce929d0e0e4736".to_json(),
  )
  assert_otlp_json_eq(
    otlp_json_field(obj, "spanId"),
    "00f067aa0ba902b7".to_json(),
  )
  assert_otlp_json_eq(
    otlp_json_field(obj, "traceState"),
    "rojo=00f067aa0ba902b7".to_json(),
  )
  let attributes = otlp_json_array(
    otlp_json_field(obj, "attributes"),
    "attributes",
  )
  assert_eq(attributes.length(), 1)
  assert_otlp_attribute_string(attributes, "edge", "remote")
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

///|
test "otlp resource constructor maps service metadata to attributes" {
  let res = @otlp.resource(service_name="checkout", service_version="2026.06", attributes=[
    @otlp.OtlpAttribute::{
      key: "deployment.environment",
      value: @otlp.StringVal("prod"),
    },
  ])
  let obj = otlp_json_object(res.to_json(), "resource")
  let attributes = otlp_json_array(
    otlp_json_field(obj, "attributes"),
    "attributes",
  )
  assert_eq(attributes.length(), 3)
  assert_otlp_attribute_string(attributes, "service.name", "checkout")
  assert_otlp_attribute_string(attributes, "service.version", "2026.06")
  assert_otlp_attribute_string(attributes, "deployment.environment", "prod")
}

///|
test "otlp instrumentation scope to_json omits empty version" {
  let scope = @otlp.instrumentation_scope()
  let obj = otlp_json_object(scope.to_json(), "scope")
  assert_otlp_json_eq(otlp_json_field(obj, "name"), "moontrace".to_json())
  assert_no_otlp_json_field(obj, "version")
  assert_eq(
    otlp_json_array(otlp_json_field(obj, "attributes"), "attributes").length(),
    0,
  )
}

///|
test "otlp instrumentation scope to_json includes version and attributes" {
  let scope = @otlp.instrumentation_scope(
    name="moontrace-test",
    version="0.9.3",
    attributes=[
      @otlp.OtlpAttribute::{ key: "scope.role", value: @otlp.StringVal("test") },
    ],
  )
  let obj = otlp_json_object(scope.to_json(), "scope")
  assert_otlp_json_eq(otlp_json_field(obj, "name"), "moontrace-test".to_json())
  assert_otlp_json_eq(otlp_json_field(obj, "version"), "0.9.3".to_json())
  let attributes = otlp_json_array(
    otlp_json_field(obj, "attributes"),
    "attributes",
  )
  assert_eq(attributes.length(), 1)
  assert_otlp_attribute_string(attributes, "scope.role", "test")
}
