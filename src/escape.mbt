///|
/// Render control code points visibly in human-readable output while preserving
/// printable text verbatim.
fn escape_control_chars(value : String) -> String {
  let buf = StringBuilder()
  for ch in value.iter() {
    match ch {
      '\b' => buf.write_string("\\b")
      '\u{000c}' => buf.write_string("\\f")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if ch.is_control() {
          let hex = ch.to_int().to_string(radix=16).pad_start(4, '0')
          buf.write_string("\\u{")
          buf.write_string(hex)
          buf.write_string("}")
        } else {
          buf.write_char(ch)
        }
    }
  }
  buf.to_string()
}
