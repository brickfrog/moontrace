///|
/// Explicit bound logging context. Pass it to work that needs the same fields;
/// it does not install global or task-local context or manage span lifetimes.
pub struct Logger {
  priv bound_fields : Array[Field]
  priv associated_span : Span?
}

///|
fn copy_logger_json(value : Json) -> Json {
  match value {
    Array(values) => Json(values.map(copy_logger_json))
    Object(values) => {
      let result : Map[String, Json] = Map([])
      values.each(fn(key, value) { result.set(key, copy_logger_json(value)) })
      Json(result)
    }
    _ => value
  }
}

///|
// Keep the first occurrence's position, but the last occurrence's value.
// Copy JSON containers as well as the field array to isolate bound state.
fn merge_logger_fields(
  base : Array[Field],
  overrides : Array[Field],
) -> Array[Field] {
  let result : Array[Field] = []
  let positions : Map[String, Int32] = Map([])
  for layer in [base, overrides] {
    for field in layer {
      let copied = Field::{
        key: field.key,
        value: copy_logger_json(field.value),
      }
      match positions.get(field.key) {
        Some(index) => result[index] = copied
        None => {
          positions.set(field.key, result.length())
          result.push(copied)
        }
      }
    }
  }
  result
}

///|
/// Bind a snapshot of fields, optionally associated with an existing span.
/// Duplicate keys use the last value. The span supplies correlation IDs only;
/// its fields and lifecycle are not inherited or changed.
pub fn logger(fields~ : Array[Field] = [], span? : Span) -> Logger {
  { bound_fields: merge_logger_fields([], fields), associated_span: span, }
}

///|
/// Derive an independent child logger. Child fields override parent fields;
/// the associated span is retained. Arrays and nested JSON are copied.
pub fn Logger::bind(self : Logger, fields : Array[Field]) -> Logger {
  {
    bound_fields: merge_logger_fields(self.bound_fields, fields),
    associated_span: self.associated_span,
  }
}

///|
/// Derive a logger associated with span, preserving the bound fields.
/// This does not enter or exit the span or change the original logger.
pub fn Logger::in_span(self : Logger, span : Span) -> Logger {
  {
    bound_fields: merge_logger_fields([], self.bound_fields),
    associated_span: Some(span),
  }
}

///|
/// Emit through the current filters and subscriber using the caller's package.
/// Precedence is global < bound < event fields (last duplicate wins).
/// An associated span's trace_id, span_id, and parent_span_id always win.
#callsite(autofill(loc))
pub fn Logger::event(
  self : Logger,
  level : Level,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  if !should_log_module(extract_package(loc), level) {
    return
  }
  let fields = merge_logger_fields(self.bound_fields, fields)
  match self.associated_span {
    Some(span) => emit_in_span_with_loc(span, level, msg, fields, loc)
    None => emit_with_loc(level, msg, fields, loc)
  }
}

///|
#callsite(autofill(loc))
pub fn Logger::trace(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Trace, msg, fields~, loc~)
}

///|
#callsite(autofill(loc))
pub fn Logger::debug(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Debug, msg, fields~, loc~)
}

///|
#callsite(autofill(loc))
pub fn Logger::info(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Info, msg, fields~, loc~)
}

///|
#callsite(autofill(loc))
pub fn Logger::warn(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Warn, msg, fields~, loc~)
}

///|
#callsite(autofill(loc))
pub fn Logger::error(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Error_, msg, fields~, loc~)
}
