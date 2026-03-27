///|
test "format timestamp hms zero pads components" {
  let timestamp = (52_303_903_000_000 : UInt64)
  assert_eq(@moontrace.format_timestamp_hms(timestamp), "14:31:43.903")
}

///|
test "format timestamp hms wraps after 24 hours" {
  let timestamp = (90_003_004_000_000 : UInt64)
  assert_eq(@moontrace.format_timestamp_hms(timestamp), "01:00:03.004")
}

///|
test "event format matches console style" {
  let event = @moontrace.Event::{
    level: @moontrace.Debug,
    message: "no listen_tcp configured",
    fields: @moontrace.fields([("service", "choir".to_json())]),
    timestamp: (52_303_903_000_000 : UInt64),
    source: "choir/server",
  }

  assert_eq(
    event.format(),
    "14:31:43.903 | DEBUG | choir/server — no listen_tcp configured  service=\"choir\"",
  )
}

///|
test "event format omits source separator when source is empty" {
  let event = @moontrace.Event::{
    level: @moontrace.Info,
    message: "UDS server listening",
    fields: [],
    timestamp: (52_303_903_000_000 : UInt64),
    source: "",
  }

  assert_eq(event.format(), "14:31:43.903 | INFO  — UDS server listening")
}

///|
test "event format colors the padded level only" {
  let event = @moontrace.Event::{
    level: @moontrace.Warn,
    message: "colored",
    fields: @moontrace.fields([("service", "choir".to_json())]),
    timestamp: (52_303_903_000_000 : UInt64),
    source: "choir/server",
  }

  assert_eq(
    event.format(color=true),
    "14:31:43.903 | \u001b[33mWARN \u001b[0m | choir/server — colored  service=\"choir\"",
  )
}

///|
test "event format uses two spaces before first field and one between fields" {
  let event = @moontrace.Event::{
    level: @moontrace.Info,
    message: "listening",
    fields: @moontrace.fields([
      ("service", "choir".to_json()),
      ("path", ".choir/server.sock".to_json()),
    ]),
    timestamp: (52_303_903_000_000 : UInt64),
    source: "choir/server",
  }

  assert_eq(
    event.format(),
    "14:31:43.903 | INFO  | choir/server — listening  service=\"choir\" path=\".choir/server.sock\"",
  )
}
