///|
/// Run an async closure inside a new span.
///
/// The span exits on return, error, or cancellation. Raised errors are recorded
/// as exceptions. Cancellation records the error status with message `Cancelled`.
/// `level` behaves as for `@moontrace.span`.
#callsite(autofill(loc))
pub async fn[T] with_span_async(
  name : String,
  fields~ : Array[@moontrace.Field] = [],
  level? : @moontrace.Level,
  loc~ : SourceLoc,
  f : async (@moontrace.Span) -> T,
) -> T {
  run_in_span_async(@moontrace.span(name, fields~, level?, loc~), f)
}

///|
/// Run an async closure inside a child span with an explicit parent span.
///
/// The child span inherits the parent's trace_id, records parent_span_id, and
/// emits the core CHILD_OF span link. Errors and cancellation are recorded
/// as in `with_span_async`.
/// `level` behaves as for `@moontrace.span`.
#callsite(autofill(loc))
pub async fn[T] with_child_span_async(
  parent : @moontrace.Span,
  name : String,
  fields~ : Array[@moontrace.Field] = [],
  level? : @moontrace.Level,
  loc~ : SourceLoc,
  f : async (@moontrace.Span) -> T,
) -> T {
  run_in_span_async(
    @moontrace.child_span(parent, name, fields~, level?, loc~),
    f,
  )
}

///|
async fn[T] run_in_span_async(
  s : @moontrace.Span,
  f : async (@moontrace.Span) -> T,
) -> T {
  s.enter()
  defer s.exit()
  let outcome = {
    // Ordinary errors become Err here, so only cancellation unwinds this block.
    errdefer s.record_error("Cancelled")
    Ok(f(s)) catch {
      err => Err(err)
    }
  }
  match outcome {
    Ok(value) => value
    Err(err) => {
      s.record_exception(err)
      raise err
    }
  }
}

///|
/// Run request work in a new local span parented by incoming trace context.
/// Defaults to Server; preserves trace ID, sampled flags, and tracestate through
/// span_from_remote_context. Headers must already be parsed by the caller.
/// Enters before f, records raised errors/cancellation, and always exits on return
/// or raise. Propagates the original result/error; installs no task-local context.
#callsite(autofill(loc))
pub async fn[T] with_remote_span_async(
  context : @moontrace.SpanContext,
  name : String,
  fields~ : Array[@moontrace.Field] = [],
  kind~ : @moontrace.SpanKind = @moontrace.Server,
  level? : @moontrace.Level,
  loc~ : SourceLoc,
  f : async (@moontrace.Span) -> T,
) -> T {
  run_in_span_async(
    @moontrace.span_from_remote_context(
      context,
      name,
      fields~,
      kind~,
      level?,
      loc~,
    ),
    f,
  )
}
