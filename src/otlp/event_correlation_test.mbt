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
