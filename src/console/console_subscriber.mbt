///|
/// Write one human-readable record per event to `output`.
///
/// * `color` adds ANSI level colors.
/// * `format_timestamp` renders the millisecond timestamp.
/// * `location` adds the caller's `file:line`.
/// * `pretty` writes each field on its own indented line for local
///   development instead of a single line.
/// * `format` replaces the built-in layout entirely; when it is given, `color`,
///   `format_timestamp`, `location`, and `pretty` are not used.
pub fn subscriber(
  min_level~ : @moontrace.Level = @moontrace.Trace,
  output~ : (String) -> Unit = fn(s) { println(s) },
  color~ : Bool = true,
  format_timestamp~ : (UInt64) -> String = @moontrace.format_timestamp_utc,
  location~ : Bool = false,
  pretty~ : Bool = false,
  format? : (@moontrace.Event) -> String,
) -> (@moontrace.Event) -> Unit {
  let render = match format {
    Some(custom) => custom
    None if pretty =>
      event => {
        @moontrace.format_event_pretty(
          event,
          color,
          format_timestamp,
          location~,
        )
      }
    None =>
      event => {
        @moontrace.format_event(event, color, format_timestamp, location~)
      }
  }
  fn(event) {
    if event.level < min_level {
      return
    }
    output(render(event))
  }
}
