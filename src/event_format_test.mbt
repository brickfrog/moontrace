///|
test "event format basic" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("hello")
  let formatted = captured[0].format()
  assert_true(formatted.contains("INFO"))
  assert_true(formatted.contains("hello"))
  @moontrace.clear_subscriber()
}

///|
test "event format includes fields" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("msg", fields=@moontrace.fields([("key", "val".to_json())]))
  let formatted = captured[0].format()
  assert_true(formatted.contains("key="))
  assert_true(formatted.contains("val"))
  @moontrace.clear_subscriber()
}

///|
test "event format with color" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("colored")
  let formatted = captured[0].format(color=true)
  // Should contain ANSI green for INFO
  assert_true(formatted.contains("\u001b[32m"))
  assert_true(formatted.contains("\u001b[0m"))
  assert_true(formatted.contains("INFO"))
  @moontrace.clear_subscriber()
}

///|
test "event format default no color" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.warn("plain")
  let formatted = captured[0].format()
  // Should NOT contain any ANSI escape codes
  assert_true(formatted.contains("WARN"))
  assert_true(formatted.contains("plain"))
  assert_true(!formatted.contains("\u001b["))
  @moontrace.clear_subscriber()
}
