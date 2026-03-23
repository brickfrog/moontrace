///|
test "with_span enters and exits" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.with_span("work", fn() { @moontrace.info("inside") })
  // Should have: span.enter, info event, span.exit = 3 events
  assert_eq(captured.length(), 3)
  assert_eq(captured[0].message, "span.enter work")
  assert_eq(captured[1].message, "inside")
  assert_eq(captured[2].message, "span.exit work")
  @moontrace.clear_subscriber()
}

///|
test "with_span returns closure result" {
  let result = @moontrace.with_span("calc", fn() { 42 })
  assert_eq(result, 42)
  @moontrace.clear_subscriber()
}

///|
test "with_span passes fields to span" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.with_span(
    "op",
    fields=@moontrace.fields([("key", "val".to_json())]),
    fn() {  },
  )
  // Just verify enter event has the field
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "span.enter op")
  let found = {
    let mut result = false
    captured[0].fields.each(fn(f) { if f.key == "key" { result = true } })
    result
  }
  assert_eq(found, true)
  @moontrace.clear_subscriber()
}
