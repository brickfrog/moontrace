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
    name: "test",
    kind: 1,
    start_time_unix_nano: (100 : UInt64),
    end_time_unix_nano: (200 : UInt64),
    attributes: [],
    status_code: 1,
    status_message: "",
  }
  let j = span.to_json().stringify()
  assert_true(j.contains("\"traceId\":\"0000000000000000000000000000000a\""))
  assert_true(j.contains("\"spanId\":\"000000000000000b\""))
  assert_true(j.contains("\"name\":\"test\""))
  assert_true(j.contains("\"kind\":1"))
  // parentSpanId should be omitted when empty
  assert_true(!j.contains("parentSpanId"))
}

///|
test "otlp span to_json includes parentSpanId when set" {
  let span = @otlp.OtlpSpan::{
    trace_id: "0000000000000000000000000000000a",
    span_id: "000000000000000b",
    parent_span_id: "000000000000000c",
    name: "child",
    kind: 1,
    start_time_unix_nano: (100 : UInt64),
    end_time_unix_nano: (200 : UInt64),
    attributes: [],
    status_code: 1,
    status_message: "",
  }
  let j = span.to_json().stringify()
  assert_true(j.contains("\"parentSpanId\":\"000000000000000c\""))
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
