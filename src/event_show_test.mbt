///|
test "event to_string matches format" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("show")
  let ts = captured[0].to_string()
  let fmt = captured[0].format()
  assert_eq(ts, fmt)
  @moontrace.clear_subscriber()
}
