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

///|
fn invalid_protobuf_response() -> TransportError {
  Request("invalid OTLP protobuf export response")
}

///|
/// Read a base-128 varint at `pos` that must end before `limit`, returning the
/// value and next position.
fn read_proto_varint(
  body : Bytes,
  pos : Int32,
  limit : Int32,
) -> (UInt64, Int32)? {
  let mut value = 0UL
  let mut shift = 0
  let mut i = pos
  while i < limit && shift < 64 {
    let byte = body[i].to_uint64()
    value = value | ((byte & 0x7FUL) << shift)
    i += 1
    if (byte & 0x80UL) == 0UL {
      return Some((value, i))
    }
    shift += 7
  }
  None
}

///|
/// Skip one field of `wire_type` at `pos` that must end by `limit`, returning
/// the next position.
fn skip_proto_field(
  body : Bytes,
  pos : Int32,
  wire_type : Int32,
  limit : Int32,
) -> Int32? {
  match wire_type {
    0 => read_proto_varint(body, pos, limit).map(r => r.1)
    1 => if pos + 8 <= limit { Some(pos + 8) } else { None }
    2 => read_proto_length(body, pos, limit).map(r => r.1)
    5 => if pos + 4 <= limit { Some(pos + 4) } else { None }
    _ => None
  }
}

///|
/// Read a length prefix at `pos` and check that the delimited bytes end by
/// `limit`. Returns the start and end of the delimited bytes.
fn read_proto_length(
  body : Bytes,
  pos : Int32,
  limit : Int32,
) -> (Int32, Int32)? {
  guard read_proto_varint(body, pos, limit) is Some((len, start)) &&
    start <= limit &&
    len <= (limit - start).to_uint64() else {
    return None
  }
  Some((start, start + len.to_int()))
}

///|
/// Parse an `Export{Trace,Logs}ServiceResponse` protobuf body. Both carry
/// `partial_success` as field 1, a message with the rejected count (field 1,
/// int64) and `error_message` (field 2). The count is reported as
/// `rejected_spans` or `rejected_log_records` according to `signal`. Empty
/// bodies give `None`; unknown fields are skipped.
pub fn parse_protobuf_export_response(
  body : Bytes,
  signal : OtlpSignal,
) -> Result[ExportPartialSuccess?, TransportError] {
  if body.length() > 65536 {
    return Err(invalid_protobuf_response())
  }
  let mut partial : ExportPartialSuccess? = None
  let mut pos = 0
  let limit = body.length()
  while pos < limit {
    guard read_proto_varint(body, pos, limit) is Some((tag, next)) else {
      return Err(invalid_protobuf_response())
    }
    let field = (tag >> 3).to_int()
    let wire_type = (tag & 7UL).to_int()
    if field == 1 && wire_type == 2 {
      guard read_proto_length(body, next, limit) is Some((start, end)) else {
        return Err(invalid_protobuf_response())
      }
      match parse_protobuf_partial(body, start, end, signal) {
        Some(details) => partial = Some(details)
        None => return Err(invalid_protobuf_response())
      }
      pos = end
    } else {
      guard skip_proto_field(body, next, wire_type, limit) is Some(after) else {
        return Err(invalid_protobuf_response())
      }
      pos = after
    }
  }
  Ok(partial)
}

///|
fn parse_protobuf_partial(
  body : Bytes,
  start : Int32,
  end : Int32,
  signal : OtlpSignal,
) -> ExportPartialSuccess? {
  let mut rejected = 0L
  let mut message = ""
  let mut pos = start
  while pos < end {
    guard read_proto_varint(body, pos, end) is Some((tag, next)) else {
      return None
    }
    let field = (tag >> 3).to_int()
    let wire_type = (tag & 7UL).to_int()
    match (field, wire_type) {
      (1, 0) => {
        guard read_proto_varint(body, next, end) is Some((value, after)) else {
          return None
        }
        let count = value.reinterpret_as_int64()
        if count < 0L {
          return None
        }
        rejected = count
        pos = after
      }
      (2, 2) => {
        guard read_proto_length(body, next, end) is Some((text_start, text_end)) else {
          return None
        }
        message = @utf8.decode(body[text_start:text_end]) catch {
          _ => return None
        }
        pos = text_end
      }
      _ => {
        guard skip_proto_field(body, next, wire_type, end) is Some(after) else {
          return None
        }
        pos = after
      }
    }
  }
  if pos != end {
    return None
  }
  Some(
    match signal {
      Traces =>
        {
          rejected_spans: rejected,
          rejected_log_records: 0L,
          error_message: message,
        }
      Logs =>
        {
          rejected_spans: 0L,
          rejected_log_records: rejected,
          error_message: message,
        }
    },
  )
}
