///|
fn record_raised(s : Span, throw_error : () -> Unit raise) -> Unit {
  throw_error() catch {
    error => s.record_exception(error)
  }
}

///|
// The catch observes the error; defer owns cleanup, as in span_async.
#warnings("-fragile_catch_all")
fn[T] run_in_span(s : Span, f : (Span) -> T raise?) -> T raise? {
  s.enter()
  defer s.exit()
  f(s) catch {
    err => {
      // Widen the polymorphic error through a typed raise for recording,
      // then rethrow the original below to preserve the callback error type.
      record_raised(s, fn() raise { raise err })
      raise err
    }
  }
}

///|
/// Run the callback in a span, closing it on return or raised error.
/// Raised errors are recorded before closing and propagated unchanged.
/// `level` behaves as for `span`.
#callsite(autofill(loc))
pub fn[T] with_span(
  name : String,
  fields~ : Array[Field] = [],
  level? : Level,
  loc~ : SourceLoc,
  f : () -> T raise?,
) -> T raise? {
  run_in_span(span(name, fields~, level?, loc~), _s => f())
}

///|
/// Pass a new span to the callback and close it on return or raised error.
/// Raised errors are recorded before closing and propagated unchanged.
/// `level` behaves as for `span`.
#callsite(autofill(loc))
pub fn[T] with_span_ctx(
  name : String,
  fields~ : Array[Field] = [],
  level? : Level,
  loc~ : SourceLoc,
  f : (Span) -> T raise?,
) -> T raise? {
  run_in_span(span(name, fields~, level?, loc~), f)
}

///|
/// Pass a child span to the callback and close it on return or raised error.
/// Raised errors are recorded before closing and propagated unchanged.
/// `level` behaves as for `child_span`.
#callsite(autofill(loc))
pub fn[T] with_child_span(
  parent : Span,
  name : String,
  fields~ : Array[Field] = [],
  level? : Level,
  loc~ : SourceLoc,
  f : (Span) -> T raise?,
) -> T raise? {
  run_in_span(child_span(parent, name, fields~, level?, loc~), f)
}
