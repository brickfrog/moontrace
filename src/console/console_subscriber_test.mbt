///|
fn sample_console_event(
  level : @moontrace.Level,
  message : String,
  fields? : Array[@moontrace.Field] = [],
  source? : String = "brickfrog/choir/server",
) -> @moontrace.Event {
  @moontrace.Event::{
    level,
    message,
    fields,
    timestamp: (52_303_903_000_000 : UInt64),
    source,
  }
}

///|
test "console subscriber formats pipe-separated output" {
  let output : Array[String] = []
  let subscriber = @console.subscriber(color=false, output=fn(s) {
    output.push(s)
  })
  subscriber(
    sample_console_event(
      @moontrace.Debug,
      "no listen_tcp configured",
      fields=@moontrace.fields([("service", "choir".to_json())]),
    ),
  )
  assert_eq(output.length(), 1)
  assert_eq(
    output[0],
    "14:31:43.903 | DEBUG | choir/server — no listen_tcp configured  service=\"choir\"",
  )
}

///|
test "console subscriber omits empty source" {
  let output : Array[String] = []
  let subscriber = @console.subscriber(color=false, output=fn(s) {
    output.push(s)
  })
  subscriber(
    sample_console_event(
      @moontrace.Info,
      "follow up",
      fields=@moontrace.fields([("detail", "needs attention".to_json())]),
      source="",
    ),
  )
  assert_eq(output.length(), 1)
  assert_eq(
    output[0],
    "14:31:43.903 | INFO  — follow up  detail=\"needs attention\"",
  )
}

///|
test "console subscriber min_level filtering" {
  let output : Array[String] = []
  let subscriber = @console.subscriber(min_level=@moontrace.Warn, color=false, output=fn(
    s,
  ) {
    output.push(s)
  })
  subscriber(
    sample_console_event(@moontrace.Info, "skip", source="brickfrog/moontrace"),
  )
  subscriber(
    sample_console_event(@moontrace.Warn, "keep", source="brickfrog/moontrace"),
  )
  assert_eq(output.length(), 1)
  assert_eq(output[0], "14:31:43.903 | WARN  | moontrace — keep")
}

///|
test "console subscriber no ansi when color false" {
  let output : Array[String] = []
  let subscriber = @console.subscriber(color=false, output=fn(s) {
    output.push(s)
  })
  subscriber(
    sample_console_event(@moontrace.Info, "test", source="brickfrog/moontrace"),
  )
  assert_eq(output.length(), 1)
  assert_false(output[0].contains("\u001b"))
}

///|
test "console subscriber ansi color" {
  let output : Array[String] = []
  let subscriber = @console.subscriber(color=true, output=fn(s) {
    output.push(s)
  })
  subscriber(
    sample_console_event(
      @moontrace.Warn,
      "colored",
      source="brickfrog/moontrace",
    ),
  )
  assert_eq(output.length(), 1)
  assert_eq(
    output[0],
    "14:31:43.903 | \u001b[33mWARN \u001b[0m | moontrace — colored",
  )
}

///|
test "console initialize convenience function" {
  let output : Array[String] = []
  @console.initialize(min_level=@moontrace.Warn, color=true, output=fn(s) {
    output.push(s)
  })
  @moontrace.info("skip")
  @moontrace.warn("keep")
  @moontrace.clear_subscriber()
  assert_eq(output.length(), 1)
  assert_true(output[0].contains(" | "))
  assert_true(output[0].contains(" — "))
  assert_true(output[0].contains("\u001b[33m"))
}
