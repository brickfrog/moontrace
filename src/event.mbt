///|
pub(all) struct Event {
  level : Level
  message : String
  fields : Array[Field]
  timestamp : UInt64
  source : String
}

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

///|
/// Internal emit function without SourceLoc (for spans and internal use)
/// This bypasses module filtering and sets source to empty string
///
fn emit(level : Level, msg : String, fields : Array[Field]) -> Unit {
  if level < global_min_level.val {
    return
  }
  // Fast path: skip allocation when no global context is set
  let final_fields = if global_context.val.length() == 0 {
    fields
  } else {
    // Collect explicit field keys for dedup
    let explicit_keys : Map[String, Bool] = {}
    fields.each(fn(f) { explicit_keys.set(f.key, true) })
    let merged : Array[Field] = []
    // Global context first, skip keys that explicit fields override
    global_context.val.each(fn(k, v) {
      if not(explicit_keys.contains(k)) {
        merged.push({ key: k, value: v })
      }
    })
    // Then explicit fields
    fields.each(fn(f) { merged.push(f) })
    merged
  }
  let event = Event::{
    level,
    message: msg,
    fields: final_fields,
    timestamp: @env.now(),
    source: "",
  }
  match global_subscriber.val {
    Some(f) => f(event)
    None => ()
  }
}

///|
/// Internal emit function with SourceLoc support for module filtering
/// This is used by the public emit functions (info, warn, etc.)
///
fn emit_with_loc(
  level : Level,
  msg : String,
  fields : Array[Field],
  loc : SourceLoc,
) -> Unit {
  if level < global_min_level.val {
    return
  }
  // Extract package name from SourceLoc
  let source = extract_package(loc)
  // Check module filter
  if not(should_log_module(source, level)) {
    return
  }
  // Fast path: skip allocation when no global context is set
  let final_fields = if global_context.val.length() == 0 {
    fields
  } else {
    // Collect explicit field keys for dedup
    let explicit_keys : Map[String, Bool] = {}
    fields.each(fn(f) { explicit_keys.set(f.key, true) })
    let merged : Array[Field] = []
    // Global context first, skip keys that explicit fields override
    global_context.val.each(fn(k, v) {
      if not(explicit_keys.contains(k)) {
        merged.push({ key: k, value: v })
      }
    })
    // Then explicit fields
    fields.each(fn(f) { merged.push(f) })
    merged
  }
  let event = Event::{
    level,
    message: msg,
    fields: final_fields,
    timestamp: @env.now(),
    source,
  }
  match global_subscriber.val {
    Some(f) => f(event)
    None => ()
  }
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
  let fm : Map[String, Json] = {}
  self.fields.each(fn(f) { fm.set(f.key, f.value) })
  m.set("fields", fm.to_json())
  m.to_json()
}
