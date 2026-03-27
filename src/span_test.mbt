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
test "span has trace and span ids" {
  let s = @moontrace.span("test")
  assert_eq(s.trace_id.length(), 32)
  assert_eq(s.span_id.length(), 16)
  assert_eq(s.parent_span_id, "")
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
test "span exit is idempotent when already inactive" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  let s = @moontrace.span("once")
  s.enter()
  s.exit()
  s.exit()
  @moontrace.clear_subscriber()
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "span.enter once")
  assert_eq(captured[1].message, "span.exit once")
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

///|
test "record after enter does not mutate enter event" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  let s = @moontrace.span("snap")
  s.enter()
  s.record("late", "field".to_json())
  s.exit()
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "span.enter snap")
  assert_eq(captured[1].message, "span.exit snap")
  // enter event should NOT have the "late" field
  let mut enter_has_late = false
  captured[0].fields.each(fn(f) { if f.key == "late" { enter_has_late = true } })
  assert_eq(enter_has_late, false)
  // exit event SHOULD have the "late" field
  let mut exit_has_late = false
  captured[1].fields.each(fn(f) { if f.key == "late" { exit_has_late = true } })
  assert_eq(exit_has_late, true)
  @moontrace.clear_subscriber()
}
