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

///|
test "call-site location becomes OTLP code attributes" {
  let captured : Array[@moontrace.Event] = []
  @moontrace.with_subscriber(event => captured.push(event), () => {
    @moontrace.info("located")
  })
  let record = @otlp.event_to_log_record(captured[0])
  let attributes = record.attributes
  assert_eq(attributes.length(), 2)
  assert_eq(attributes[0].key, "code.file.path")
  assert_true(
    attributes[0].value is StringVal(path) &&
    path == "src/otlp/event_correlation_test.mbt",
  )
  assert_eq(attributes[1].key, "code.line.number")
  assert_true(attributes[1].value is IntVal(line) && line > 0L)

  let unlocated = @otlp.event_to_log_record({
    ..captured[0],
    file: "",
    line: 0,
  })
  assert_eq(unlocated.attributes.length(), 0)
}

///|
test "explicit code attributes win over the captured location" {
  let captured : Array[@moontrace.Event] = []
  @moontrace.with_subscriber(event => captured.push(event), () => {
    @moontrace.info("located", fields=[
      @moontrace.field("code.file.path", "generated/model.mbt"),
    ])
  })
  let attributes = @otlp.event_to_log_record(captured[0]).attributes
  let keys = attributes.map(a => a.key)
  assert_eq(keys, ["code.file.path", "code.line.number"])
  assert_true(
    attributes[0].value is StringVal(path) && path == "generated/model.mbt",
  )
}
