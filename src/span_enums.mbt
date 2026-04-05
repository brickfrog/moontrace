///|
pub(all) enum SpanKind {
  Internal // 1 in OTLP
  Server // 2
  Client // 3
  Producer // 4
  Consumer // 5
} derive(Eq, Compare)

///|
pub impl Show for SpanKind with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn SpanKind::to_string(self : SpanKind) -> String {
  match self {
    Internal => "INTERNAL"
    Server => "SERVER"
    Client => "CLIENT"
    Producer => "PRODUCER"
    Consumer => "CONSUMER"
  }
}

///|
pub fn SpanKind::to_int(self : SpanKind) -> Int {
  match self {
    Internal => 1
    Server => 2
    Client => 3
    Producer => 4
    Consumer => 5
  }
}

///|
pub(all) enum SpanStatus {
  Unset // 0 in OTLP
  Ok // 1
  SpanError // 2 — can't use Error (keyword-adjacent)
} derive(Eq, Compare)

///|
pub impl Show for SpanStatus with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn SpanStatus::to_string(self : SpanStatus) -> String {
  match self {
    Unset => "UNSET"
    Ok => "OK"
    SpanError => "ERROR"
  }
}

///|
pub fn SpanStatus::to_int(self : SpanStatus) -> Int {
  match self {
    Unset => 0
    Ok => 1
    SpanError => 2
  }
}

///|
pub fn SpanStatus::to_json(self : SpanStatus) -> Json {
  self.to_string().to_json()
}

///|
pub fn SpanKind::to_json(self : SpanKind) -> Json {
  self.to_string().to_json()
}
