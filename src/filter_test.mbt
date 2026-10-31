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
  @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Warn)
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
  @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Info)
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
  @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Error_)
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
  @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Error_)
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  let s = @moontrace.span("test_span")
  s.enter()
  s.exit()
  @moontrace.clear_module_filters()
  @moontrace.clear_subscriber()
  assert_eq(captured.length(), 2)
}

///|
test "enabled is false without a subscriber" {
  @moontrace.with_trace_state(() => {
    @moontrace.clear_subscriber()
    assert_true(!@moontrace.enabled(@moontrace.Error_))
  })
}

///|
test "enabled follows global and module filters for the caller package" {
  @moontrace.with_trace_state(() => {
    @moontrace.set_subscriber(fn(_) { () })
    @moontrace.set_min_level(@moontrace.Info)
    assert_true(!@moontrace.enabled(@moontrace.Debug))
    assert_true(@moontrace.enabled(@moontrace.Info))

    @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Trace)
    assert_true(@moontrace.enabled(@moontrace.Trace))

    @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Error_)
    assert_true(!@moontrace.enabled(@moontrace.Warn))
  })
}

///|
#callsite(autofill(loc))
fn enabled_through_wrapper(level : @moontrace.Level, loc~ : SourceLoc) -> Bool {
  @moontrace.enabled(level, loc~)
}

///|
test "enabled agrees with emission and forwards caller metadata" {
  @moontrace.with_trace_state(() => {
    let captured : Array[@moontrace.Event] = []
    @moontrace.set_subscriber(fn(e) { captured.push(e) })
    @moontrace.set_min_level(@moontrace.Warn)
    for
      level in [
        @moontrace.Trace,
        @moontrace.Debug,
        @moontrace.Info,
        @moontrace.Warn,
        @moontrace.Error_,
      ] {
      let before = captured.length()
      @moontrace.event_in_span(@moontrace.span("probe"), level, "probe")
      assert_eq(captured.length() > before, @moontrace.enabled(level))
      assert_eq(enabled_through_wrapper(level), @moontrace.enabled(level))
    }
  })
}
