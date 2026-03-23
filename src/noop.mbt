///|
pub fn noop() -> (Event) -> Unit {
  fn(_event) {  }
}

///|
pub fn tap(
  subscriber : (Event) -> Unit,
  on_event : (Event) -> Unit,
) -> (Event) -> Unit {
  fn(event) {
    on_event(event)
    subscriber(event)
  }
}
