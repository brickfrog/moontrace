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
/// The span is entered before the closure runs and exited when the closure
/// returns or raises. Cancellation delivered through MoonBit async error/catch
/// paths is treated like any other raised error: the span records SpanError
/// before exit and the original error is re-raised.
///
/// This is best-effort structured cancellation instrumentation. It is not a
/// Rust Drop-guard equivalent, and out-of-band abort/kill paths are out of
/// scope.
pub async fn[T] with_span_async(
  name : String,
  fields? : Array[@moontrace.Field] = [],
  f : async (@moontrace.Span) -> T,
) -> T {
  let s = @moontrace.span(name, fields~)
  s.enter()
  try f(s) catch {
    err => {
      s.record_error(error_message(err))
      s.exit()
      raise err
    }
  } noraise {
    result => {
      s.exit()
      result
    }
  }
}

///|
/// Run an async closure inside a child span with an explicit parent span.
///
/// The child span inherits the parent's trace_id, records parent_span_id, and
/// emits the core CHILD_OF span link. The span is exited on normal return and
/// on raised errors, including structured async cancellation delivered through
/// MoonBit async error/catch paths.
///
/// This is best-effort structured cancellation instrumentation. It is not a
/// Rust Drop-guard equivalent, and out-of-band abort/kill paths are out of
/// scope.
pub async fn[T] with_child_span_async(
  parent : @moontrace.Span,
  name : String,
  fields? : Array[@moontrace.Field] = [],
  f : async (@moontrace.Span) -> T,
) -> T {
  let s = @moontrace.child_span(parent, name, fields~)
  s.enter()
  try f(s) catch {
    err => {
      s.record_error(error_message(err))
      s.exit()
      raise err
    }
  } noraise {
    result => {
      s.exit()
      result
    }
  }
}
