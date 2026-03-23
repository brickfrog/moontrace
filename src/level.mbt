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

///|
pub fn Level::to_json(self : Level) -> Json {
  self.to_string().to_json()
}

///|
pub fn Level::from_string(s : String) -> Level? {
  match s[:].to_upper().to_string() {
    "TRACE" => Some(Trace)
    "DEBUG" => Some(Debug)
    "INFO" => Some(Info)
    "WARN" => Some(Warn)
    "ERROR" => Some(Error_)
    _ => None
  }
}
