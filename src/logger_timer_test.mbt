///|
test "log timers add duration_ms and keep bound fields" {
  let events = @test.capture(() => {
    let log = @moontrace.logger(fields=[@moontrace.field("job", "sync")])
    let timer = log.start_timer()
    timer.done("sync finished", fields=[
      @moontrace.field("items", 3),
      @moontrace.field("duration_ms", "overridden"),
    ])
    timer.done("sync slow", level=@moontrace.Warn)
  })
  assert_eq(events.length(), 2)
  let first = events[0]
  assert_eq(first.message, "sync finished")
  assert_eq(first.level, @moontrace.Info)
  assert_eq(first.file, "src/logger_timer_test.mbt")
  let keys = first.fields.map(f => f.key)
  assert_true(keys.contains("job"))
  assert_true(keys.contains("items"))
  let duration = first.fields.filter(f => f.key == "duration_ms")
  assert_eq(duration.length(), 1)
  assert_true(duration[0].value is Number(ms, ..) && ms >= 0.0)
  assert_eq(events[1].level, @moontrace.Warn)
}
