///|
test "execute delivers to attached handlers in order with copied data" {
  let seen : Array[String] = []
  let measurements = { "rows": 3.0 }
  @telemetry.with_handler(
    "first",
    ["db.query"],
    event => {
      seen.push(
        "first \{event.name} \{event.measurements.get("rows").unwrap_or(-1.0)}",
      )
      event.measurements.set("rows", 99.0)
    },
    () => {
      @telemetry.with_handler(
        "second",
        ["db.query", "db.other"],
        event => {
          seen.push("second \{event.measurements.get("rows").unwrap_or(-1.0)}")
        },
        () => {
          @telemetry.execute("db.query", measurements, metadata={
            "table": Json("users"),
          })
          @telemetry.execute("unrelated", {})
        },
      )
    },
  )
  assert_eq(seen, ["first db.query 3", "second 3"])
  assert_eq(measurements.get("rows"), Some(3.0))
  assert_eq(@telemetry.handler_ids(), [])
}

///|
test "attach rejects duplicate ids and detach reports removal" {
  assert_true(@telemetry.attach("dup", "a", _ => ()))
  assert_false(@telemetry.attach("dup", "b", _ => ()))
  assert_eq(@telemetry.handler_ids(name="a"), ["dup"])
  assert_eq(@telemetry.handler_ids(name="b"), [])
  assert_true(@telemetry.detach("dup"))
  assert_false(@telemetry.detach("dup"))
}

///|
test "span emits start and stop with duration" {
  let events : Array[@telemetry.TelemetryEvent] = []
  let result = @telemetry.with_handler(
    "span",
    ["job.start", "job.stop", "job.exception"],
    event => events.push(event),
    () => @telemetry.span("job", metadata={ "id": Json(1) }, () => 42),
  )
  assert_eq(result, 42)
  assert_eq(events.map(e => e.name), ["job.start", "job.stop"])
  assert_true(events[0].measurements.contains("system_time_ms"))
  assert_true(
    events[1].measurements.get("duration_ms") is Some(ms) && ms >= 0.0,
  )
  assert_eq(events[1].metadata.get("id"), Some(Json(1)))
}

///|
test "span reports exceptions and re-raises them" {
  let events : Array[@telemetry.TelemetryEvent] = []
  let raised = @telemetry.with_handler(
    "span-err",
    ["job.start", "job.stop", "job.exception"],
    event => events.push(event),
    () => {
      @telemetry.span("job", () => fail("boom")) catch {
        Failure(message) => message
      }
    },
  )
  assert_true(raised.contains("boom"))
  assert_eq(events.map(e => e.name), ["job.start", "job.exception"])
  match events[1].metadata.get("error") {
    Some(String(text)) => assert_true(text.contains("boom"))
    _ => fail("expected an error description")
  }
}

///|
test "handlers get deep copies of nested metadata" {
  let seen : Array[String] = []
  let metadata : Map[String, Json] = {
    "tags": Json(["a"]),
    "nested": { "k": Json(1) },
  }
  let mutate = (event : @telemetry.TelemetryEvent) => {
    if event.metadata.get("tags") is Some(Array(items)) {
      items.push(Json("mutated"))
    }
    if event.metadata.get("nested") is Some(Object(inner)) {
      inner.set("k", Json(2))
    }
  }
  let observe = (event : @telemetry.TelemetryEvent) => {
    let tags = event.metadata.get("tags").unwrap().stringify()
    let nested = event.metadata.get("nested").unwrap().stringify()
    seen.push(tags + nested)
  }
  @telemetry.with_handler("mutator", ["evt"], mutate, () => {
    @telemetry.with_handler("observer", ["evt"], observe, () => {
      @telemetry.execute("evt", {}, metadata~)
    })
  })
  assert_eq(seen, ["[\"a\"]{\"k\":1}"])
  assert_eq(metadata.get("tags"), Some(Json(["a"])))
}

///|
test "span measures durations with an injected clock" {
  let now = Ref(100UL)
  let events : Array[@telemetry.TelemetryEvent] = []
  @telemetry.with_handler(
    "clock",
    ["t.start", "t.stop"],
    event => events.push(event),
    () => @telemetry.span("t", clock=() => now.val, () => now.val = 145UL),
  )
  assert_eq(events[0].measurements.get("system_time_ms"), Some(100.0))
  assert_eq(events[1].measurements.get("duration_ms"), Some(45.0))
}
