///|
suberror ExceptionTestError {
  Broken(Int32)
}

///|
impl Show for ExceptionTestError with fn output(self, logger) {
  match self {
    Broken(code) => logger.write_string("Broken(\{code})")
  }
}

///|
suberror QuietError

///|
suberror ProseError

///|
impl Show for ProseError with fn output(_, logger) {
  logger.write_string("disk is full")
}

///|
fn exception_event_value(event : @moontrace.SpanEvent, key : String) -> Json? {
  event.fields.filter(f => f.key == key).get(0).map(f => f.value)
}

///|
test "add_event records events and ignores them after exit" {
  let span = @moontrace.span("work")
  let fields = [@moontrace.field("attempt", 1)]
  span.enter()
  span.add_event("retry", fields~)
  fields.clear()
  span.exit()
  span.add_event("late")
  assert_eq(span.events.map(e => e.name), ["retry"])
  assert_eq(span.events[0].fields.length(), 1)
}

///|
test "completed span snapshots include events" {
  let completed : Array[@moontrace.Span] = []
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_observer(
      @moontrace.completed_span_observer(s => completed.push(s)),
    )
    let span = @moontrace.span("work")
    span.enter()
    span.add_event("checkpoint")
    span.exit()
  })
  assert_eq(completed[0].events.map(e => e.name), ["checkpoint"])
}

///|
test "record_exception sets status and adds an exception event" {
  let span = @moontrace.span("work")
  span.enter()
  span.record_exception(Broken(3), fields=[@moontrace.field("retryable", false)])
  span.exit()
  assert_eq(span.status, @moontrace.SpanError)
  assert_eq(span.status_message, "Broken(3)")
  assert_true(span.fields.iter().any(f => f.key == "error"))
  let event = span.events[0]
  assert_eq(event.name, "exception")
  assert_eq(
    exception_event_value(event, "exception.type"),
    Some(Json("Broken")),
  )
  assert_eq(
    exception_event_value(event, "exception.message"),
    Some(Json("Broken(3)")),
  )
  assert_eq(exception_event_value(event, "retryable"), Some(Json(false)))
}

///|
test "exception_fields derives or accepts the type name" {
  let fields = @moontrace.exception_fields(Failure("boom"))
  assert_eq(fields.map(f => f.key), ["exception.type", "exception.message"])
  assert_eq(fields.map(f => f.value), [Json("Failure"), Json("Failure(boom)")])

  let quiet = @moontrace.exception_fields(QuietError)
  assert_eq(quiet[0].value, quiet[1].value)

  let prose = @moontrace.exception_fields(ProseError)
  assert_eq(prose.map(f => f.value), [Json("Error"), Json("disk is full")])

  let named = @moontrace.exception_fields(ProseError, type_name="DiskFull")
  assert_eq(named[0].value, Json("DiskFull"))
}

///|
fn raises_in_span() -> Bool {
  @moontrace.with_span("op", fn() -> Unit raise ExceptionTestError {
    raise Broken(7)
  }) catch {
    _ => return true
  }
  false
}

///|
test "with_span records raised errors as exception events" {
  let completed : Array[@moontrace.Span] = []
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_observer(
      @moontrace.completed_span_observer(s => completed.push(s)),
    )
    assert_true(raises_in_span())
  })
  assert_eq(completed[0].status_message, "Broken(7)")
  assert_eq(completed[0].events.map(e => e.name), ["exception"])
}

///|
test "span JSON includes events only when present" {
  let span = @moontrace.span("work")
  assert_true(!span.to_json().stringify().contains("\"events\""))
  span.add_event("cache_miss", fields=[@moontrace.field("key", "k")])
  let json = span.to_json().stringify()
  assert_true(json.contains("\"events\":[{\"name\":\"cache_miss\""))
  assert_true(json.contains("\"key\":\"k\""))
}

///|
test "completed span snapshots deep-copy field and event JSON" {
  let completed : Array[@moontrace.Span] = []
  let nested : Map[String, Json] = Map([("k", Json("original"))])
  let span = @moontrace.span("work", fields=[@moontrace.field("attr", nested)])
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_observer(
      @moontrace.completed_span_observer(s => completed.push(s)),
    )
    span.enter()
    span.add_event("e", fields=[@moontrace.field("payload", nested)])
    span.exit()
  })
  nested.set("k", Json("changed"))
  match span.events[0].fields[0].value {
    Object(obj) => obj.set("k", Json("mutated"))
    _ => abort("expected object")
  }
  let expected = Json(Map([("k", Json("original"))]))
  assert_eq(completed[0].fields[0].value, expected)
  assert_eq(completed[0].events[0].fields[0].value, expected)
}
