///|
test "full pipeline: subscribe, emit, capture, verify" {
  // Set up a collecting subscriber
  let captured : Array[@moontrace.Event] = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })

  // Emit events at all levels
  @moontrace.trace("t")
  @moontrace.debug("d")
  @moontrace.info("i", fields=@moontrace.fields([("key", "val".to_json())]))
  @moontrace.warn("w")
  @moontrace.error("e")

  // Verify all 5 captured
  assert_eq(captured.length(), 5)
  assert_eq(captured[0].level, @moontrace.Trace)
  assert_eq(captured[1].level, @moontrace.Debug)
  assert_eq(captured[2].level, @moontrace.Info)
  assert_eq(captured[3].level, @moontrace.Warn)
  assert_eq(captured[4].level, @moontrace.Error_)

  // Verify structured fields preserved
  assert_eq(captured[2].fields.length(), 1)
  assert_eq(captured[2].fields[0].key, "key")

  // Verify format() produces readable output
  let formatted = captured[2].format()
  assert_true(formatted.contains("INFO"))
  assert_true(formatted.contains("i"))
  assert_true(formatted.contains("key="))

  // Verify Show trait works via interpolation
  let shown = "\{captured[2]}"
  assert_eq(shown, formatted)

  @moontrace.clear_subscriber()
}

///|
test "full pipeline: spans with nested context" {
  let captured : Array[@moontrace.Event] = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })

  @moontrace.with_span_ctx("request", fn(parent) {
    @moontrace.info("handling")
    @moontrace.with_child_span(parent, "db", fn(child) {
      child.record("query", "SELECT *")
      @moontrace.debug("querying")
    })
  })

  // Expected: span.enter request, info, span.enter db, debug, span.exit db, span.exit request
  assert_eq(captured.length(), 6)
  assert_eq(captured[0].message, "span.enter request")
  assert_eq(captured[1].message, "handling")
  assert_eq(captured[2].message, "span.enter db")
  assert_eq(captured[3].message, "querying")
  assert_eq(captured[4].message, "span.exit db")
  assert_eq(captured[5].message, "span.exit request")

  // Exit event should have duration_ns
  let mut has_duration = false
  captured[4].fields.each(fn(f) {
    if f.key == "duration_ns" {
      has_duration = true
    }
  })
  assert_eq(has_duration, true)

  @moontrace.clear_subscriber()
}

///|
test "full pipeline: event to_json roundtrip" {
  let captured : Array[@moontrace.Event] = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })

  @moontrace.info(
    "hello",
    fields=@moontrace.fields([
      ("count", (42).to_json()),
      ("tag", "test".to_json()),
    ]),
  )

  let json_str = captured[0].to_json().stringify()

  // Verify JSON contains expected structure
  assert_true(json_str.contains("\"level\":\"INFO\""))
  assert_true(json_str.contains("\"message\":\"hello\""))
  assert_true(json_str.contains("\"timestamp\":"))
  assert_true(json_str.contains("\"fields\":{"))
  assert_true(json_str.contains("\"count\":42"))
  assert_true(json_str.contains("\"tag\":\"test\""))

  // Verify span to_json also works
  let s = @moontrace.span("test_span").with_field("x", 1)
  let span_json = s.to_json().stringify()
  assert_true(span_json.contains("\"name\":\"test_span\""))
  assert_true(span_json.contains("\"active\":false"))

  @moontrace.clear_subscriber()
}

///|
test "full pipeline: min level gate + compose" {
  let console_out : Array[String] = []
  let json_out : Array[String] = []

  // Composed subscriber: console (warn+) and json (all)
  let console_sub = @moontrace.with_filter(
    fn(e : @moontrace.Event) { console_out.push(e.format()) },
    @moontrace.Warn,
  )
  let json_sub = fn(e : @moontrace.Event) {
    json_out.push(e.to_json().stringify())
  }
  @moontrace.set_subscriber(@moontrace.compose([console_sub, json_sub]))

  // Global gate at Info (skips trace/debug allocation entirely)
  @moontrace.set_min_level(@moontrace.Info)

  @moontrace.trace("skip")
  @moontrace.debug("skip")
  @moontrace.info("keep-json-only")
  @moontrace.warn("keep-both")
  @moontrace.error("keep-both")

  // Reset global state
  @moontrace.set_min_level(@moontrace.Trace)
  @moontrace.clear_subscriber()

  // trace/debug gated at emit — nothing reaches either subscriber
  // info reaches json only (console filters at Warn)
  // warn+error reach both
  assert_eq(json_out.length(), 3)
  assert_eq(console_out.length(), 2)
}
