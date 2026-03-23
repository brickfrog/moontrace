///|
pub fn initialize(
  min_level? : @moontrace.Level = @moontrace.Trace,
  color? : Bool = true,
  output? : (String) -> Unit,
) -> Unit {
  @moontrace.set_subscriber(subscriber(min_level~, color~, output?))
}
