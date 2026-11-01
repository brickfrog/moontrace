///|
fn sample_console_event(
  level : @moontrace.Level,
  message : String,
  fields~ : Array[@moontrace.Field] = [],
  source~ : String = "brickfrog/choir/server",
) -> @moontrace.Event {
  @moontrace.Event::{
    level,
    message,
    fields,
    timestamp: (52_303_903 : UInt64),
    source,
    file: "",
    line: 0,
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
      fields=@moontrace.fields([("service", Json("choir"))]),
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
      fields=@moontrace.fields([("detail", Json("needs attention"))]),
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

///|
test "console subscriber shows file and line when location is enabled" {
  let output : Array[String] = []
  let subscriber = @console.subscriber(color=false, location=true, output=fn(
    s,
  ) {
    output.push(s)
  })
  subscriber({
    ..sample_console_event(@moontrace.Info, "hello"),
    file: "src/server/main.mbt",
    line: 12,
  })
  assert_true(
    output[0].contains(" | choir/server | src/server/main.mbt:12 — "),
  )
}

///|
test "console format hook replaces the built-in layout" {
  let output : Array[String] = []
  let subscriber = @console.subscriber(
    output=s => output.push(s),
    format=event => "[\{event.level}] \{event.message}",
    pretty=true,
  )
  subscriber(sample_console_event(@moontrace.Warn, "custom"))
  assert_eq(output, ["[WARN] custom"])
}

///|
test "console pretty mode puts fields on indented lines" {
  let output : Array[String] = []
  let subscriber = @console.subscriber(
    color=false,
    pretty=true,
    location=true,
    output=s => output.push(s),
  )
  subscriber({
    ..sample_console_event(@moontrace.Error_, "request failed", fields=[
      @moontrace.field("path", "/api\nusers"),
      @moontrace.field("status", 503),
      @moontrace.field("detail", { "retry": true }),
    ]),
    file: "src/server/main.mbt",
    line: 9,
  })
  assert_eq(
    output[0],
    (
      #|14:31:43.903 | ERROR | choir/server — request failed
      #|    at src/server/main.mbt:9
      #|    path: /api\nusers
      #|    status: 503
      #|    detail: {
      #|        "retry": true
      #|      }
    ),
  )
}

///|
test "console pretty mode without fields matches the single-line header" {
  let event = sample_console_event(@moontrace.Info, "ready")
  assert_eq(
    @moontrace.format_event_pretty(
      event, false, @moontrace.format_timestamp_utc,
    ),
    @moontrace.format_event(event, false, @moontrace.format_timestamp_utc),
  )
}

///|
test "console span observer prints closed spans with durations" {
  let output : Array[String] = []
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_observer(
      @console.span_observer(color=false, output=s => output.push(s), format_timestamp=_ => {
        "T"
      }),
    )
    let span = @moontrace.span("db.query", fields=[
      @moontrace.field("table", "users"),
    ])
    span.enter()
    span.set_status(@moontrace.SpanError, message=Some("timeout"))
    span.exit()
  })
  assert_eq(output.length(), 1)
  assert_true(
    output[0].has_prefix("T | SPAN  | db.query — closed  duration_ms="),
  )
  assert_true(
    output[0].has_suffix(
      " status=ERROR status_message=\"timeout\" table=\"users\"",
    ),
  )
}

///|
test "console span observer skips spans shorter than min_duration_ms" {
  let output : Array[String] = []
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_observer(
      @console.span_observer(
        output=s => output.push(s),
        min_duration_ms=3_600_000UL,
      ),
    )
    let span = @moontrace.span("fast")
    span.enter()
    span.exit()
  })
  assert_eq(output, [])
}

///|
test "format_span_close escapes the span name" {
  let span = @moontrace.Span::{
    name: "a\nb",
    fields: [],
    links: [],
    events: [],
    trace_id: "",
    span_id: "",
    parent_span_id: "",
    trace_flags: 1,
    trace_state: @moontrace.TraceState::empty(),
    kind: @moontrace.Internal,
    start_time: 1000UL,
    end_time: 1012UL,
    active: false,
    status: @moontrace.Unset,
    status_message: "",
  }
  assert_eq(
    @moontrace.format_span_close(span, format_timestamp=_ => "T"),
    "T | SPAN  | a\\nb — closed  duration_ms=12",
  )
}
