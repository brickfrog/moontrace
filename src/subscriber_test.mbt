///|
test "compose fans out to multiple subscribers" {
  let a : Array[String] = []
  let b : Array[String] = []
  let sub1 = fn(e : @moontrace.Event) { a.push(e.message) }
  let sub2 = fn(e : @moontrace.Event) { b.push(e.message) }
  @moontrace.set_subscriber(@moontrace.compose([sub1, sub2]))
  @moontrace.info("hello")
  assert_eq(a.length(), 1)
  assert_eq(b.length(), 1)
  assert_eq(a[0], "hello")
  assert_eq(b[0], "hello")
  @moontrace.clear_subscriber()
}

///|
test "compose with empty array does not crash" {
  @moontrace.set_subscriber(@moontrace.compose([]))
  @moontrace.info("noop")
  @moontrace.clear_subscriber()
}

///|
test "with_filter blocks events below min_level" {
  let captured : Array[String] = []
  let sub = fn(e : @moontrace.Event) { captured.push(e.message) }
  @moontrace.set_subscriber(@moontrace.with_filter(sub, @moontrace.Warn))
  @moontrace.debug("skip")
  @moontrace.info("skip")
  @moontrace.warn("keep1")
  @moontrace.error("keep2")
  assert_eq(captured.length(), 2)
  assert_eq(captured[0], "keep1")
  assert_eq(captured[1], "keep2")
  @moontrace.clear_subscriber()
}

///|
test "compose with with_filter" {
  let all_events : Array[String] = []
  let errors_only : Array[String] = []
  let sub_all = fn(e : @moontrace.Event) { all_events.push(e.message) }
  let sub_errors = fn(e : @moontrace.Event) { errors_only.push(e.message) }
  @moontrace.set_subscriber(
    @moontrace.compose([
      sub_all,
      @moontrace.with_filter(sub_errors, @moontrace.Error_),
    ]),
  )
  @moontrace.info("i")
  @moontrace.error("e")
  assert_eq(all_events.length(), 2)
  assert_eq(errors_only.length(), 1)
  assert_eq(errors_only[0], "e")
  @moontrace.clear_subscriber()
}
