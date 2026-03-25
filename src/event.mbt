///|
pub(all) struct Event {
  level : Level
  message : String
  fields : Array[Field]
  timestamp : UInt64
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
fn emit(level : Level, msg : String, fields : Array[Field]) -> Unit {
  if level < global_min_level.val {
    return
  }
  let all_fields : Array[Field] = []
  // Global context fields first
  global_context.val.each(fn(k, v) { all_fields.push({ key: k, value: v }) })
  // Then explicit fields (these override context if same key)
  fields.each(fn(f) { all_fields.push(f) })
  let event = Event::{
    level,
    message: msg,
    fields: all_fields,
    timestamp: @env.now(),
  }
  match global_subscriber.val {
    Some(f) => f(event)
    None => ()
  }
}

///|
pub fn info(msg : String, fields? : Array[Field] = []) -> Unit {
  emit(Info, msg, fields)
}

///|
pub fn warn(msg : String, fields? : Array[Field] = []) -> Unit {
  emit(Warn, msg, fields)
}

///|
pub fn error(msg : String, fields? : Array[Field] = []) -> Unit {
  emit(Error_, msg, fields)
}

///|
pub fn debug(msg : String, fields? : Array[Field] = []) -> Unit {
  emit(Debug, msg, fields)
}

///|
pub fn trace(msg : String, fields? : Array[Field] = []) -> Unit {
  emit(Trace, msg, fields)
}

///|
pub fn Event::to_json(self : Event) -> Json {
  let m : Map[String, Json] = {}
  m.set("level", self.level.to_json())
  m.set("message", self.message.to_json())
  m.set("timestamp", self.timestamp.to_json())
  let fm : Map[String, Json] = {}
  self.fields.each(fn(f) { fm.set(f.key, f.value) })
  m.set("fields", fm.to_json())
  m.to_json()
}
