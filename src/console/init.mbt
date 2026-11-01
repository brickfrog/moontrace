///|
/// Install a console subscriber as the global subscriber. Options match
/// `subscriber`.
pub fn initialize(
  min_level~ : @moontrace.Level = @moontrace.Trace,
  color~ : Bool = true,
  output? : (String) -> Unit,
  format_timestamp~ : (UInt64) -> String = @moontrace.format_timestamp_utc,
  location~ : Bool = false,
  pretty~ : Bool = false,
  format? : (@moontrace.Event) -> String,
) -> Unit {
  @moontrace.set_subscriber(
    subscriber(
      min_level~,
      color~,
      output?,
      format_timestamp~,
      location~,
      pretty~,
      format?,
    ),
  )
}
