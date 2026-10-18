///|
fn logger_value(event : Event, key : String) -> Json? raise {
  let found = event.fields.filter(f => f.key == key)
  assert_true(found.length() <= 1)
  found.get(0).map(f => f.value)
}

///|
test "logger binding isolates parents children input and emitted JSON" {
  with_trace_state(() => {
    let events : Array[Event] = []
    set_subscriber(e => events.push(e))
    set_min_level(Trace)
    clear_module_filters()
    clear_global_fields()
    let values : Array[Json] = [Json("original")]
    let object : Map[String, Json] = { "items": Json(values) }
    let input = [field("request_id", "parent"), field("nested", object)]
    let parent = logger(fields=input)
    let child_input = [
      field("request_id", "first"),
      field("request_id", "child"),
    ]
    let child = parent.bind(child_input)
    input.clear()
    child_input.clear()
    values[0] = Json("changed")
    object.set("other", Json(true))
    parent.info("parent")
    child.info("child")
    assert_eq(logger_value(events[0], "request_id"), Some(Json("parent")))
    assert_eq(logger_value(events[1], "request_id"), Some(Json("child")))
    assert_eq(
      logger_value(events[0], "nested"),
      Some(Json({ "items": ["original"] })),
    )
    match logger_value(events[0], "nested") {
      Some(Object(obj)) => obj.set("items", Json("subscriber mutation"))
      _ => abort("missing object")
    }
    events[1].fields.clear()
    parent.info("parent again")
    child.info("child again")
    assert_eq(
      logger_value(events[2], "nested"),
      Some(Json({ "items": ["original"] })),
    )
    assert_eq(logger_value(events[3], "request_id"), Some(Json("child")))
  })
}

///|
test "logger precedence is global parent child event with unique keys" {
  with_trace_state(() => {
    clear_global_fields()
    clear_module_filters()
    set_min_level(Trace)
    let events : Array[Event] = []
    set_subscriber(e => events.push(e))
    set_global_field("key", "global")
    set_global_field("global_only", true)
    let parent = logger(fields=[field("key", "old"), field("key", "parent")])
    let child = parent.bind([field("key", "child")])
    child.info("event", fields=[
      field("key", "old event"),
      field("key", "event"),
    ])
    child.info("child")
    parent.info("parent")
    logger().info("global")
    for i, expected in ["event", "child", "parent", "global"] {
      assert_eq(logger_value(events[i], "key"), Some(Json(expected)))
      assert_eq(logger_value(events[i], "global_only"), Some(Json(true)))
    }
  })
}

///|
test "logger spans override spoofed IDs without inheriting span fields or lifetime" {
  with_trace_state(() => {
    clear_global_fields()
    clear_module_filters()
    set_min_level(Trace)
    let events : Array[Event] = []
    set_subscriber(e => events.push(e))
    let root = span("root")
    let child = child_span(root, "child", fields=[field("span_only", true)])
    let plain = logger(fields=[
      field("request_id", "r"),
      field("trace_id", "fake"),
    ])
    let bound = plain.in_span(child).bind([field("span_id", "fake")])
    set_global_field("parent_span_id", "fake")
    bound.info("correlated", fields=[
      field("trace_id", "fake event"),
      field("parent_span_id", "fake event"),
    ])
    logger(span=root).info("root")
    plain.info("plain")
    assert_eq(logger_value(events[0], "trace_id"), Some(Json(root.trace_id)))
    assert_eq(logger_value(events[0], "span_id"), Some(Json(child.span_id)))
    assert_eq(
      logger_value(events[0], "parent_span_id"),
      Some(Json(root.span_id)),
    )
    assert_eq(logger_value(events[0], "span_only"), None)
    assert_eq(logger_value(events[1], "span_id"), Some(Json(root.span_id)))
    assert_eq(logger_value(events[2], "trace_id"), Some(Json("fake")))
    assert_eq(logger_value(events[2], "span_id"), None)
    assert_false(root.active)
    assert_false(child.active)
    assert_eq(child.end_time, 0)
  })
}

///|
test "logger uses current subscriber filters redaction and caller metadata" {
  with_trace_state(() => {
    clear_global_fields()
    clear_module_filters()
    let events : Array[Event] = []
    let log = logger(fields=[field("password", "secret")])
    set_subscriber(redact(e => events.push(e)))
    set_min_level(Error_)
    set_module_filter("brickfrog/moontrace", Debug)
    log.trace("hidden")
    log.debug("debug")
    log.info("info")
    log.warn("warn")
    log.error("error")
    log.event(Debug, "event")
    assert_eq(events.map(e => e.level), [Debug, Info, Warn, Error_, Debug])
    for event in events {
      assert_eq(event.source, "brickfrog/moontrace")
      assert_eq(logger_value(event, "password"), Some(Json("[REDACTED]")))
      assert_true(event.timestamp > 0)
    }
    set_module_filter("brickfrog/moontrace", Error_)
    log.in_span(span("filtered")).info("hidden span")
    assert_eq(events.length(), 5)
    clear_subscriber()
    log.error("no subscriber")
    assert_eq(events.length(), 5)
    set_subscriber(e => events.push(e))
    log.error("replacement")
    assert_eq(logger_value(events[5], "password"), Some(Json("secret")))
  })
}

