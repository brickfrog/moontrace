///|
test "record adds field to span" {
  let s = @moontrace.span("test")
  s.record("key", "val")
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  s.enter()
  // The enter event should include the recorded field
  let found = {
    let mut result = false
    captured[0].fields.each(fn(f) { if f.key == "key" { result = true } })
    result
  }
  assert_eq(found, true)
  @moontrace.clear_subscriber()
}

///|
test "record multiple fields" {
  let s = @moontrace.span("multi")
  s.record("a", 1)
  s.record("b", 2)
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  s.enter()
  assert_eq(captured[0].fields.length(), 2)
  @moontrace.clear_subscriber()
}

///|
test "record after enter appears in exit event" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  let s = @moontrace.span("late")
  s.enter()
  s.record("added", "later")
  s.exit()
  // exit event (captured[1]) should include the recorded field + duration_ns
  let exit_event = captured[1]
  let found = {
    let mut result = false
    exit_event.fields.each(fn(f) { if f.key == "added" { result = true } })
    result
  }
  assert_eq(found, true)
  @moontrace.clear_subscriber()
}
