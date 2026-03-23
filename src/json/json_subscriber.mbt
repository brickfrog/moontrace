///|
pub fn subscriber(
  min_level? : @moontrace.Level = @moontrace.Trace,
  output? : (String) -> Unit = fn(s) { println(s) },
) -> (@moontrace.Event) -> Unit {
  fn(event) {
    if event.level < min_level {
      return
    }
    let m : Map[String, Json] = {}
    m.set("level", event.level.to_string().to_json())
    m.set("message", event.message.to_json())
    m.set("timestamp", event.timestamp.to_string().to_json())
    let fm : Map[String, Json] = {}
    event.fields.each(fn(f) { fm.set(f.key, f.value) })
    m.set("fields", fm.to_json())
    output(m.to_json().stringify())
  }
}
