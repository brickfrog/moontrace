///|
pub fn initialize(min_level? : @moontrace.Level = @moontrace.Trace) -> Unit {
  @moontrace.set_subscriber(subscriber(min_level~))
}
