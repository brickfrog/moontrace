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
// The handler inspects `err` rather than cleaning up, so E0092 is a false
// positive here; the cleanup it asks for already moved to `defer` above.
#warnings("-fragile_catch_all")
pub async fn[T] with_span_async(
  name : String,
  fields? : Array[@moontrace.Field] = [],
  f : async (@moontrace.Span) -> T,
) -> T {
  let s = @moontrace.span(name, fields~)
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
// See `with_span_async`: E0092 is a false positive for an error-inspecting
// handler, and the cleanup it asks for already moved to `defer` below.
#warnings("-fragile_catch_all")
pub async fn[T] with_child_span_async(
  parent : @moontrace.Span,
  name : String,
  fields? : Array[@moontrace.Field] = [],
  f : async (@moontrace.Span) -> T,
) -> T {
  let s = @moontrace.child_span(parent, name, fields~)
  s.enter()
  defer s.exit()
  f(s) catch {
    err => {
      s.record_error(error_message(err))
      raise err
    }
  }
}
