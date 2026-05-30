///|
suberror ExampleFailure

///|
test "example capture subscriber replaces manual captured arrays" {
  let capture = test_subscriber()

  capture.with_install(fn() {
    @moontrace.info("hello")
    @moontrace.warn("careful")
  })

  assert_eq(capture.captured_events().length(), 2)
  capture.assert_events_ordered([
    event_with_level(@moontrace.Info).with_message("hello"),
    event_with_level(@moontrace.Warn).with_message("careful"),
  ])
}

///|
test "ordered and unordered event assertions" {
  let capture = test_subscriber()

  capture.with_install(fn() {
    @moontrace.debug("first")
    @moontrace.info("second")
    @moontrace.error("third")
  })

  capture.assert_events_ordered([
    event_with_message("first"),
    event_with_message("second"),
    event_with_message("third"),
  ])
  capture.assert_events_unordered([
    event_with_level(@moontrace.Error_).with_message("third"),
    event_with_level(@moontrace.Debug).with_message("first"),
    event_with_level(@moontrace.Info).with_message("second"),
  ])
}

///|
test "event query helpers match level message source field and span" {
  let capture = test_subscriber()
  let spans : Array[@moontrace.Span] = []

  capture.with_install(fn() {
    let span = @moontrace.span("request")
    spans.push(span)
    span.enter()
    @moontrace.info("dispatched", fields=[
      @moontrace.field("tool", "fork_wave"),
      @moontrace.field("attempt", 2),
    ])
    span.exit()
  })

  let span = spans[0]
  let source = capture.captured_events()[1].source

  assert_eq(capture.events_by_level(@moontrace.Info).length(), 1)
  assert_eq(capture.events_by_message("dispatched").length(), 1)
  assert_eq(capture.events_by_source(source).length(), 1)
  assert_eq(capture.events_by_field("tool").length(), 1)
  assert_eq(capture.events_by_field_value("attempt", 2).length(), 1)
  assert_eq(capture.events_in_span(span).length(), 2)
  assert_eq(capture.events_in_span_named("request").length(), 2)
  capture.assert_event(
    event_with_level(@moontrace.Info)
    .with_message("dispatched")
    .with_source(source)
    .with_field_value("tool", "fork_wave")
    .with_span(span),
  )
}

///|
test "span-name correlation handles overlapping spans with same name" {
  let capture = test_subscriber()

  capture.with_install(fn() {
    let span_a = @moontrace.span("phase")
    let span_b = @moontrace.span("phase")
    span_a.enter()
    span_b.enter()
    @moontrace.info("both active")
    span_b.exit()
    @moontrace.info("a still active")
    span_a.exit()
    @moontrace.info("after all")
  })

  let named_events = capture.events_in_span_named("phase")
  assert_eq(named_events.length(), 5)
  assert_eq(named_events[0].message, "span.enter phase")
  assert_eq(named_events[1].message, "span.enter phase")
  assert_eq(named_events[2].message, "both active")
  assert_eq(named_events[3].message, "span.exit phase")
  assert_eq(named_events[4].message, "a still active")
  assert_eq(
    capture
    .events_matching(event_with_message("both active").with_span_name("phase"))
    .length(),
    1,
  )
  assert_eq(
    capture
    .events_matching(
      event_with_message("a still active").with_span_name("phase"),
    )
    .length(),
    1,
  )
  assert_eq(
    capture
    .events_matching(
      event_with_message("span.exit phase").with_span_name("phase"),
    )
    .length(),
    1,
  )
  assert_eq(
    capture
    .events_matching(event_with_message("after all").with_span_name("phase"))
    .length(),
    0,
  )
}

