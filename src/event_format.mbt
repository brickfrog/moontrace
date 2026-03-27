///|
pub fn format_timestamp_hms(timestamp : UInt64) -> String {
  let total_millis = timestamp / (1_000_000 : UInt64)
  let total_seconds = total_millis / (1000 : UInt64)
  let hours = total_seconds / (3600 : UInt64) % (24 : UInt64)
  let minutes = total_seconds / (60 : UInt64) % (60 : UInt64)
  let seconds = total_seconds % (60 : UInt64)
  let millis = total_millis % (1000 : UInt64)

  let buf = StringBuilder::new()
  buf.write_string(pad_left_uint64(hours, 2))
  buf.write_string(":")
  buf.write_string(pad_left_uint64(minutes, 2))
  buf.write_string(":")
  buf.write_string(pad_left_uint64(seconds, 2))
  buf.write_string(".")
  buf.write_string(pad_left_uint64(millis, 3))
  buf.to_string()
}

///|
pub fn Event::format(self : Event, color? : Bool = false) -> String {
  let buf = StringBuilder::new()
  buf.write_string(format_timestamp_hms(self.timestamp))
  buf.write_string(" | ")
  let level_str = pad_right(self.level.to_string(), 5)
  if color {
    buf.write_string(level_color(self.level))
    buf.write_string(level_str)
    buf.write_string("\u001b[0m")
  } else {
    buf.write_string(level_str)
  }
  if self.source != "" {
    buf.write_string(" | ")
    buf.write_string(self.source)
  }
  buf.write_string(" — ")
  buf.write_string(self.message)
  if self.fields.length() > 0 {
    let mut first = true
    buf.write_string("  ")
    self.fields.each(fn(f) {
      if first {
        first = false
      } else {
        buf.write_string(" ")
      }
      buf.write_string(f.key)
      buf.write_string("=")
      buf.write_string(f.value.stringify())
    })
  }
  buf.to_string()
}

///|
fn pad_left_uint64(value : UInt64, width : Int) -> String {
  pad_left(value.to_string(), width)
}

///|
fn pad_left(s : String, width : Int) -> String {
  if s.length() >= width {
    s
  } else {
    let buf = StringBuilder::new()
    for i = s.length(); i < width; i = i + 1 {
      buf.write_string("0")
    }
    buf.write_string(s)
    buf.to_string()
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
