///|
pub fn initialize(
  min_level? : @moontrace.Level = @moontrace.Trace,
  color? : Bool = true,
  output? : (String) -> Unit,
  format_timestamp? : (UInt64) -> String = @moontrace.format_timestamp_hms,
) -> Unit {
  @moontrace.set_subscriber(
    subscriber(min_level~, color~, output?, format_timestamp~),
  )
}
