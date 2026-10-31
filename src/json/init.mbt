///|
pub fn initialize(
  min_level~ : @moontrace.Level = @moontrace.Trace,
  output? : (String) -> Unit,
  timestamp~ : TimestampFormat = EpochMillis,
  flatten~ : Bool = false,
  trace_ids~ : Bool = false,
  keys~ : JsonKeys = json_keys(),
) -> Unit {
  @moontrace.set_subscriber(
    subscriber(min_level~, output?, timestamp~, flatten~, trace_ids~, keys~),
  )
}
