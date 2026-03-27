///|
pub fn subscriber(
  min_level? : @moontrace.Level = @moontrace.Trace,
  output? : (String) -> Unit = fn(s) { println(s) },
  color? : Bool = true,
  format_timestamp? : (UInt64) -> String = @moontrace.format_timestamp_hms,
) -> (@moontrace.Event) -> Unit {
  fn(event) {
    if event.level < min_level {
      return
    }
    output(@moontrace.format_event(event, color, format_timestamp))
  }
}

///|
pub fn initialize(
  min_level? : @moontrace.Level = @moontrace.Trace,
  output? : (String) -> Unit = fn(s) { println(s) },
  color? : Bool = true,
  format_timestamp? : (UInt64) -> String = @moontrace.format_timestamp_hms,
) -> Unit {
  @moontrace.set_subscriber(
    subscriber(min_level~, output~, color~, format_timestamp~),
  )
}
