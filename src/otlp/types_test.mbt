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
    trace_id: "00000001",
    span_id: "00000002",
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
  assert_true(j.contains("\"traceId\":\"00000001\""))
  assert_true(j.contains("\"spanId\":\"00000002\""))
  assert_true(j.contains("\"name\":\"test\""))
  assert_true(j.contains("\"kind\":1"))
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
