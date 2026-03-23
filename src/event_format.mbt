///|
pub fn Event::format(self : Event) -> String {
  let buf = StringBuilder::new()
  buf.write_string(self.timestamp.to_string())
  buf.write_string(" ")
  buf.write_string(self.level.to_string())
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
