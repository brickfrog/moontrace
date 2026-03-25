///|
pub impl Show for Span with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub impl Show for Span with to_string(self) {
  let buf = StringBuilder::new()
  buf.write_string("Span(")
  buf.write_string(self.name)
  buf.write_string(" ")
  buf.write_string(self.span_id)
  if self.active {
    buf.write_string(", active")
  } else {
    buf.write_string(", inactive")
  }
  let d = self.duration()
  if d > (0 : UInt64) {
    buf.write_string(", duration=")
    buf.write_string(d.to_string())
    buf.write_string("ns")
  }
  if self.fields.length() > 0 {
    buf.write_string(", fields=")
    buf.write_string(self.fields.length().to_string())
  }
  buf.write_string(")")
  buf.to_string()
}
