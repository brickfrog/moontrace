///|
/// A timestamped annotation recorded on a span, exported as an OTLP span event.
pub(all) struct SpanEvent {
  name : String
  timestamp : UInt64
  fields : Array[Field]
} derive(Debug)

///|
/// Record a named event on the span, such as a retry or cache miss. Events are
/// kept with the span and exported with it; they are not emitted as log events.
/// Events added after the span has exited are ignored.
pub fn Span::add_event(
  self : Span,
  name : String,
  fields~ : Array[Field] = [],
) -> Unit {
  if self.is_closed() {
    return
  }
  self.events.push({ name, timestamp: @env.now(), fields: fields.copy(), })
}

///|
/// Derive an exception type name from an error's display string: the leading
/// identifier when the string starts with one (`Failure(boom)` -> `Failure`,
/// `pkg.MyError.Case` -> itself), otherwise `Error`. MoonBit has no runtime
/// type names, so pass `type_name` where a precise name matters.
fn exception_type_name(display : String) -> String {
  let mut end = 0
  for i in 0..<display.length() {
    let c = display.code_unit_at(i).to_int()
    let is_start = (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
      (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
      c == '_'.to_int()
    let is_part = is_start ||
      (c >= '0'.to_int() && c <= '9'.to_int()) ||
      c == '.'.to_int() ||
      c == '/'.to_int()
    if (i == 0 && !is_start) || !is_part {
      break
    }
    end = i + 1
  }
  if end > 0 && (end == display.length() || display.code_unit_at(end) == '(') {
    display[:end].to_owned()
  } else {
    "Error"
  }
}

///|
/// OpenTelemetry `exception.type` and `exception.message` fields for an error,
/// for use on log events. See `Span::record_exception` for spans.
pub fn exception_fields(err : Error, type_name? : String) -> Array[Field] {
  let message = "\{err}"
  let exception_type = match type_name {
    Some(name) => name
    None => exception_type_name(message)
  }
  [
    { key: "exception.type", value: Json(exception_type), },
    { key: "exception.message", value: Json(message), },
  ]
}

///|
/// Record a raised error: sets error status and the `error` field like
/// `record_error`, then adds an `exception` span event with OpenTelemetry
/// `exception.type` and `exception.message` attributes plus any extra fields.
pub fn Span::record_exception(
  self : Span,
  err : Error,
  type_name? : String,
  fields~ : Array[Field] = [],
) -> Unit {
  let attributes = exception_fields(err, type_name?)
  match attributes[1].value {
    String(message) => self.record_error(message)
    _ => ()
  }
  for field in fields {
    attributes.push(field)
  }
  self.add_event("exception", fields=attributes)
}
