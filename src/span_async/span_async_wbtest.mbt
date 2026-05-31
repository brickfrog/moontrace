///|
suberror AsyncSpanTestErr derive(Debug)

///|
fn span_has_field(span : @moontrace.Span, key : String) -> Bool {
  let mut found = false
  span.fields.each(field => if field.key == key { found = true })
  found
}

///|
async test "with_span_async exits on normal return" {
  let mut captured : @moontrace.Span? = None
  let result = with_span_async("async_return", span => {
    captured = Some(span)
    assert_eq(span.is_active(), true)
    @async.pause()
    42
  })
  let span = captured.unwrap()

  assert_eq(result, 42)
  assert_eq(span.name, "async_return")
  assert_eq(span.active, false)
  assert_eq(span.status, @moontrace.Unset)
}

///|
async test "with_child_span_async propagates trace id and parent id" {
  let mut parent_trace_id = ""
  let mut parent_span_id = ""
  let mut child_trace_id = ""
  let mut child_parent_id = ""
  let mut child_span_id = ""
  with_span_async("async_parent", parent => {
    parent_trace_id = parent.trace_id
    parent_span_id = parent.span_id
    with_child_span_async(parent, "async_child", child => {
      @async.sleep(1)
      child_trace_id = child.trace_id
      child_parent_id = child.parent_span_id
      child_span_id = child.span_id
    })
  })

  assert_eq(parent_trace_id, child_trace_id)
  assert_eq(child_parent_id, parent_span_id)
  assert_true(!child_span_id.is_empty())
}

///|
async test "with_span_async exits and records errors" {
  let mut captured : @moontrace.Span? = None
  let mut saw_error = false
  with_span_async("async_error", _span => {
    captured = Some(_span)
    @async.pause()
    raise AsyncSpanTestErr
  }) catch {
    AsyncSpanTestErr => saw_error = true
    err => raise err
  }
  let span = captured.unwrap()

  assert_eq(saw_error, true)
  assert_eq(span.name, "async_error")
  assert_eq(span.active, false)
  assert_eq(span.status, @moontrace.SpanError)
  assert_true(span_has_field(span, "error"))
}

///|
async test "with_child_span_async exits on structured cancellation" {
  let parent = @moontrace.span("cancel_parent")
  let mut captured : @moontrace.Span? = None

  @async.with_task_group(root => {
    let task = root.spawn(() => {
      with_child_span_async(parent, "cancelled_child", span => {
        captured = Some(span)
        @async.sleep(1000)
      })
    })
    @async.pause()
    task.cancel()
    task.wait() catch {
      _err => ()
    }
  })
  let span = captured.unwrap()

  assert_eq(span.name, "cancelled_child")
  assert_eq(span.active, false)
  assert_eq(span.status, @moontrace.SpanError)
  assert_true(span.status_message.contains("Cancelled"))
  assert_true(span_has_field(span, "error"))
}
