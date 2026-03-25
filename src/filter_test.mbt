///|
test "event has source field" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("hello")
  assert_eq(captured.length(), 1)
  // source should be non-empty (the test package name)
  assert_true(captured[0].source.length() > 0)
  inspect(
    captured[0].source,
    content=(
      #|brickfrog/moontrace_blackbox_test
    ),
  )
  @moontrace.clear_subscriber()
}

///|
test "no filter means all events pass" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("pass")
  assert_eq(captured.length(), 1)
  @moontrace.clear_subscriber()
}

///|
test "module filter blocks events below level" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  // Set filter for current package at Warn level
  @moontrace.set_module_filter(
    "brickfrog/moontrace_blackbox_test",
    @moontrace.Warn,
  )
  @moontrace.debug("blocked")
  @moontrace.info("blocked")
  @moontrace.warn("allowed")
  @moontrace.error("allowed")
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].level, @moontrace.Warn)
  assert_eq(captured[1].level, @moontrace.Error_)
  @moontrace.clear_module_filters()
  @moontrace.clear_subscriber()
}

///|
test "module filter allows events at or above level" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  // Set filter for current package at Info level
  @moontrace.set_module_filter(
    "brickfrog/moontrace_blackbox_test",
    @moontrace.Info,
  )
  @moontrace.trace("blocked")
  @moontrace.debug("blocked")
  @moontrace.info("allowed")
  @moontrace.warn("allowed")
  @moontrace.error("allowed")
  assert_eq(captured.length(), 3)
  @moontrace.clear_module_filters()
  @moontrace.clear_subscriber()
}

///|
test "clearing module filters allows all events" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.set_module_filter(
    "brickfrog/moontrace_blackbox_test",
    @moontrace.Error_,
  )
  @moontrace.info("blocked")
  @moontrace.clear_module_filters()
  @moontrace.info("now allowed")
  assert_eq(captured.length(), 1)
  assert_eq(captured[0].message, "now allowed")
  @moontrace.clear_subscriber()
}

///|
test "span events bypass module filtering" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.set_module_filter(
    "brickfrog/moontrace_blackbox_test",
    @moontrace.Error_,
  )
  let s = @moontrace.span("test_span")
  s.enter()
  s.exit()
  // Span events should still be emitted (they use emit() without SourceLoc)
  assert_eq(captured.length(), 2)
  @moontrace.clear_module_filters()
  @moontrace.clear_subscriber()
}
