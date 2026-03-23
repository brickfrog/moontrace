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
  match s {
    "TRACE" | "trace" | "Trace" => Some(Trace)
    "DEBUG" | "debug" | "Debug" => Some(Debug)
    "INFO" | "info" | "Info" => Some(Info)
    "WARN" | "warn" | "Warn" => Some(Warn)
    "ERROR" | "error" | "Error" => Some(Error_)
    _ => None
  }
}
