///|
pub fn format_timestamp_hms(timestamp : UInt64) -> String {
  // @env.now() returns milliseconds since epoch
  let total_millis = timestamp
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
  format_event(self, color, format_timestamp_hms)
}

///|
pub fn format_event(
  event : Event,
  color : Bool,
  format_timestamp : (UInt64) -> String,
) -> String {
  let buf = StringBuilder::new()
  buf.write_string(format_timestamp(event.timestamp))
  buf.write_string(" | ")
  let level_str = pad_right(event.level.to_string(), 5)
  if color {
    buf.write_string(level_color(event.level))
    buf.write_string(level_str)
    buf.write_string("\u001b[0m")
  } else {
    buf.write_string(level_str)
  }
  let source = format_source(event.source)
  if source.length() > 0 {
    buf.write_string(" | ")
    buf.write_string(source)
  }
  buf.write_string(" — ")
  buf.write_string(event.message)
  if event.fields.length() > 0 {
    buf.write_string("  ")
    let mut first = true
    event.fields.each(fn(f) {
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
fn format_source(source : String) -> String {
  if source.length() == 0 {
    return ""
  }
  for i = 0; i < source.length(); i = i + 1 {
    if source[i] == '/' {
      let next = i + 1
      if next >= source.length() {
        return source
      }
      return source[next:].to_string()
    }
  }
  source
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