///|
test "span lifecycle ordering around events" {
  let capture = test_subscriber()
  let spans : Array[@moontrace.Span] = []

  capture.with_install(fn() {
    let span = @moontrace.span("work")
    spans.push(span)
    span.enter()
    @moontrace.info("inside")
    span.record("phase", "running")
    @moontrace.info("after record")
    span.exit()
  })

  let span = spans[0]
  capture.assert_created_entered_recorded_exited(span)
  capture.assert_lifecycle_ordered([
    lifecycle_kind(SpanCreated).with_span(span),
    lifecycle_kind(SpanEntered).with_span(span),
    lifecycle_kind(SpanRecorded).with_span(span).with_recorded_field("phase"),
    lifecycle_kind(SpanExited).with_span(span),
    lifecycle_kind(SpanClosed).with_span(span),
  ])
  capture.assert_events_ordered([
    event_with_message("span.enter work").with_span(span),
    event_with_message("inside").with_span(span),
    event_with_message("after record").with_span(span),
  ])
  assert_eq(
    capture
    .events_matching(event_with_message("span.exit work").with_span(span))
    .length(),
    0,
  )
}

///|
test "missing event diagnostics include query and captured events" {
  let capture = test_subscriber()

  capture.with_install(fn() {
    @moontrace.info("present", fields=[@moontrace.field("tool", "fork")])
  })

  let diagnostic = capture.check_event(
    event_with_level(@moontrace.Error_)
    .with_message("missing")
    .with_field("request_id"),
  )
  guard diagnostic is Some(message) else {
    abort("expected missing event diagnostic")
  }
  assert_true(message.contains("missing event"))
  assert_true(message.contains("message=missing"))
  assert_true(message.contains("field=request_id"))
  assert_true(message.contains("present"))
}

///|
test "scoped install restores global subscriber and observer on return" {
  let base_events : Array[String] = []
  let base_lifecycle : Array[String] = []
  @moontrace.set_subscriber(fn(event) { base_events.push(event.message) })
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(on_created=fn(span) {
      base_lifecycle.push(span.name)
    }),
  )

  let capture = test_subscriber()
  capture.with_install(fn() {
    @moontrace.info("inside")
    let span = @moontrace.span("inside span")
    span.enter()
    span.exit()
  })

  @moontrace.info("after")
  let after_span = @moontrace.span("after span")

  assert_eq(capture.events_by_message("inside").length(), 1)
  assert_eq(
    capture
    .lifecycle_matching(
      lifecycle_kind(SpanCreated).with_span_name("inside span"),
    )
    .length(),
    1,
  )
  assert_eq(capture.events_by_message("after").length(), 0)
  assert_eq(
    capture
    .lifecycle_matching(lifecycle_kind(SpanCreated).with_span(after_span))
    .length(),
    0,
  )
  assert_eq(base_events.length(), 1)
  assert_eq(base_events[0], "after")
  assert_eq(base_lifecycle.length(), 1)
  assert_eq(base_lifecycle[0], "after span")

  @moontrace.clear_subscriber()
  @moontrace.clear_span_observer()
}

///|
test "scoped install restores global subscriber and observer on raise" {
  let base_events : Array[String] = []
  let base_lifecycle : Array[String] = []
  @moontrace.set_subscriber(fn(event) { base_events.push(event.message) })
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(on_created=fn(span) {
      base_lifecycle.push(span.name)
    }),
  )

  let capture = test_subscriber()
  fn fail_in_scope() -> Unit raise ExampleFailure {
    capture.with_install(() => {
      @moontrace.info("before failure")
      let span = @moontrace.span("failing span")
      span.enter()
      raise ExampleFailure
    })
  }

  let result : Result[Unit, ExampleFailure] = try? fail_in_scope()
  guard result is Err(_) else { abort("expected ExampleFailure") }

  @moontrace.info("after failure")
  let after_span = @moontrace.span("after failure span")

  assert_eq(capture.events_by_message("before failure").length(), 1)
  assert_eq(capture.events_by_message("after failure").length(), 0)
  assert_eq(
    capture
    .lifecycle_matching(
      lifecycle_kind(SpanCreated).with_span_name("failing span"),
    )
    .length(),
    1,
  )
  assert_eq(
    capture
    .lifecycle_matching(lifecycle_kind(SpanCreated).with_span(after_span))
    .length(),
    0,
  )
  assert_eq(base_events.length(), 1)
  assert_eq(base_events[0], "after failure")
  assert_eq(base_lifecycle.length(), 1)
  assert_eq(base_lifecycle[0], "after failure span")

  @moontrace.clear_subscriber()
  @moontrace.clear_span_observer()
}
