///|
pub fn subscriber(
  min_level? : @moontrace.Level = @moontrace.Trace,
  output? : (String) -> Unit = fn(s) { println(s) },
) -> (@moontrace.Event) -> Unit {
  fn(event) {
    if event.level < min_level {
      return
    }
    let json_str = event.to_json().stringify()
    output(json_str)
  }
}
