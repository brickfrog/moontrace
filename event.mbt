///|
pub(all) struct Event {
  level : Level
  message : String
  fields : Array[Field]
  timestamp : Int64
}

///|
let global_subscriber : Ref[((Event) -> Unit)?] = { val: None }

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
  let event = Event::{ level, message: msg, fields, timestamp: @env.now() }
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
