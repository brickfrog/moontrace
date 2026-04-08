///|
pub impl Show for Span with output(self, logger) {
  let buf = StringBuilder::new()
  buf.write_string("Span(")
  buf.write_string(self.name)
  buf.write_string(" ")
  buf.write_string(self.span_id)
  if self.kind != Internal {
    buf.write_string(", kind=")
    buf.write_string(self.kind.to_string())
  }
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
  if !self.fields.is_empty() {
    buf.write_string(", fields=")
    buf.write_string(self.fields.length().to_string())
  }
  if self.status != Unset {
    buf.write_string(", status=")
    buf.write_string(self.status.to_string())
    if !self.status_message.is_empty() {
      buf.write_string(" msg=")
      buf.write_string(self.status_message)
    }
  }
  buf.write_string(")")
  logger.write_string(buf.to_string())
}
