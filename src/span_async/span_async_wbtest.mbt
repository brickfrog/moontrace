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

///|
fn incoming_request_context() -> @moontrace.SpanContext {
  match
    @moontrace.parse_span_context(
      "00-11111111111111111111111111111111-2222222222222222-01",
      tracestate="vendor=fixture",
    ) {
    Ok(context) => context
    Err(error) => abort(error.to_string())
  }
}

///|
async test "remote async span preserves incoming propagation and returns callback result" {
  let context = incoming_request_context()
  let captured : Ref[@moontrace.Span?] = Ref(None)
  let result = with_remote_span_async(
    context,
    "request",
    fields=[@moontrace.field("request_id", "fixture")],
    server => {
      captured.val = Some(server)
      assert_true(server.active)
      assert_eq(server.kind, @moontrace.Server)
      assert_eq(server.trace_id, context.trace_id.to_string())
      assert_eq(server.parent_span_id, context.span_id.to_string())
      assert_true(server.span_id != server.parent_span_id)
      assert_eq(
        @moontrace.span_trace_state(server).to_header(),
        "vendor=fixture",
      )
      assert_true(@moontrace.span_trace_flags(server).is_sampled())
      assert_true(span_has_field(server, "request_id"))
      with_child_span_async(server, "child", child => {
        @async.pause()
        assert_eq(child.parent_span_id, server.span_id)
        assert_eq(child.trace_id, server.trace_id)
        assert_eq(
          @moontrace.span_trace_state(child).to_header(),
          "vendor=fixture",
        )
        42
      })
    },
  )
  assert_eq(result, 42)
  let server = captured.val.unwrap()
  assert_false(server.active)
  assert_true(server.end_time >= server.start_time)
  assert_eq(server.status, @moontrace.Unset)
}

///|
suberror RemoteSpanError {
  RemoteSpanError(Int32)
} derive(Debug)

///|
async test "remote async span records failure while preserving the original typed error" {
  let captured : Ref[@moontrace.Span?] = Ref(None)
  let saw_error = Ref(false)
  with_remote_span_async(
    incoming_request_context(),
    "failed request",
    kind=@moontrace.Consumer,
    server => {
      captured.val = Some(server)
      assert_eq(server.kind, @moontrace.Consumer)
      @async.pause()
      raise RemoteSpanError(73)
    },
  ) catch {
    RemoteSpanError(code) => {
      assert_eq(code, 73)
      saw_error.val = true
    }
    error => raise error
  }
  assert_true(saw_error.val)
  let server = captured.val.unwrap()
  assert_false(server.active)
  assert_eq(server.status, @moontrace.SpanError)
  assert_true(server.status_message.contains("RemoteSpanError"))
  assert_true(span_has_field(server, "error"))
}

///|
async test "remote async span closes and records cancellation without changing remote context" {
  let context = incoming_request_context()
  let captured : Ref[@moontrace.Span?] = Ref(None)
  @async.with_task_group(group => {
    let task = group.spawn(() => {
      with_remote_span_async(context, "cancelled request", server => {
        captured.val = Some(server)
        @async.sleep(10000)
      })
    })
    @async.pause()
    task.cancel()
    let cancelled = Ref(false)
    task.wait() catch {
      error => cancelled.val = @async.is_cancellation_error(error)
    }
    assert_true(cancelled.val)
  })
  let server = captured.val.unwrap()
  assert_false(server.active)
  assert_eq(server.status, @moontrace.SpanError)
  assert_eq(server.status_message, "Cancelled")
  assert_eq(server.trace_id, context.trace_id.to_string())
  assert_eq(server.parent_span_id, context.span_id.to_string())
  assert_eq(context.trace_state.to_header(), "vendor=fixture")
}
