///|
pub fn initialize(
  min_level? : @moontrace.Level = @moontrace.Trace,
  output? : (String) -> Unit,
) -> Unit {
  @moontrace.set_subscriber(subscriber(min_level~, output?))
}
