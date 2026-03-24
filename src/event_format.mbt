///|
pub fn Event::format(self : Event, color? : Bool = false) -> String {
  let buf = StringBuilder::new()
  buf.write_string(self.timestamp.to_string())
  buf.write_string(" ")
  let level_str = self.level.to_string()
  if color {
    buf.write_string(level_color(self.level))
    buf.write_string(level_str)
    buf.write_string("\u001b[0m")
  } else {
    buf.write_string(level_str)
  }
  buf.write_string(" ")
  buf.write_string(self.message)
  self.fields.each(fn(f) {
    buf.write_string(" ")
    buf.write_string(f.key)
    buf.write_string("=")
    buf.write_string(f.value.stringify())
  })
  buf.to_string()
}
