///|
pub fn level_color(level : Level) -> String {
  match level {
    Trace => "\u001b[2m"
    Debug => "\u001b[34m"
    Info => "\u001b[32m"
    Warn => "\u001b[33m"
    Error_ => "\u001b[31m"
  }
}
