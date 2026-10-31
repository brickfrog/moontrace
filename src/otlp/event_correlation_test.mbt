///|
test "span-scoped events preserve correlation fields in OTLP log records" {
  let captured : Array[@moontrace.Event] = []
  let span = @moontrace.span("otlp-event")

  @moontrace.with_trace_state(fn() {
    @moontrace.set_subscriber(fn(event) { captured.push(event) })
    @moontrace.info_in_span(span, "otlp associated")
  })

  assert_eq(captured.length(), 1)
  let record = @otlp.event_to_log_record(captured[0])
  let json = record.to_json().stringify()
  assert_true(json.contains("\"key\":\"trace_id\""))
  assert_true(json.contains("\"stringValue\":\"\{span.trace_id}\""))
  assert_true(json.contains("\"key\":\"span_id\""))
  assert_true(json.contains("\"stringValue\":\"\{span.span_id}\""))
  assert_true(json.contains("\"key\":\"parent_span_id\""))
  assert_true(json.contains("\"stringValue\":\"\""))
}

///|
test "span-scoped events set top-level OTLP log record ids" {
  let captured : Array[@moontrace.Event] = []
  let span = @moontrace.span("otlp-ids")

  @moontrace.with_trace_state(fn() {
    @moontrace.set_subscriber(fn(event) { captured.push(event) })
    @moontrace.info_in_span(span, "inside")
    @moontrace.info("outside")
  })

  assert_eq(captured.length(), 2)
  let inside = @otlp.event_to_log_record(captured[0])
  assert_eq(inside.trace_id, span.trace_id)
  assert_eq(inside.span_id, span.span_id)
  let json = inside.to_json().stringify()
  assert_true(json.contains("\"traceId\":\"\{span.trace_id}\""))
  assert_true(json.contains("\"spanId\":\"\{span.span_id}\""))

  let outside = @otlp.event_to_log_record(captured[1])
  assert_eq(outside.trace_id, "")
  assert_eq(outside.span_id, "")
  let outside_json = outside.to_json().stringify()
  assert_true(!outside_json.contains("traceId"))
  assert_true(!outside_json.contains("spanId"))
}

///|
test "invalid correlation field values are not promoted to OTLP ids" {
  let captured : Array[@moontrace.Event] = []

  @moontrace.with_trace_state(fn() {
    @moontrace.set_subscriber(fn(event) { captured.push(event) })
    @moontrace.info("fake", fields=[
      @moontrace.field("trace_id", "fake"),
      @moontrace.field("span_id", "000000000000000d"),
    ])
    @moontrace.info("zero", fields=[
      @moontrace.field("trace_id", "00000000000000000000000000000000"),
    ])
  })

  for event in captured {
    let record = @otlp.event_to_log_record(event)
    assert_eq(record.trace_id, "")
    assert_eq(record.span_id, "")
  }
}
