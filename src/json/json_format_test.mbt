///|
fn json_format_event(
  fields~ : Array[@moontrace.Field] = [],
  file~ : String = "src/app/main.mbt",
) -> @moontrace.Event {
  @moontrace.Event::{
    level: @moontrace.Warn,
    message: "m",
    fields,
    timestamp: 1774708303903UL,
    source: "brickfrog/app",
    file,
    line: 7,
  }
}

///|
test "event_json defaults match Event::to_json" {
  let event = json_format_event(fields=[
    @moontrace.field("count", 1),
    @moontrace.field("trace_id", "abc"),
  ])
  assert_eq(@json.event_json(event), event.to_json())
  assert_eq(
    @json.event_json(json_format_event(file="")),
    json_format_event(file="").to_json(),
  )
}

///|
test "event_json renders RFC 3339 timestamps" {
  assert_eq(
    @json.event_json(json_format_event(), timestamp=Rfc3339).stringify(),
    "{\"level\":\"WARN\",\"message\":\"m\",\"timestamp\":\"2026-03-28T14:31:43.903Z\",\"source\":\"brickfrog/app\",\"file\":\"src/app/main.mbt\",\"line\":7,\"fields\":{}}",
  )
}

///|
test "event_json flattens fields and prefixes collisions" {
  let event = json_format_event(fields=[
    @moontrace.field("user", "ann"),
    @moontrace.field("level", "custom"),
    @moontrace.field("nested", { "a": 1 }),
  ])
  assert_eq(
    @json.event_json(event, flatten=true).stringify(),
    "{\"level\":\"WARN\",\"message\":\"m\",\"timestamp\":\"1774708303903\",\"source\":\"brickfrog/app\",\"file\":\"src/app/main.mbt\",\"line\":7,\"user\":\"ann\",\"fields.level\":\"custom\",\"nested\":{\"a\":1}}",
  )
}

///|
test "event_json promotes span-correlated trace ids" {
  let captured : Array[@moontrace.Event] = []
  let span = @moontrace.span("op")
  @moontrace.with_subscriber(event => captured.push(event), () => {
    span.info("inside", fields=[@moontrace.field("k", 1)])
  })
  let json = @json.event_json(captured[0], trace_ids=true)
  guard json is Object(record) else { fail("expected object") }
  assert_eq(record.get("trace_id"), Some(Json(span.trace_id)))
  assert_eq(record.get("span_id"), Some(Json(span.span_id)))
  guard record.get("fields") is Some(Object(fields)) else {
    fail("expected fields")
  }
  assert_false(fields.contains("trace_id"))
  assert_false(fields.contains("span_id"))
  assert_true(fields.contains("parent_span_id"))
  assert_eq(fields.get("k"), Some(Json(1)))
}

///|
test "event_json renames keys" {
  let keys = @json.json_keys(
    timestamp="@timestamp",
    level="log.level",
    trace_id="trace.id",
  )
  let event = json_format_event(fields=[@moontrace.field("trace_id", "t1")])
  assert_eq(
    @json.event_json(event, keys~, trace_ids=true, timestamp=Rfc3339).stringify(),
    "{\"log.level\":\"WARN\",\"message\":\"m\",\"@timestamp\":\"2026-03-28T14:31:43.903Z\",\"source\":\"brickfrog/app\",\"file\":\"src/app/main.mbt\",\"line\":7,\"trace.id\":\"t1\",\"fields\":{}}",
  )
}

///|
test "json subscriber forwards formatting options" {
  let output : Array[String] = []
  let subscriber = @json.subscriber(
    output=line => output.push(line),
    flatten=true,
    timestamp=Rfc3339,
  )
  subscriber(json_format_event(fields=[@moontrace.field("k", true)]))
  assert_eq(
    output[0],
    "{\"level\":\"WARN\",\"message\":\"m\",\"timestamp\":\"2026-03-28T14:31:43.903Z\",\"source\":\"brickfrog/app\",\"file\":\"src/app/main.mbt\",\"line\":7,\"k\":true}",
  )
}
