///|
/// Counts are nonnegative protobuf int64 values. Zero counts may carry a warning.
pub(all) struct ExportPartialSuccess {
  rejected_spans : Int64
  rejected_log_records : Int64
  error_message : String
} derive(Eq, Compare, Debug)

///|
/// Additive response detail without changing the constructible ExportOutcome.
pub(all) struct ExportReport {
  outcome : ExportOutcome
  partial_success : ExportPartialSuccess?
} derive(Eq, Compare, Debug)

///|
fn invalid_response() -> TransportError {
  Request("invalid OTLP JSON export response")
}

///|
/// Parse exact decimal integers, including protobuf JSON exponent notation.
/// Work on decimal digits rather than Double, which loses precision above 2^53.
fn parse_count_text(text : String) -> Int64? {
  let chars = text.to_array()
  let mut i = 0
  let mut negative = false
  if i < chars.length() && chars[i] == '-' {
    negative = true
    i += 1
  }
  let digits : Array[Int32] = []
  let mut fraction = 0
  let start = i
  while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
    digits.push(chars[i].to_int() - 48)
    i += 1
  }
  if i == start {
    return None
  }
  if i < chars.length() && chars[i] == '.' {
    i += 1
    let start = i
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      digits.push(chars[i].to_int() - 48)
      fraction += 1
      i += 1
    }
    if i == start {
      return None
    }
  }
  let mut exponent = 0
  if i < chars.length() && (chars[i] == 'e' || chars[i] == 'E') {
    i += 1
    let mut sign = 1
    if i < chars.length() && (chars[i] == '+' || chars[i] == '-') {
      if chars[i] == '-' {
        sign = -1
      }
      i += 1
    }
    let start = i
    while i < chars.length() && chars[i] >= '0' && chars[i] <= '9' {
      // Larger exponents cannot change the result except for all-zero mantissas.
      exponent = if exponent >= 100000 {
        1000000
      } else {
        exponent * 10 + chars[i].to_int() - 48
      }
      i += 1
    }
    if i == start {
      return None
    }
    exponent *= sign
  }
  if i != chars.length() {
    return None
  }
  if digits.all(d => d == 0) {
    return Some(0L)
  }
  if negative {
    return None
  }
  let shift = exponent - fraction
  let end = digits.length() + (if shift < 0 { shift } else { 0 })
  if end < 0 {
    return None
  }
  for j in end..<digits.length() {
    if digits[j] != 0 {
      return None
    }
  }
  let mut value = 0L
  for j in 0..<end {
    let digit = digits[j].to_int64()
    if value > (9223372036854775807L - digit) / 10L {
      return None
    }
    value = value * 10L + digit
  }
  if shift > 19 {
    return None
  }
  for _ in 0..<(if shift > 0 { shift } else { 0 }) {
    if value > 922337203685477580L {
      return None
    }
    value *= 10L
  }
  Some(value)
}

///|
fn response_count(value : Json?) -> Int64? {
  match value {
    None | Some(Null) => Some(0L)
    Some(String(text)) => parse_count_text(text)
    // ProtoJSON specifies Double coercion for bare numeric int64 values.
    // Require the exclusive upper bound before converting: Int64.MAX rounds up.
    Some(Number(n, ..)) =>
      if n >= 0.0 && n < 9223372036854775808.0 && n == n.floor() {
        Some(n.to_int64())
      } else {
        None
      }
    _ => None
  }
}

///|
/// Empty bodies are accepted for compatibility. Nonempty bodies must be JSON
/// objects; unknown fields are ignored as required by OTLP JSON encoding.
pub fn parse_export_response(
  body : String,
) -> Result[ExportPartialSuccess?, TransportError] {
  if body.length() > 65536 {
    return Err(invalid_response())
  }
  if body.trim().is_empty() {
    return Ok(None)
  }
  let json = @json.parse(body) catch { _ => return Err(invalid_response()) }
  let object = match json {
    Object(fields) => fields
    _ => return Err(invalid_response())
  }
  let fields = match object.get("partialSuccess") {
    None | Some(Null) => return Ok(None)
    Some(Object(fields)) => fields
    _ => return Err(invalid_response())
  }
  let rejected_spans = match response_count(fields.get("rejectedSpans")) {
    Some(n) => n
    None => return Err(invalid_response())
  }
  let rejected_log_records = match
    response_count(fields.get("rejectedLogRecords")) {
    Some(n) => n
    None => return Err(invalid_response())
  }
  let error_message = match fields.get("errorMessage") {
    None | Some(Null) => ""
    Some(String(s)) => s
    _ => return Err(invalid_response())
  }
  Ok(Some({ rejected_spans, rejected_log_records, error_message, }))
}
