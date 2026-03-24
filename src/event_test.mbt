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
  // Verify the JSON string contains expected keys and values with correct structure
  assert_true(s.contains("\"level\":\"INFO\""))
  assert_true(s.contains("\"message\":\"hello\""))
  assert_true(s.contains("\"fields\":{\"key\":\"val\""))
  assert_true(s.contains("\"timestamp\":"))
  @moontrace.clear_subscriber()
}

///|
test "min level gates emit" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.set_min_level(@moontrace.Warn)
  @moontrace.debug("skip")
  @moontrace.info("skip")
  @moontrace.warn("keep")
  @moontrace.error("keep")
  // Reset global state before assertions so it's restored even if they fail
  @moontrace.set_min_level(@moontrace.Trace)
  @moontrace.clear_subscriber()
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "keep")
}

///|
test "get_min_level returns current level" {
  let original = @moontrace.get_min_level()
  @moontrace.set_min_level(@moontrace.Trace)
  assert_eq(@moontrace.get_min_level(), @moontrace.Trace)
  @moontrace.set_min_level(@moontrace.Error_)
  assert_eq(@moontrace.get_min_level(), @moontrace.Error_)
  @moontrace.set_min_level(original)
}
