///|
test "event to_string matches format" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("show")
  let ts = captured[0].to_string()
  let fmt = captured[0].format()
  assert_eq(ts, fmt)
  // Verify Show works via string interpolation
  let shown = "\{captured[0]}"
  assert_eq(shown, fmt)
  @moontrace.clear_subscriber()
}
