///|
pub(all) enum Level {
  Trace
  Debug
  Info
  Warn
  Error_
} derive(Show, Eq, Compare)

///|
pub fn Level::to_string(self : Level) -> String {
  match self {
    Trace => "TRACE"
    Debug => "DEBUG"
    Info => "INFO"
    Warn => "WARN"
    Error_ => "ERROR"
  }
}
