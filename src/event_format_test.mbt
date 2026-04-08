///|
fn sample_event(
  level : @moontrace.Level,
  message : String,
  fields? : Array[@moontrace.Field] = [],
  source? : String = "brickfrog/choir/server",
) -> @moontrace.Event {
  @moontrace.Event::{
    level,
    message,
    fields,
    timestamp: (52_303_903 : UInt64),
    source,
  }
}

///|
test "format timestamp utc zero pads components" {
  let timestamp = (52_303_903 : UInt64)
  assert_eq(@moontrace.format_timestamp_utc(timestamp), "14:31:43.903")
}

///|
test "format timestamp utc wraps after 24 hours" {
  // 25*3600*1000 + 3*1000 + 4 = 90_003_004 ms → wraps to 01:00:03.004
  let timestamp = (90_003_004 : UInt64)
  assert_eq(@moontrace.format_timestamp_utc(timestamp), "01:00:03.004")
}

///|
test "event format basic" {
  let formatted = sample_event(@moontrace.Info, "hello").format()
  assert_eq(formatted, "14:31:43.903 | INFO  | choir/server — hello")
}

///|
test "event format includes fields" {
  let event = sample_event(
    @moontrace.Info,
    "msg",
    fields=@moontrace.fields([
      ("key", "val".to_json()),
      ("detail", "needs attention".to_json()),
    ]),
  )
  assert_eq(
    event.format(),
    "14:31:43.903 | INFO  | choir/server — msg  key=\"val\" detail=\"needs attention\"",
  )
}

///|
test "event format with color" {
  let formatted = sample_event(@moontrace.Info, "colored").format(color=true)
  assert_eq(
    formatted, "14:31:43.903 | \u001b[32mINFO \u001b[0m | choir/server — colored",
  )
}

///|
test "event format omits source when empty" {
  let formatted = sample_event(@moontrace.Warn, "plain", source="").format()
  assert_eq(formatted, "14:31:43.903 | WARN  — plain")
}

///|
test "event format colors the padded level only" {
  let event = sample_event(
    @moontrace.Warn,
    "colored",
    fields=@moontrace.fields([("service", "choir".to_json())]),
  )
  assert_eq(
    event.format(color=true),
    "14:31:43.903 | \u001b[33mWARN \u001b[0m | choir/server — colored  service=\"choir\"",
  )
}

///|
test "event format two spaces before fields one between" {
  let event = sample_event(
    @moontrace.Info,
    "listening",
    fields=@moontrace.fields([
      ("service", "choir".to_json()),
      ("path", ".choir/server.sock".to_json()),
    ]),
  )
  assert_eq(
    event.format(),
    "14:31:43.903 | INFO  | choir/server — listening  service=\"choir\" path=\".choir/server.sock\"",
  )
}

///|
test "format timestamp utc at zero" {
  assert_eq(@moontrace.format_timestamp_utc((0 : UInt64)), "00:00:00.000")
}

///|
test "level_color returns ANSI codes for each level" {
  assert_eq(@moontrace.level_color(@moontrace.Trace), "\u001b[2m")
  assert_eq(@moontrace.level_color(@moontrace.Debug), "\u001b[34m")
  assert_eq(@moontrace.level_color(@moontrace.Info), "\u001b[32m")
  assert_eq(@moontrace.level_color(@moontrace.Warn), "\u001b[33m")
  assert_eq(@moontrace.level_color(@moontrace.Error_), "\u001b[31m")
}
