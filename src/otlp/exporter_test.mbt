///|
fn exporter_json_object(json : Json, label : String) -> Map[String, Json] {
  match json {
    Object(obj) => obj
    _ => abort("expected JSON object for \{label}")
  }
}

///|
fn exporter_json_field(obj : Map[String, Json], key : String) -> Json {
  match obj.get(key) {
    Some(value) => value
    None => abort("missing JSON field \{key}")
  }
}

///|
fn parse_exporter_json(text : String) -> Json {
  @json.parse(text) catch {
    err => abort("invalid exporter JSON: \{err}")
  }
}

///|
fn exporter_json_array(json : Json, label : String) -> Array[Json] {
  match json {
    Array(items) => items
    _ => abort("expected JSON array for \{label}")
  }
}

///|
fn exporter_json_string(json : Json, label : String) -> String {
  match json {
    String(value) => value
    _ => abort("expected JSON string for \{label}")
  }
}

///|
fn exporter_single_json(items : Array[Json], label : String) -> Json {
  if items.length() != 1 {
    abort("expected exactly one item for \{label}, got \{items.length()}")
  }
  items[0]
}

///|
fn assert_exporter_json_eq(actual : Json, expected : Json) -> Unit {
  if actual.stringify() != expected.stringify() {
    abort("expected \{expected.stringify()}, got \{actual.stringify()}")
  }
}

///|
fn exporter_resource_logs(envelope : Json) -> Map[String, Json] {
  let root = exporter_json_object(envelope, "logs envelope")
  let resource_logs = exporter_json_array(
    exporter_json_field(root, "resourceLogs"),
    "resourceLogs",
  )
  exporter_json_object(
    exporter_single_json(resource_logs, "resourceLogs"),
    "resourceLogs[0]",
  )
}

///|
fn exporter_scope_logs(envelope : Json) -> Map[String, Json] {
  let resource_logs = exporter_resource_logs(envelope)
  let scope_logs = exporter_json_array(
    exporter_json_field(resource_logs, "scopeLogs"),
    "scopeLogs",
  )
  exporter_json_object(
    exporter_single_json(scope_logs, "scopeLogs"),
    "scopeLogs[0]",
  )
}

///|
fn exporter_log_records(envelope : Json) -> Array[Json] {
  let scope_logs = exporter_scope_logs(envelope)
  exporter_json_array(
    exporter_json_field(scope_logs, "logRecords"),
    "logRecords",
  )
}

///|
fn exporter_log_resource_attributes(envelope : Json) -> Array[Json] {
  let resource_logs = exporter_resource_logs(envelope)
  let resource = exporter_json_object(
    exporter_json_field(resource_logs, "resource"),
    "resource",
  )
  exporter_json_array(exporter_json_field(resource, "attributes"), "attributes")
}

///|
fn exporter_log_scope(envelope : Json) -> Map[String, Json] {
  let scope_logs = exporter_scope_logs(envelope)
  exporter_json_object(exporter_json_field(scope_logs, "scope"), "scope")
}

///|
fn exporter_resource_spans(envelope : Json) -> Map[String, Json] {
  let root = exporter_json_object(envelope, "spans envelope")
  let resource_spans = exporter_json_array(
    exporter_json_field(root, "resourceSpans"),
    "resourceSpans",
  )
  exporter_json_object(
    exporter_single_json(resource_spans, "resourceSpans"),
    "resourceSpans[0]",
  )
}

///|
fn exporter_scope_spans(envelope : Json) -> Map[String, Json] {
  let resource_spans = exporter_resource_spans(envelope)
  let scope_spans = exporter_json_array(
    exporter_json_field(resource_spans, "scopeSpans"),
    "scopeSpans",
  )
  exporter_json_object(
    exporter_single_json(scope_spans, "scopeSpans"),
    "scopeSpans[0]",
  )
}

///|
fn exporter_spans(envelope : Json) -> Array[Json] {
  let scope_spans = exporter_scope_spans(envelope)
  exporter_json_array(exporter_json_field(scope_spans, "spans"), "spans")
}

///|
fn exporter_span_resource_attributes(envelope : Json) -> Array[Json] {
  let resource_spans = exporter_resource_spans(envelope)
  let resource = exporter_json_object(
    exporter_json_field(resource_spans, "resource"),
    "resource",
  )
  exporter_json_array(exporter_json_field(resource, "attributes"), "attributes")
}

///|
fn exporter_span_scope(envelope : Json) -> Map[String, Json] {
  let scope_spans = exporter_scope_spans(envelope)
  exporter_json_object(exporter_json_field(scope_spans, "scope"), "scope")
}

///|
fn exporter_scope_attributes(scope : Map[String, Json]) -> Array[Json] {
  exporter_json_array(
    exporter_json_field(scope, "attributes"),
    "scope.attributes",
  )
}

