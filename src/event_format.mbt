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
  buf.write_string(hours.to_string().pad_start(2, '0'))
  buf.write_string(":")
  buf.write_string(minutes.to_string().pad_start(2, '0'))
  buf.write_string(":")
  buf.write_string(seconds.to_string().pad_start(2, '0'))
  buf.write_string(".")
  buf.write_string(millis.to_string().pad_start(3, '0'))
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
  let level_str = event.level.to_string().pad_end(5, ' ')
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
fn format_source(source : String) -> String {
  match source.split_once("/") {
    Some((_, after)) => after.to_string()
    None => source
  }
}
