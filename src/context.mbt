///|
let global_context : Ref[Map[String, Json]] = { val: {} }

///|
pub fn set_global_field(key : String, value : Json) -> Unit {
  global_context.val.set(key, value)
}

///|
pub fn get_global_field(key : String) -> Json? {
  global_context.val.get(key)
}

///|
pub fn remove_global_field(key : String) -> Unit {
  global_context.val.remove(key)
}

///|
pub fn clear_global_fields() -> Unit {
  global_context.val = {}
}
