///|
/// Keys written before event fields. A field with one of these keys is written
/// as `fields.<key>` so it cannot shadow the event's own values.
let reserved_keys : Array[String] = ["ts", "level", "msg", "source", "caller"]

///|
/// Format `event` as one logfmt line:
///
/// ```text
/// ts=2026-03-28T14:31:43.903Z level=info msg="server started" source=choir/server caller=src/server/main.mbt:42 port=8080
/// ```
///
/// `source` and `caller` are omitted when the event has none. Levels are
/// lowercase. String field values are written as text; other JSON values use
/// their compact JSON encoding. Values are quoted when they are empty or
/// contain spaces, `=`, `"`, or control characters. Keys have those characters
/// replaced with `_`.
pub fn format_event(
  event : @moontrace.Event,
  format_timestamp~ : (UInt64) -> String = @moontrace.format_timestamp_rfc3339,
) -> String {
  let buf = StringBuilder()
  buf.write_string("ts=")
  write_value(buf, format_timestamp(event.timestamp))
  write_pair(buf, "level", event.level.to_string().to_lower())
  write_pair(buf, "msg", event.message)
  if !event.source.is_empty() {
    write_pair(buf, "source", event.source)
  }
  if !event.file.is_empty() {
    write_pair(buf, "caller", "\{event.file}:\{event.line}")
  }
  for field in event.fields {
    let key = sanitize_key(field.key)
    let key = if reserved_keys.contains(key) { "fields." + key } else { key }
    let value = match field.value {
      String(text) => text
      other => other.stringify()
    }
    write_pair(buf, key, value)
  }
  buf.to_string()
}

///|
/// Write logfmt lines for events at or above `min_level` to `output`.
pub fn subscriber(
  min_level~ : @moontrace.Level = @moontrace.Trace,
  output~ : (String) -> Unit = fn(s) { println(s) },
  format_timestamp~ : (UInt64) -> String = @moontrace.format_timestamp_rfc3339,
) -> (@moontrace.Event) -> Unit {
  fn(event) {
    if event.level < min_level {
      return
    }
    output(format_event(event, format_timestamp~))
  }
}

///|
/// Install a logfmt subscriber as the global subscriber.
pub fn initialize(
  min_level~ : @moontrace.Level = @moontrace.Trace,
  output? : (String) -> Unit,
  format_timestamp~ : (UInt64) -> String = @moontrace.format_timestamp_rfc3339,
) -> Unit {
  @moontrace.set_subscriber(subscriber(min_level~, output?, format_timestamp~))
}

///|
/// Write ` key=value`; the leading `ts` pair is written without a separator.
fn write_pair(buf : StringBuilder, key : String, value : String) -> Unit {
  buf.write_char(' ')
  buf.write_string(key)
  buf.write_char('=')
  write_value(buf, value)
}

///|
fn needs_quotes(value : String) -> Bool {
  value.is_empty() ||
  value.iter().any(ch => ch == ' ' || ch == '=' || ch == '"' || ch.is_control())
}

///|
fn write_value(buf : StringBuilder, value : String) -> Unit {
  if !needs_quotes(value) {
    buf.write_string(value)
    return
  }
  buf.write_char('"')
  for ch in value {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      _ =>
        if ch.is_control() {
          buf.write_string("\\u")
          buf.write_string(ch.to_int().to_string(radix=16).pad_start(4, '0'))
        } else {
          buf.write_char(ch)
        }
    }
  }
  buf.write_char('"')
}

///|
fn sanitize_key(key : String) -> String {
  if key.is_empty() {
    return "_"
  }
  let buf = StringBuilder()
  for ch in key {
    if ch == ' ' || ch == '=' || ch == '"' || ch.is_control() {
      buf.write_char('_')
    } else {
      buf.write_char(ch)
    }
  }
  buf.to_string()
}
