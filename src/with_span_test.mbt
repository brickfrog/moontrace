///|
test "with_span enters and exits" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.with_span("work", fn() { @moontrace.info("inside") })
  // Should have: span.enter, info event, span.exit = 3 events
  assert_eq(captured.length(), 3)
  assert_eq(captured[0].message, "span.enter work")
  assert_eq(captured[1].message, "inside")
  assert_eq(captured[2].message, "span.exit work")
  @moontrace.clear_subscriber()
}

///|
test "with_span returns closure result" {
  let result = @moontrace.with_span("calc", fn() { 42 })
  assert_eq(result, 42)
  @moontrace.clear_subscriber()
}

///|
test "with_span passes fields to span" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.with_span("op", fields=@moontrace.fields([("key", Json("val"))]), fn() {

  })
  // Just verify enter event has the field
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "span.enter op")
  let found = {
    let mut result = false
    captured[0].fields.each(fn(f) { if f.key == "key" { result = true } })
    result
  }
  assert_eq(found, true)
  @moontrace.clear_subscriber()
}

///|
test "with_span_ctx passes span to closure" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.with_span_ctx("ctx", fn(s) { s.record("added", "during") })
  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "span.enter ctx")
  @moontrace.clear_subscriber()
}

///|
test "with_span_ctx returns closure result" {
  let result = @moontrace.with_span_ctx("calc", fn(_s) { 99 })
  assert_eq(result, 99)
  @moontrace.clear_subscriber()
}

///|
test "with_child_span links parent" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.with_span_ctx("parent", fn(parent) {
    @moontrace.with_child_span(parent, "child", fn(_s) {  })
  })
  // Events: parent.enter, child.enter, child.exit, parent.exit
  assert_eq(captured.length(), 4)
  assert_eq(captured[1].message, "span.enter child")
  @moontrace.clear_subscriber()
}

///|
test "with_child_span propagates trace_id" {
  let mut parent_trace = ""
  let mut child_trace = ""
  let mut child_parent_id = ""
  let mut parent_span = ""
  @moontrace.with_span_ctx("parent", fn(p) {
    parent_trace = p.trace_id
    parent_span = p.span_id
    @moontrace.with_child_span(p, "child", fn(c) {
      child_trace = c.trace_id
      child_parent_id = c.parent_span_id
    })
  })
  assert_eq(parent_trace, child_trace)
  assert_eq(child_parent_id, parent_span)
  @moontrace.clear_subscriber()
}

///|
suberror SyncSpanFailure {
  SyncSpanFailure(Int32)
} derive(Debug)

///|
fn check_sync_span_failure(
  run : (() -> Unit raise) -> Unit raise,
) -> Unit raise {
  @moontrace.with_trace_state(() => {
    let lifecycle : Array[String] = []
    let closed : Array[@moontrace.Span] = []
    let events : Array[@moontrace.Event] = []
    @moontrace.set_min_level(@moontrace.Trace)
    @moontrace.set_subscriber(e => events.push(e))
    @moontrace.set_span_observer(
      @moontrace.span_lifecycle_observer(
        on_entered=s => lifecycle.push("entered:" + s.name),
        on_recorded=fn(s, field) {
          lifecycle.push("recorded:" + s.name + ":" + field.key)
        },
        on_exited=s => lifecycle.push("exited:" + s.name),
        on_closed=s => {
          lifecycle.push("closed:" + s.name)
          closed.push(s)
        },
      ),
    )
    let mut caught = false
    run(fn() raise { raise SyncSpanFailure(73) }) catch {
      SyncSpanFailure(code) => {
        assert_eq(code, 73)
        caught = true
      }
      err => raise err
    }
    assert_true(caught)
    assert_eq(lifecycle, [
      "entered:failure", "recorded:failure:error", "exited:failure", "closed:failure",
    ])
    assert_eq(closed.length(), 1)
    let span = closed[0]
    assert_false(span.active)
    assert_eq(span.status, @moontrace.SpanError)
    let error : Error = SyncSpanFailure(73)
    assert_eq(span.status_message, "\{error}")
    assert_true(
      span.fields.any(f => {
        f.key == "error" && f.value == Json(span.status_message)
      }),
    )
    assert_eq(events.filter(e => e.message == "span.exit failure").length(), 1)
  })
}

///|
test "with_span records and propagates raised callback error" {
  check_sync_span_failure(f => @moontrace.with_span("failure", f))
}

///|
test "with_span_ctx records and propagates raised callback error" {
  check_sync_span_failure(f => @moontrace.with_span_ctx("failure", _s => f()))
}

///|
test "with_child_span records and propagates raised callback error" {
  let parent = @moontrace.span("parent")
  check_sync_span_failure(f => {
    @moontrace.with_child_span(parent, "failure", _s => f())
  })
}

///|
test "nested synchronous failures close child before parent once" {
  @moontrace.with_trace_state(() => {
    let closed : Array[@moontrace.Span] = []
    @moontrace.set_span_observer(
      @moontrace.completed_span_observer(s => closed.push(s)),
    )
    @moontrace.with_span_ctx("parent", parent => {
      @moontrace.with_child_span(parent, "child", _child => {
        raise SyncSpanFailure(91)
      })
    }) catch {
      SyncSpanFailure(code) => assert_eq(code, 91)
    }
    assert_eq(closed.length(), 2)
    assert_eq(closed[0].name, "child")
    assert_eq(closed[1].name, "parent")
    assert_eq(closed[0].parent_span_id, closed[1].span_id)
    assert_eq(closed[0].trace_id, closed[1].trace_id)
    for span in closed {
      assert_false(span.active)
      assert_eq(span.status, @moontrace.SpanError)
    }
  })
}

///|
test "synchronous wrappers close once on success including explicit exit" {
  @moontrace.with_trace_state(() => {
    let closed : Array[@moontrace.Span] = []
    @moontrace.set_span_observer(
      @moontrace.completed_span_observer(s => closed.push(s)),
    )
    assert_eq(@moontrace.with_span("plain", () => 42), 42)
    let result = @moontrace.with_span_ctx("parent", parent => {
      @moontrace.with_child_span(parent, "child", child => {
        child.exit()
        99
      })
    })
    assert_eq(result, 99)
    assert_eq(closed.map(s => s.name), ["plain", "child", "parent"])
    for span in closed {
      assert_false(span.active)
      assert_eq(span.status, @moontrace.Unset)
    }
  })
}
