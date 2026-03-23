///|
pub fn initialize(
  min_level? : @moontrace.Level = @moontrace.Trace,
  color? : Bool = true,
) -> Unit {
  @moontrace.set_subscriber(subscriber(min_level~, color~))
}
