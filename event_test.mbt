///|
test "subscriber captures events" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })

  @moontrace.info("hello")
  @moontrace.warn("careful", fields=@moontrace.fields([("x", (1).to_json())]))

  assert_eq(captured.length(), 2)
  assert_eq(captured[0].level, @moontrace.Info)
  assert_eq(captured[0].message, "hello")

  assert_eq(captured[1].level, @moontrace.Warn)
  assert_eq(captured[1].message, "careful")

  // Reset global_subscriber to test that events are dropped
  @moontrace.global_subscriber.val = None
  @moontrace.info("dropped")
  assert_eq(captured.length(), 2)
}
