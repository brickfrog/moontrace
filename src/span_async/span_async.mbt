///|
fn error_message(err : Error) -> String {
  if @async.is_cancellation_error(err) {
    "Cancelled"
  } else {
    "\{err}"
  }
}

///|
/// Run an async closure inside a new span.
///
/// The span is exited by `defer`, so it is exited on normal return, on a raised
/// error, and on async cancellation. The error message is recorded by a
/// catch-all handler, which is the only construct that can observe the error
/// value: `errdefer` runs no matter the error but binds nothing.
///
/// This is best-effort structured cancellation instrumentation. It is not a
/// Rust Drop-guard equivalent, and out-of-band abort/kill paths are out of
/// scope. If a future compiler stops routing cancellation through `catch`, the
/// span is still exited but the cancellation message is no longer recorded.
pub async fn[T] with_span_async(
  name : String,
  fields~ : Array[@moontrace.Field] = [],
  f : async (@moontrace.Span) -> T,
) -> T {
  run_in_span_async(@moontrace.span(name, fields~), f)
}

///|
/// Run an async closure inside a child span with an explicit parent span.
///
/// The child span inherits the parent's trace_id, records parent_span_id, and
/// emits the core CHILD_OF span link. The span is exited by `defer`, so it is
/// exited on normal return, on a raised error, and on async cancellation.
///
/// This is best-effort structured cancellation instrumentation. It is not a
/// Rust Drop-guard equivalent, and out-of-band abort/kill paths are out of
/// scope. If a future compiler stops routing cancellation through `catch`, the
/// span is still exited but the cancellation message is no longer recorded.
pub async fn[T] with_child_span_async(
  parent : @moontrace.Span,
  name : String,
  fields~ : Array[@moontrace.Field] = [],
  f : async (@moontrace.Span) -> T,
) -> T {
  run_in_span_async(@moontrace.child_span(parent, name, fields~), f)
}

///|
// Catch observes the original error; defer owns cleanup for all async helpers.
#warnings("-fragile_catch_all")
async fn[T] run_in_span_async(
  s : @moontrace.Span,
  f : async (@moontrace.Span) -> T,
) -> T {
  s.enter()
  defer s.exit()
  f(s) catch {
    err => {
      s.record_error(error_message(err))
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
pub async fn[T] with_remote_span_async(
  context : @moontrace.SpanContext,
  name : String,
  fields~ : Array[@moontrace.Field] = [],
  kind~ : @moontrace.SpanKind = @moontrace.Server,
  f : async (@moontrace.Span) -> T,
) -> T {
  run_in_span_async(
    @moontrace.span_from_remote_context(context, name, fields~, kind~),
    f,
  )
}
