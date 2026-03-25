///|
test "event has source field" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("hello")
  @moontrace.clear_subscriber()
  assert_eq(captured.length(), 1)
  assert_true(captured[0].source.length() > 0)
}

///|
test "no filter means all events pass" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("pass")
  @moontrace.clear_subscriber()
  assert_eq(captured.length(), 1)
}

///|
test "module filter blocks events below level" {
  @moontrace.set_module_filter(
    "brickfrog/moontrace_blackbox_test",
    @moontrace.Warn,
  )
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.debug("blocked")
  @moontrace.info("blocked")
  @moontrace.warn("allowed")
  @moontrace.error("allowed")
  @moontrace.clear_module_filters()
  @moontrace.clear_subscriber()
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].level, @moontrace.Warn)
  assert_eq(captured[1].level, @moontrace.Error_)
}

///|
test "module filter allows events at or above level" {
  @moontrace.set_module_filter(
    "brickfrog/moontrace_blackbox_test",
    @moontrace.Info,
  )
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.trace("blocked")
  @moontrace.debug("blocked")
  @moontrace.info("allowed")
  @moontrace.warn("allowed")
  @moontrace.error("allowed")
  @moontrace.clear_module_filters()
  @moontrace.clear_subscriber()
  assert_eq(captured.length(), 3)
}

///|
test "clearing module filters allows all events" {
  @moontrace.set_module_filter(
    "brickfrog/moontrace_blackbox_test",
    @moontrace.Error_,
  )
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("blocked")
  @moontrace.clear_module_filters()
  @moontrace.info("now allowed")
  @moontrace.clear_subscriber()
  assert_eq(captured.length(), 1)
  assert_eq(captured[0].message, "now allowed")
}

///|
test "span events bypass module filtering" {
  @moontrace.set_module_filter(
    "brickfrog/moontrace_blackbox_test",
    @moontrace.Error_,
  )
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  let s = @moontrace.span("test_span")
  s.enter()
  s.exit()
  @moontrace.clear_module_filters()
  @moontrace.clear_subscriber()
  assert_eq(captured.length(), 2)
}
