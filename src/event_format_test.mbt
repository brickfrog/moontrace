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