///|
async test "explicit loggers remain isolated through interleaved async tasks" {
  let saved = snapshot_trace_state()
  defer restore_trace_state(saved)
  clear_global_fields()
  clear_module_filters()
  set_min_level(Info)
  let events : Array[Event] = []
  set_subscriber(e => events.push(e))
  let first_span = span("first")
  let second_span = span("second")
  let shared = logger(fields=[field("service", "api")])
  let first = shared.bind([field("request_id", "first")]).in_span(first_span)
  let second = shared.bind([field("request_id", "second")]).in_span(second_span)
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      first.info("first before")
      @async.pause()
      first.bind([field("phase", "after")]).info("first after")
    })
    second.info("second before")
    @async.pause()
    second.info("second after")
    task.wait()
  })
  info("unbound")
  assert_eq(events.length(), 5)
  for event in events[:4] {
    let is_first = event.message.has_prefix("first")
    assert_eq(
      logger_value(event, "request_id"),
      Some(Json(if is_first { "first" } else { "second" })),
    )
    assert_eq(
      logger_value(event, "span_id"),
      Some(
        Json(if is_first { first_span.span_id } else { second_span.span_id }),
      ),
    )
  }
  assert_eq(logger_value(events[4], "request_id"), None)
  assert_eq(logger_value(events[4], "span_id"), None)
}

///|
test "logger event overrides are snapshots and do not stick" {
  with_trace_state(() => {
    clear_global_fields()
    clear_module_filters()
    set_min_level(Trace)
    let seen : Array[Event] = []
    set_subscriber(e => seen.push(e))
    let log = logger(fields=[field("key", "bound")])
    let values : Array[Json] = [Json("event")]
    let fields = [field("key", values)]
    log.info("override", fields~)
    values[0] = Json("changed")
    fields.clear()
    log.info("next")
    assert_eq(logger_value(seen[0], "key"), Some(Json(["event"])))
    assert_eq(logger_value(seen[1], "key"), Some(Json("bound")))
  })
}

///|
test "subscriber nested array mutation cannot alter subsequent bound events" {
  with_trace_state(() => {
    clear_global_fields()
    clear_module_filters()
    set_min_level(Info)
    let log = logger(fields=[
      field("nested", Json({ "items": [{ "value": "original" }] })),
    ])
    let seen : Array[Event] = []
    set_subscriber(e => {
      seen.push(e)
      for field in e.fields {
        match field.value {
          Object(obj) =>
            match obj.get("items") {
              Some(Array(items)) => items[0] = Json("mutated by subscriber")
              _ => ()
            }
          _ => ()
        }
      }
    })
    log.info("first")
    set_subscriber(e => seen.push(e))
    log.info("second")
    assert_eq(
      logger_value(seen[1], "nested"),
      Some(Json({ "items": [{ "value": "original" }] })),
    )
  })
}

///|
test "logger redaction follows global merging and span correlation" {
  with_trace_state(() => {
    clear_global_fields()
    clear_module_filters()
    set_min_level(Info)
    let seen : Array[Event] = []
    let root = span("request")
    let log = logger(
      fields=[field("trace_id", "spoof"), field("password", "bound")],
      span=root,
    )
    set_global_field("global_secret", "old")
    set_subscriber(
      redact(
        e => seen.push(e),
        policy=redaction_policy(deny=["secret", "password", "trace_id"]),
      ),
    )
    set_global_field("global_secret", "new")
    log.info("redacted", fields=[field("password", "event")])
    assert_eq(logger_value(seen[0], "trace_id"), Some(Json("[REDACTED]")))
    assert_eq(logger_value(seen[0], "password"), Some(Json("[REDACTED]")))
    assert_eq(logger_value(seen[0], "global_secret"), Some(Json("[REDACTED]")))
    set_subscriber(e => seen.push(e))
    log.info("plain")
    assert_eq(logger_value(seen[1], "trace_id"), Some(Json(root.trace_id)))
    assert_eq(logger_value(seen[1], "password"), Some(Json("bound")))
    assert_eq(logger_value(seen[1], "global_secret"), Some(Json("new")))
  })
}
