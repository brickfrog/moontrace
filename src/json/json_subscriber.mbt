///|
/// Write one JSON record per event to `output`. Formatting options are those of
/// `event_json`; the defaults produce `event.to_json()`.
pub fn subscriber(
  min_level~ : @moontrace.Level = @moontrace.Trace,
  output~ : (String) -> Unit = fn(s) { println(s) },
  timestamp~ : TimestampFormat = EpochMillis,
  flatten~ : Bool = false,
  trace_ids~ : Bool = false,
  keys~ : JsonKeys = json_keys(),
) -> (@moontrace.Event) -> Unit {
  fn(event) {
    if event.level < min_level {
      return
    }
    output(
      event_json(event, timestamp~, flatten~, trace_ids~, keys~).stringify(),
    )
  }
}