///|
fn exporter_attribute_string(attributes : Array[Json], key : String) -> String? {
  for attribute_json in attributes {
    let attribute = exporter_json_object(attribute_json, "attribute")
    if exporter_json_string(exporter_json_field(attribute, "key"), "key") == key {
      let value = exporter_json_object(
        exporter_json_field(attribute, "value"),
        "attribute.value",
      )
      match value.get("stringValue") {
        Some(string_value) =>
          return Some(
            exporter_json_string(string_value, "attribute.value.stringValue"),
          )
        None => abort("attribute \{key} is not a string attribute")
      }
    }
  }
  None
}

///|
fn assert_exporter_attribute_string(
  attributes : Array[Json],
  key : String,
  expected : String,
) -> Unit {
  match exporter_attribute_string(attributes, key) {
    Some(actual) =>
      if actual != expected {
        abort("expected attribute \{key}=\{expected}, got \{actual}")
      }
    None => abort("missing attribute \{key}")
  }
}

///|
fn exporter_test_span(name : String) -> @otlp.OtlpSpan {
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
fn exporter_test_log_record(body : String) -> @otlp.OtlpLogRecord {
  @otlp.OtlpLogRecord::{
    time_unix_nano: (100 : UInt64),
    severity_number: 9,
    severity_text: "INFO",
    body,
    attributes: [],
  }
}

///|
test "otlp exporter captures events as log records" {
  let output : Array[String] = []
  let exp = @otlp.exporter(log_output=fn(s) { output.push(s) }, capacity=2)
  @moontrace.set_subscriber(exp.subscriber())
  @moontrace.info("one")
  assert_eq(output.length(), 0) // not flushed yet
  @moontrace.info("two")
  assert_eq(output.length(), 1) // auto-flushed at capacity
  let envelope = parse_exporter_json(output[0])
  assert_eq(exporter_log_records(envelope).length(), 2)
  let scope = exporter_log_scope(envelope)
  assert_exporter_json_eq(
    exporter_json_field(scope, "name"),
    "moontrace".to_json(),
  )
  assert_eq(exporter_log_resource_attributes(envelope).length(), 0)
  @moontrace.clear_subscriber()
}

///|
test "otlp exporter manual flush" {
  let output : Array[String] = []
  let exp = @otlp.exporter(log_output=fn(s) { output.push(s) })
  @moontrace.set_subscriber(exp.subscriber())
  @moontrace.warn("alert")
  assert_eq(output.length(), 0)
  exp.flush()
  assert_eq(output.length(), 1)
  let records = exporter_log_records(parse_exporter_json(output[0]))
  let record = exporter_json_object(
    exporter_single_json(records, "logRecords"),
    "logRecord",
  )
  assert_exporter_json_eq(
    exporter_json_field(record, "severityText"),
    "WARN".to_json(),
  )
  let body = exporter_json_object(exporter_json_field(record, "body"), "body")
  assert_exporter_json_eq(
    exporter_json_field(body, "stringValue"),
    "alert".to_json(),
  )
  @moontrace.clear_subscriber()
}

///|
test "otlp span conversion" {
  let s = @moontrace.span(
    "work",
    fields=@moontrace.fields([("key", "val".to_json())]),
  )
  s.enter()
  s.exit()
  let otlp_span = @otlp.span_to_otlp(s)
  let j = otlp_span.to_json().stringify()
  assert_true(j.contains("\"name\":\"work\""))
  assert_true(j.contains("\"traceId\""))
  assert_true(j.contains("\"spanId\""))
  assert_true(j.contains("\"key\""))
  assert_true(j.contains("\"stringValue\":\"val\""))
  @moontrace.clear_subscriber()
}

///|
test "otlp span conversion carries trace flags" {
  let remote = match
    @moontrace.parse_traceparent(
      "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01",
    ) {
    Ok(ctx) => ctx
    Err(err) => abort("expected remote context, got \{err}")
  }
  let child = @moontrace.span_from_remote_context(remote, "server")
  child.enter()
  child.exit()
  let otlp_span = @otlp.span_to_otlp(child)
  assert_eq(otlp_span.flags, 1)
  let span_json = exporter_json_object(otlp_span.to_json(), "span")
  assert_exporter_json_eq(
    exporter_json_field(span_json, "flags"),
    (1).to_json(),
  )
  assert_exporter_json_eq(
    exporter_json_field(span_json, "traceId"),
    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa".to_json(),
  )
  assert_exporter_json_eq(
    exporter_json_field(span_json, "parentSpanId"),
    "bbbbbbbbbbbbbbbb".to_json(),
  )
}

///|
test "otlp exporter captures completed spans through observer" {
  let output : Array[String] = []
  let exp = @otlp.exporter(span_output=fn(s) { output.push(s) }, capacity=1)
  @moontrace.set_span_observer(exp.span_observer())
  let s = @moontrace.span(
    "observed",
    fields=@moontrace.fields([("key", "val".to_json())]),
  )
  s.enter()
  s.exit()
  @moontrace.clear_span_observer()
  assert_eq(output.length(), 1)
  let spans = exporter_spans(parse_exporter_json(output[0]))
  let span = exporter_json_object(exporter_single_json(spans, "spans"), "span")
  assert_exporter_json_eq(
    exporter_json_field(span, "name"),
    "observed".to_json(),
  )
  assert_eq(
    exporter_json_array(exporter_json_field(span, "attributes"), "attributes").length(),
    1,
  )
}

///|
test "otlp exporter captures reopened span only once" {
  let output : Array[String] = []
  let exp = @otlp.exporter(span_output=fn(s) { output.push(s) }, capacity=1)
  @moontrace.set_span_observer(exp.span_observer())
  let s = @moontrace.span("single")
  s.enter()
  s.exit()
  s.enter()
  s.exit()
  @moontrace.clear_span_observer()
  assert_eq(output.length(), 1)
  let spans = exporter_spans(parse_exporter_json(output[0]))
  let span = exporter_json_object(exporter_single_json(spans, "spans"), "span")
  assert_exporter_json_eq(exporter_json_field(span, "name"), "single".to_json())
}

///|
test "otlp wrap_spans produces valid envelope" {
  let s = @moontrace.span("op")
  s.enter()
  s.exit()
  let otlp_span = @otlp.span_to_otlp(s)
  let envelope = @otlp.wrap_spans([otlp_span])
  assert_eq(exporter_spans(envelope).length(), 1)
  let scope = exporter_span_scope(envelope)
  assert_exporter_json_eq(
    exporter_json_field(scope, "name"),
    "moontrace".to_json(),
  )
  @moontrace.clear_subscriber()
}

///|
test "otlp wrap_spans carries resource and scope attributes" {
  let resource = @otlp.resource(
    service_name="billing-api",
    service_version="1.2.3",
    attributes=[
      @otlp.OtlpAttribute::{
        key: "deployment.environment",
        value: @otlp.StringVal("prod"),
      },
    ],
  )
  let scope = @otlp.instrumentation_scope(
    name="moontrace-tests",
    version="0.1.0",
    attributes=[
      @otlp.OtlpAttribute::{
        key: "scope.kind",
        value: @otlp.StringVal("blackbox"),
      },
    ],
  )
  let envelope = @otlp.wrap_spans(
    [exporter_test_span("with-resource")],
    resource~,
    scope~,
  )
  let resource_attributes = exporter_span_resource_attributes(envelope)
  assert_exporter_attribute_string(
    resource_attributes, "service.name", "billing-api",
  )
  assert_exporter_attribute_string(
    resource_attributes, "service.version", "1.2.3",
  )
  assert_exporter_attribute_string(
    resource_attributes, "deployment.environment", "prod",
  )
  let scope_obj = exporter_span_scope(envelope)
  assert_exporter_json_eq(
    exporter_json_field(scope_obj, "name"),
    "moontrace-tests".to_json(),
  )
  assert_exporter_json_eq(
    exporter_json_field(scope_obj, "version"),
    "0.1.0".to_json(),
  )
  assert_exporter_attribute_string(
    exporter_scope_attributes(scope_obj),
    "scope.kind",
    "blackbox",
  )
}

///|
test "otlp wrap_log_records carries resource and scope attributes" {
  let resource = @otlp.resource(
    service_name="log-api",
    service_version="2.0.0",
    attributes=[
      @otlp.OtlpAttribute::{ key: "region", value: @otlp.StringVal("iad") },
    ],
  )
  let scope = @otlp.instrumentation_scope(
    name="moontrace-log-tests",
    version="0.2.0",
    attributes=[
      @otlp.OtlpAttribute::{
        key: "scope.signal",
        value: @otlp.StringVal("logs"),
      },
    ],
  )
  let envelope = @otlp.wrap_log_records(
    [exporter_test_log_record("structured")],
    resource~,
    scope~,
  )
  let resource_attributes = exporter_log_resource_attributes(envelope)
  assert_exporter_attribute_string(
    resource_attributes, "service.name", "log-api",
  )
  assert_exporter_attribute_string(
    resource_attributes, "service.version", "2.0.0",
  )
  assert_exporter_attribute_string(resource_attributes, "region", "iad")
  let scope_obj = exporter_log_scope(envelope)
  assert_exporter_json_eq(
    exporter_json_field(scope_obj, "name"),
    "moontrace-log-tests".to_json(),
  )
  assert_exporter_json_eq(
    exporter_json_field(scope_obj, "version"),
    "0.2.0".to_json(),
  )
  assert_exporter_attribute_string(
    exporter_scope_attributes(scope_obj),
    "scope.signal",
    "logs",
  )
}

///|
test "otlp exporter uses resource and scope on capacity flush" {
  let log_output : Array[String] = []
  let span_output : Array[String] = []
  let resource = @otlp.resource(service_name="capacity-api")
  let scope = @otlp.instrumentation_scope(
    name="capacity-scope",
    version="1.0.0",
  )
  let exp = @otlp.exporter(
    log_output=fn(s) { log_output.push(s) },
    span_output=fn(s) { span_output.push(s) },
    capacity=1,
    resource~,
    scope~,
  )
  @moontrace.set_subscriber(exp.subscriber())
  @moontrace.info("capacity log")
  exp.add_span(exporter_test_span("capacity span"))
  @moontrace.clear_subscriber()
  assert_eq(log_output.length(), 1)
  assert_eq(span_output.length(), 1)
  let log_envelope = parse_exporter_json(log_output[0])
  assert_exporter_attribute_string(
    exporter_log_resource_attributes(log_envelope),
    "service.name",
    "capacity-api",
  )
  assert_exporter_json_eq(
    exporter_json_field(exporter_log_scope(log_envelope), "name"),
    "capacity-scope".to_json(),
  )
  let span_envelope = parse_exporter_json(span_output[0])
  assert_exporter_attribute_string(
    exporter_span_resource_attributes(span_envelope),
    "service.name",
    "capacity-api",
  )
  assert_exporter_json_eq(
    exporter_json_field(exporter_span_scope(span_envelope), "version"),
    "1.0.0".to_json(),
  )
}

///|
test "otlp exporter shutdown flushes then drops later events" {
  let log_output : Array[String] = []
  let span_output : Array[String] = []
  let exp = @otlp.exporter(
    log_output=fn(s) { log_output.push(s) },
    span_output=fn(s) { span_output.push(s) },
    capacity=10,
  )
  @moontrace.set_subscriber(exp.subscriber())
  @moontrace.set_span_observer(exp.span_observer())
  @moontrace.info("before shutdown")
  exp.add_span(exporter_test_span("before shutdown span"))
  exp.shutdown()
  assert_eq(log_output.length(), 1)
  assert_eq(span_output.length(), 1)

  @moontrace.info("after shutdown")
  exp.add_span(exporter_test_span("after shutdown manual span"))
  let observed = @moontrace.span("after shutdown observed span")
  observed.enter()
  observed.exit()
  exp.flush()
  @moontrace.clear_subscriber()
  @moontrace.clear_span_observer()

  assert_eq(log_output.length(), 1)
  assert_eq(span_output.length(), 1)
  let log_records = exporter_log_records(parse_exporter_json(log_output[0]))
  assert_eq(log_records.length(), 1)
  let span_records = exporter_spans(parse_exporter_json(span_output[0]))
  assert_eq(span_records.length(), 1)
}

///|
test "otlp level severity mapping" {
  assert_eq(@otlp.level_to_severity(@moontrace.Trace), 1)
  assert_eq(@otlp.level_to_severity(@moontrace.Debug), 5)
  assert_eq(@otlp.level_to_severity(@moontrace.Info), 9)
  assert_eq(@otlp.level_to_severity(@moontrace.Warn), 13)
  assert_eq(@otlp.level_to_severity(@moontrace.Error_), 17)
}

///|
test "otlp id generation is unique and hex" {
  let id1 = @moontrace.next_trace_id()
  let id2 = @moontrace.next_trace_id()
  assert_true(id1 != id2)
  // trace IDs should be 32 chars
  assert_eq(id1.length(), 32)
  // span IDs should be 16 chars
  let sid = @moontrace.next_span_id()
  assert_eq(sid.length(), 16)
  // Verify non-empty
  assert_true(id1.length() > 0)
}

///|
test "otlp field conversion preserves types" {
  let str_field = @moontrace.Field::{ key: "s", value: "hello".to_json() }
  let num_field = @moontrace.Field::{ key: "n", value: (42).to_json() }
  let bool_field = @moontrace.Field::{ key: "b", value: true.to_json() }

  let sa = @otlp.field_to_attribute(str_field)
  let na = @otlp.field_to_attribute(num_field)
  let ba = @otlp.field_to_attribute(bool_field)

  let sj = sa.to_json().stringify()
  assert_true(sj.contains("\"stringValue\":\"hello\""))

  let nj = na.to_json().stringify()
  assert_true(nj.contains("\"intValue\""))

  let bj = ba.to_json().stringify()
  assert_true(bj.contains("\"boolValue\":true"))
}
