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
pub fn info(msg : String, fields? : Array[Field] = []) -> Unit {
  let event = Event::{
    level: Info,
    message: msg,
    fields,
    timestamp: @env.now(),
  }
  match global_subscriber.val {
    Some(f) => f(event)
    None => ()
  }
}

///|
pub fn warn(msg : String, fields? : Array[Field] = []) -> Unit {
  let event = Event::{
    level: Warn,
    message: msg,
    fields,
    timestamp: @env.now(),
  }
  match global_subscriber.val {
    Some(f) => f(event)
    None => ()
  }
}

///|
pub fn error(msg : String, fields? : Array[Field] = []) -> Unit {
  let event = Event::{
    level: Error_,
    message: msg,
    fields,
    timestamp: @env.now(),
  }
  match global_subscriber.val {
    Some(f) => f(event)
    None => ()
  }
}

///|
pub fn debug(msg : String, fields? : Array[Field] = []) -> Unit {
  let event = Event::{
    level: Debug,
    message: msg,
    fields,
    timestamp: @env.now(),
  }
  match global_subscriber.val {
    Some(f) => f(event)
    None => ()
  }
}
