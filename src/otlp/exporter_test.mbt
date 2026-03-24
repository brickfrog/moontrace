///|
test "otlp exporter captures events as log records" {
  let output : Array[String] = []
  let exp = @otlp.exporter(log_output=fn(s) { output.push(s) }, capacity=2)
  @moontrace.set_subscriber(exp.subscriber())
  @moontrace.info("one")
  assert_eq(output.length(), 0) // not flushed yet
  @moontrace.info("two")
  assert_eq(output.length(), 1) // auto-flushed at capacity
  // Output should be OTLP JSON with resourceLogs
  assert_true(output[0].contains("resourceLogs"))
  assert_true(output[0].contains("scopeLogs"))
  assert_true(output[0].contains("logRecords"))
  assert_true(output[0].contains("severityNumber"))
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
  assert_true(output[0].contains("WARN"))
  assert_true(output[0].contains("alert"))
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
  @moontrace.clear_subscriber()
}

///|
test "otlp wrap_spans produces valid envelope" {
  let s = @moontrace.span("op")
  s.enter()
  s.exit()
  let otlp_span = @otlp.span_to_otlp(s)
  let envelope = @otlp.wrap_spans([otlp_span])
  let j = envelope.stringify()
  assert_true(j.contains("resourceSpans"))
  assert_true(j.contains("scopeSpans"))
  assert_true(j.contains("moontrace"))
  @moontrace.clear_subscriber()
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
test "otlp id generation is unique" {
  let id1 = @otlp.next_trace_id()
  let id2 = @otlp.next_trace_id()
  assert_true(id1 != id2)
  // trace IDs should be 32 chars
  assert_eq(id1.length(), 32)
  // span IDs should be 16 chars
  let sid = @otlp.next_span_id()
  assert_eq(sid.length(), 16)
}
