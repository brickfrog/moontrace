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

  // Reset global_subscriber via public API to test that events are dropped
  @moontrace.clear_subscriber()
  @moontrace.info("dropped")
  assert_eq(captured.length(), 2)
}

///|
test "trace emits event" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.trace("tracing")
  assert_eq(captured.length(), 1)
  assert_eq(captured[0].level, @moontrace.Trace)
  assert_eq(captured[0].message, "tracing")
  @moontrace.clear_subscriber()
}

///|
test "event to_json has correct structure" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("hello", fields=@moontrace.fields([("key", "val".to_json())]))
  let json = captured[0].to_json()
  let s = json.stringify()
  // Verify the JSON string contains expected keys and values
  assert_true(s.contains("level"))
  assert_true(s.contains("INFO"))
  assert_true(s.contains("hello"))
  assert_true(s.contains("key"))
  @moontrace.clear_subscriber()
}
