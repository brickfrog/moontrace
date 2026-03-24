///|
test "span to_string shows name and state" {
  let s = @moontrace.span("test")
  let str = s.to_string()
  assert_true(str.contains("Span(test"))
  assert_true(str.contains("inactive"))
  @moontrace.clear_subscriber()
}

///|
test "span to_string shows active when entered" {
  let s = @moontrace.span("active")
  s.enter()
  let str = s.to_string()
  assert_true(str.contains("active"))
  s.exit()
  @moontrace.clear_subscriber()
}

///|
test "span show via interpolation" {
  let s = @moontrace.span("interp")
  let shown = "\{s}"
  assert_true(shown.contains("Span(interp"))
  @moontrace.clear_subscriber()
}
