///|
fn span_event_field_value(event : @moontrace.Event, key : String) -> Json? {
  let mut found : Json? = None
  event.fields.each(fn(field) {
    if field.key == key {
      found = Some(field.value)
    }
  })
  found
}

///|
fn span_event_field_count(event : @moontrace.Event, key : String) -> Int {
  let mut count = 0
  event.fields.each(fn(field) { if field.key == key { count = count + 1 } })
  count
}

///|
fn assert_span_event_field(
  event : @moontrace.Event,
  key : String,
  expected : Json,
) -> Unit {
  match span_event_field_value(event, key) {
    Some(value) =>
      if value.stringify() != expected.stringify() {
        abort("field \{key} did not match expected value")
      }
    None => abort("missing field \{key}")
  }
}

///|
fn assert_no_span_event_field(event : @moontrace.Event, key : String) -> Unit {
  match span_event_field_value(event, key) {
    Some(_) => abort("unexpected field \{key}")
    None => ()
  }
}

///|
fn assert_span_correlation(
  event : @moontrace.Event,
  span : @moontrace.Span,
) -> Unit {
  assert_span_event_field(event, "trace_id", span.trace_id.to_json())
  assert_span_event_field(event, "span_id", span.span_id.to_json())
  assert_span_event_field(
    event,
    "parent_span_id",
    span.parent_span_id.to_json(),
  )
}

///|
test "Span::info carries root span correlation fields" {
  let captured : Array[@moontrace.Event] = []
  let root = @moontrace.span("root")

  @moontrace.with_trace_state(fn() {
    @moontrace.set_subscriber(fn(event) { captured.push(event) })
    root.info("root event", fields=[@moontrace.field("work", "root")])
  })

  assert_eq(captured.length(), 1)
  assert_eq(captured[0].level, @moontrace.Info)
  assert_eq(captured[0].message, "root event")
  assert_span_correlation(captured[0], root)
  assert_span_event_field(captured[0], "work", "root".to_json())

  let json = captured[0].to_json().stringify()
  assert_true(json.contains("\"trace_id\":\"\{root.trace_id}\""))
  assert_true(json.contains("\"span_id\":\"\{root.span_id}\""))
  assert_true(json.contains("\"parent_span_id\":\"\""))
}

///|
test "warn_in_span carries child span correlation fields" {
  let captured : Array[@moontrace.Event] = []
  let mut parent_span_id = ""
  let mut child : @moontrace.Span? = None

  @moontrace.with_trace_state(fn() {
    @moontrace.set_min_level(@moontrace.Info)
    @moontrace.set_subscriber(fn(event) { captured.push(event) })
    @moontrace.with_span_ctx("parent", fn(parent) {
      parent_span_id = parent.span_id
      @moontrace.with_child_span(parent, "child", fn(child_span) {
        child = Some(child_span)
        @moontrace.warn_in_span(child_span, "child event")
      })
    })
  })

  assert_eq(captured.length(), 1)
  assert_eq(captured[0].level, @moontrace.Warn)
  match child {
    Some(child_span) => {
      assert_span_correlation(captured[0], child_span)
      assert_eq(child_span.parent_span_id, parent_span_id)
      assert_eq(child_span.trace_id.length(), 32)
    }
    None => abort("expected child span")
  }
}

///|
test "span event correlation follows lifecycle order" {
  let order : Array[String] = []
  let captured : Array[@moontrace.Event] = []
  let mut span : @moontrace.Span? = None

  @moontrace.with_trace_state(fn() {
    @moontrace.set_min_level(@moontrace.Info)
    @moontrace.set_subscriber(fn(event) {
      order.push("event:\{event.message}")
      captured.push(event)
    })
    @moontrace.set_span_observer(
      @moontrace.span_lifecycle_observer(
        on_created=fn(observed) { order.push("created:\{observed.span_id}") },
        on_entered=fn(observed) { order.push("entered:\{observed.span_id}") },
        on_exited=fn(observed) { order.push("exited:\{observed.span_id}") },
        on_closed=fn(observed) { order.push("closed:\{observed.span_id}") },
      ),
    )

    let s = @moontrace.span("ordered")
    span = Some(s)
    s.enter()
    s.event(@moontrace.Info, "during")
    s.exit()
    @moontrace.clear_span_observer()
  })

  assert_eq(order.length(), 5)
  match span {
    Some(s) => {
      assert_eq(order[0], "created:\{s.span_id}")
      assert_eq(order[1], "entered:\{s.span_id}")
      assert_eq(order[2], "event:during")
      assert_eq(order[3], "exited:\{s.span_id}")
      assert_eq(order[4], "closed:\{s.span_id}")
      assert_eq(captured.length(), 1)
      assert_span_correlation(captured[0], s)
    }
    None => abort("expected span")
  }
}

///|
test "explicit span correlation field collisions use canonical span values" {
  let captured : Array[@moontrace.Event] = []
  let span = @moontrace.span("collision")

  @moontrace.with_trace_state(fn() {
    @moontrace.set_subscriber(fn(event) { captured.push(event) })
    @moontrace.info_in_span(
      span,
      "collision",
      fields=@moontrace.fields([
        ("trace_id", "explicit-trace".to_json()),
        ("span_id", "explicit-span".to_json()),
        ("parent_span_id", "explicit-parent".to_json()),
        ("keep", "explicit".to_json()),
      ]),
    )
  })

  assert_eq(captured.length(), 1)
  assert_eq(span_event_field_count(captured[0], "trace_id"), 1)
  assert_eq(span_event_field_count(captured[0], "span_id"), 1)
  assert_eq(span_event_field_count(captured[0], "parent_span_id"), 1)
  assert_span_correlation(captured[0], span)
  assert_span_event_field(captured[0], "keep", "explicit".to_json())
}

///|
async test "plain events do not inherit span context across async yield" {
  let captured : Array[@moontrace.Event] = []
  let span = @moontrace.span("async")

  @moontrace.set_min_level(@moontrace.Info)
  @moontrace.set_subscriber(fn(event) { captured.push(event) })
  span.enter()
  @async.sleep(0)
  @moontrace.info("plain after yield")
  span.info("explicit after yield")
  span.exit()
  @moontrace.set_min_level(@moontrace.Trace)
  @moontrace.clear_subscriber()

  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "plain after yield")
  assert_no_span_event_field(captured[0], "trace_id")
  assert_no_span_event_field(captured[0], "span_id")
  assert_no_span_event_field(captured[0], "parent_span_id")
  assert_eq(captured[1].message, "explicit after yield")
  assert_span_correlation(captured[1], span)
}
