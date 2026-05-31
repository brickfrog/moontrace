///|
pub(all) struct Event {
  level : Level
  message : String
  fields : Array[Field]
  timestamp : UInt64
  source : String
} derive(Debug)

///|
let global_subscriber : Ref[((Event) -> Unit)?] = { val: None }

///|
let global_min_level : Ref[Level] = { val: Trace }

///|
pub fn set_min_level(level : Level) -> Unit {
  global_min_level.val = level
}

///|
pub fn get_min_level() -> Level {
  global_min_level.val
}

///|
pub fn set_subscriber(f : (Event) -> Unit) -> Unit {
  global_subscriber.val = Some(f)
}

///|
pub fn clear_subscriber() -> Unit {
  global_subscriber.val = None
}

///|
fn merge_fields(fields : Array[Field]) -> Array[Field] {
  if global_context.val.is_empty() {
    fields
  } else {
    let explicit_keys : Map[String, Bool] = {}
    fields.each(fn(f) { explicit_keys.set(f.key, true) })
    let merged : Array[Field] = []
    global_context.val.each(fn(k, v) {
      if !explicit_keys.contains(k) {
        merged.push({ key: k, value: v })
      }
    })
    fields.each(fn(f) { merged.push(f) })
    merged
  }
}

///|
fn dispatch(event : Event) -> Unit {
  match global_subscriber.val {
    Some(f) => f(event)
    None => ()
  }
}

///|
fn emit(level : Level, msg : String, fields : Array[Field]) -> Unit {
  if level < global_min_level.val {
    return
  }
  match global_subscriber.val {
    Some(f) =>
      f(Event::{
        level,
        message: msg,
        fields: merge_fields(fields),
        timestamp: @env.now(),
        source: "",
      })
    None => ()
  }
}

///|
fn emit_with_loc(
  level : Level,
  msg : String,
  fields : Array[Field],
  loc : SourceLoc,
) -> Unit {
  let source = extract_package(loc)
  if !should_log_module(source, level) {
    return
  }
  let event = Event::{
    level,
    message: msg,
    fields: merge_fields(fields),
    timestamp: @env.now(),
    source,
  }
  dispatch(event)
}

///|
fn is_span_correlation_field(key : String) -> Bool {
  key == "trace_id" || key == "span_id" || key == "parent_span_id"
}

///|
fn span_event_fields(span : Span, fields : Array[Field]) -> Array[Field] {
  let merged : Array[Field] = []
  fields.each(fn(field) {
    if !is_span_correlation_field(field.key) {
      merged.push(field)
    }
  })
  merged.push({ key: "trace_id", value: span.trace_id.to_json() })
  merged.push({ key: "span_id", value: span.span_id.to_json() })
  merged.push({ key: "parent_span_id", value: span.parent_span_id.to_json() })
  merged
}

///|
fn emit_in_span_with_loc(
  span : Span,
  level : Level,
  msg : String,
  fields : Array[Field],
  loc : SourceLoc,
) -> Unit {
  let source = extract_package(loc)
  if !should_log_module(source, level) {
    return
  }
  let event = Event::{
    level,
    message: msg,
    fields: merge_fields(span_event_fields(span, fields)),
    timestamp: @env.now(),
    source,
  }
  dispatch(event)
}

///|
#callsite(autofill(loc))
pub fn event_in_span(
  span : Span,
  level : Level,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(span, level, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn trace_in_span(
  span : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(span, Trace, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn debug_in_span(
  span : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(span, Debug, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn info_in_span(
  span : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(span, Info, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn warn_in_span(
  span : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(span, Warn, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn error_in_span(
  span : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(span, Error_, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn Span::event(
  self : Span,
  level : Level,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(self, level, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn Span::trace(
  self : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(self, Trace, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn Span::debug(
  self : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(self, Debug, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn Span::info(
  self : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(self, Info, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn Span::warn(
  self : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(self, Warn, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn Span::error(
  self : Span,
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_in_span_with_loc(self, Error_, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn info(
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_with_loc(Info, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn warn(
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_with_loc(Warn, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn error(
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_with_loc(Error_, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn debug(
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_with_loc(Debug, msg, fields, loc)
}

///|
#callsite(autofill(loc))
pub fn trace(
  msg : String,
  fields? : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  emit_with_loc(Trace, msg, fields, loc)
}

///|
pub fn Event::to_json(self : Event) -> Json {
  let m : Map[String, Json] = {}
  m.set("level", self.level.to_json())
  m.set("message", self.message.to_json())
  m.set("timestamp", self.timestamp.to_json())
  m.set("source", self.source.to_json())
  m.set("fields", fields_to_json(self.fields))
  m.to_json()
}
