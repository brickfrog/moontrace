///|
pub fn subscriber(
  min_level? : @moontrace.Level = @moontrace.Trace,
  output? : (String) -> Unit = fn(s) { println(s) },
  color? : Bool = true,
  format_timestamp? : (UInt64) -> String = fn(t) { t.to_string() },
) -> (@moontrace.Event) -> Unit {
  fn(event) {
    if event.level < min_level {
      return
    }
    let buf = StringBuilder::new()
    buf.write_string(format_timestamp(event.timestamp))
    buf.write_string(" ")
    let level_str = pad_right(event.level.to_string(), 5)
    if color {
      buf.write_string(@moontrace.level_color(event.level))
      buf.write_string(level_str)
      buf.write_string("\u001b[0m")
    } else {
      buf.write_string(level_str)
    }
    buf.write_string(" ")
    buf.write_string(event.message)
    event.fields.each(fn(f) {
      buf.write_string(" ")
      buf.write_string(f.key)
      buf.write_string("=")
      buf.write_string(f.value.stringify())
    })
    output(buf.to_string())
  }
}

///|
fn pad_right(s : String, width : Int) -> String {
  if s.length() >= width {
    s
  } else {
    let buf = StringBuilder::new()
    buf.write_string(s)
    for i = s.length(); i < width; i = i + 1 {
      buf.write_string(" ")
    }
    buf.to_string()
  }
}
