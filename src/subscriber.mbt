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

///|
/// Transform each event before `inner` sees it. Returning `None` drops the
/// event. Use it to rename or rewrite fields or messages for one subscriber.
/// The transform receives a copy of the event's fields, including nested JSON,
/// so in-place changes do not reach other subscribers in a `compose`.
pub fn map_events(
  inner : (Event) -> Unit,
  transform : (Event) -> Event?,
) -> (Event) -> Unit {
  fn(event) {
    let fields = event.fields.map(field => Field::{
      key: field.key,
      value: copy_logger_json(field.value),
    })
    match transform({ ..event, fields, }) {
      Some(mapped) => inner(mapped)
      None => ()
    }
  }
}

///|
/// Forward only events for which `predicate` returns true.
pub fn filter_events(
  inner : (Event) -> Unit,
  predicate : (Event) -> Bool,
) -> (Event) -> Unit {
  fn(event) { if predicate(event) { inner(event) } }
}

///|
/// Add fields computed per event, such as a hostname or a derived value.
/// Computed fields are placed before the event's fields, and the event's own
/// fields win on key collisions, matching global fields. For duplicate computed
/// keys, the last value wins.
pub fn enrich(
  inner : (Event) -> Unit,
  compute : (Event) -> Array[Field],
) -> (Event) -> Unit {
  fn(event) {
    let computed = compute(event)
    if computed.is_empty() {
      inner(event)
      return
    }
    let existing : Map[String, Bool] = Map([])
    for field in event.fields {
      existing.set(field.key, true)
    }
    let extra : Map[String, Json] = Map([])
    for field in computed {
      if !existing.contains(field.key) {
        extra.set(field.key, field.value)
      }
    }
    let fields : Array[Field] = []
    extra.each(fn(key, value) { fields.push({ key, value, }) })
    for field in event.fields {
      fields.push(field)
    }
    inner({ ..event, fields, })
  }
}

///|
/// Apply package directives to one subscriber, using the same longest-prefix
/// rule as global module filters. Global filters still run first, so this can
/// only make a subscriber stricter than the global configuration. The filter
/// is copied when the wrapper is created.
pub fn with_directives(
  inner : (Event) -> Unit,
  filter : ParsedFilter,
) -> (Event) -> Unit {
  let filters = filter.module_filters.copy()
  let default_level = filter.default_level
  fn(event) {
    if event.level >= resolve_module_level(filters, default_level, event.source) {
      inner(event)
    }
  }
}
