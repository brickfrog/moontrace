///|
test "capture returns events from a scoped subscriber and restores state" {
  let events = @test.capture(() => {
    @moontrace.info("one")
    @moontrace.warn("two")
  })
  assert_eq(events.map(e => e.message), ["one", "two"])
  let empty = @test.capture(() => ())
  assert_eq(empty.length(), 0)
}

///|
test "check_no_event reports unexpected matches" {
  let capture = @test.test_subscriber()
  capture.with_install(() => @moontrace.warn("disk low"))
  assert_true(
    capture.check_no_event(@test.event_with_level(@moontrace.Error_)) is None,
  )
  capture.assert_no_event(@test.event_with_message("missing"))
  match capture.check_no_event(@test.event_with_message("disk low")) {
    Some(message) => {
      assert_true(message.has_prefix("unexpected "))
      assert_true(message.contains("disk low"))
    }
    None => fail("expected a failure message")
  }
}
