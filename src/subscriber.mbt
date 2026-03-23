///|
pub fn compose(subscribers : Array[(Event) -> Unit]) -> (Event) -> Unit {
  fn(event) { subscribers.each(fn(s) { s(event) }) }
}

///|
pub fn with_filter(
  subscriber : (Event) -> Unit,
  min_level : Level,
) -> (Event) -> Unit {
  fn(event) { if event.level >= min_level { subscriber(event) } }
}
