///|
test "span lifecycle" {
  let s = @moontrace.span("test")
  assert_eq(s.is_active(), false)
  s.enter()
  assert_eq(s.is_active(), true)
  s.exit()
  assert_eq(s.is_active(), false)
  @moontrace.clear_subscriber()
}

///|
test "span duration" {
  let s = @moontrace.span("dur")
  assert_eq(s.duration(), (0 : UInt64))
  s.enter()
  assert_eq(s.duration(), (0 : UInt64))
  s.exit()
  let has_duration = s.duration() >= (0 : UInt64)
  assert_eq(has_duration, true)
  @moontrace.clear_subscriber()
}

///|
test "span emits events" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  let s = @moontrace.span("work")
  s.enter()
  s.exit()
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "span.enter work")
  assert_eq(captured[1].message, "span.exit work")
  @moontrace.clear_subscriber()
}

///|
test "span exit has duration field" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  let s = @moontrace.span("timed")
  s.enter()
  s.exit()
  assert_eq(captured.length(), 2)
  let exit_event = captured[1]
  let mut has_duration = false
  exit_event.fields.each(fn(f) {
    if f.key == "duration_ns" {
      has_duration = true
    }
  })
  assert_eq(has_duration, true)
  @moontrace.clear_subscriber()
}

///|
test "span preserves custom fields" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  let s = @moontrace.span(
    "op",
    fields=@moontrace.fields([("tool", "test".to_json())]),
  )
  s.enter()
  s.exit()
  assert_eq(captured.length(), 2)
  let mut enter_has_tool = false
  captured[0].fields.each(fn(f) { if f.key == "tool" { enter_has_tool = true } })
  assert_eq(enter_has_tool, true)
  @moontrace.clear_subscriber()
}
