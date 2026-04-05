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

///|
test "with_span_ctx passes span to closure" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.with_span_ctx("ctx", fn(s) { s.record("added", "during") })
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "span.enter ctx")
  @moontrace.clear_subscriber()
}

///|
test "with_span_ctx returns closure result" {
  let result = @moontrace.with_span_ctx("calc", fn(_s) { 99 })
  assert_eq(result, 99)
  @moontrace.clear_subscriber()
}

///|
test "with_child_span links parent" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.with_span_ctx("parent", fn(parent) {
    @moontrace.with_child_span(parent, "child", fn(_s) {  })
  })
  // Events: parent.enter, child.enter, child.exit, parent.exit
  assert_eq(captured.length(), 4)
  assert_eq(captured[1].message, "span.enter child")
  // child enter event should have "parent" field
  let mut found = false
  captured[1].fields.each(fn(f) { if f.key == "parent" { found = true } })
  assert_eq(found, true)
  @moontrace.clear_subscriber()
}

///|
test "with_child_span propagates trace_id" {
  let mut parent_trace = ""
  let mut child_trace = ""
  let mut child_parent_id = ""
  let mut parent_span = ""
  @moontrace.with_span_ctx("parent", fn(p) {
    parent_trace = p.trace_id
    parent_span = p.span_id
    @moontrace.with_child_span(p, "child", fn(c) {
      child_trace = c.trace_id
      child_parent_id = c.parent_span_id
    })
  })
  assert_eq(parent_trace, child_trace)
  assert_eq(child_parent_id, parent_span)
  @moontrace.clear_subscriber()
}
