///|
/// The line after the call site, so a test can name the line of its next
/// statement without hard-coding line numbers.
#callsite(autofill(loc))
fn next_line(loc~ : SourceLoc) -> Int32 {
  let text = loc.to_string()
  match text.split_once(":") {
    Some((_, rest)) =>
      match rest.split_once(":") {
        Some((line, _)) => {
          let mut n = 0
          for c in line {
            n = n * 10 + (c.to_int() - '0'.to_int())
          }
          n + 1
        }
        None => abort("bad SourceLoc: \{text}")
      }
    None => abort("bad SourceLoc: \{text}")
  }
}

///|
test "events record the caller's file and line" {
  let capture = @test.test_subscriber()
  let expected : Array[Int32] = []
  capture.with_install(() => {
    expected.push(next_line())
    @moontrace.info("free")
    let span = @moontrace.span("op")
    expected.push(next_line())
    span.warn("span method")
    expected.push(next_line())
    @moontrace.info_in_span(span, "span function")
    let log = @moontrace.logger(fields=[@moontrace.field("k", 1)])
    expected.push(next_line())
    log.info("logger")
    expected.push(next_line())
    log.in_span(span).error("logger in span")
  })
  let events = capture.captured_events()
  assert_eq(events.length(), 5)
  for i, event in events {
    assert_eq(event.file, "src/event_location_test.mbt")
    assert_eq(event.line, expected[i])
    assert_eq(event.source, "brickfrog/moontrace")
  }
}

///|
test "span lifecycle events have no call-site location" {
  let capture = @test.test_subscriber()
  capture.with_install(() => {
    let span = @moontrace.span("op")
    span.enter()
    span.exit()
  })
  let events = capture.captured_events()
  assert_eq(events.length(), 2)
  for event in events {
    assert_eq(event.file, "")
    assert_eq(event.line, 0)
  }
}

///|
test "event JSON includes file and line only when known" {
  let located = @moontrace.Event::{
    level: @moontrace.Info,
    message: "m",
    fields: [],
    timestamp: 1UL,
    source: "brickfrog/app",
    file: "src/app/main.mbt",
    line: 42,
  }
  assert_eq(
    located.to_json().stringify(),
    "{\"level\":\"INFO\",\"message\":\"m\",\"timestamp\":\"1\",\"source\":\"brickfrog/app\",\"file\":\"src/app/main.mbt\",\"line\":42,\"fields\":{}}",
  )
  let unlocated = { ..located, file: "", line: 0, }
  assert_eq(
    unlocated.to_json().stringify(),
    "{\"level\":\"INFO\",\"message\":\"m\",\"timestamp\":\"1\",\"source\":\"brickfrog/app\",\"fields\":{}}",
  )
}

///|
test "console location is opt-in" {
  let event = @moontrace.Event::{
    level: @moontrace.Warn,
    message: "m",
    fields: [],
    timestamp: 0UL,
    source: "brickfrog/app/db",
    file: "src/app/db/pool.mbt",
    line: 7,
  }
  assert_eq(event.format(), "00:00:00.000 | WARN  | app/db — m")
  assert_eq(
    event.format(location=true),
    "00:00:00.000 | WARN  | app/db | src/app/db/pool.mbt:7 — m",
  )
  assert_eq(
    { ..event, file: "", line: 0, }.format(location=true),
    "00:00:00.000 | WARN  | app/db — m",
  )
}

///|
test "redaction preserves call-site location" {
  let seen : Array[@moontrace.Event] = []
  let sub = @moontrace.redact(event => seen.push(event))
  sub(@moontrace.Event::{
    level: @moontrace.Info,
    message: "m",
    fields: [@moontrace.field("password", "x")],
    timestamp: 0UL,
    source: "brickfrog/app",
    file: "src/app/main.mbt",
    line: 3,
  })
  assert_eq(seen[0].file, "src/app/main.mbt")
  assert_eq(seen[0].line, 3)
}
