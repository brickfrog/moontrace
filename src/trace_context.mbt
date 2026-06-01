///|
pub(all) enum TraceContextError {
  InvalidTraceId(String)
  InvalidSpanId(String)
  InvalidTraceFlags(String)
  InvalidTraceParent(String)
  UnsupportedTraceParentVersion(String)
  InvalidTraceState(String)
} derive(Eq, Compare, Debug)

///|
pub impl Show for TraceContextError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn TraceContextError::to_string(self : TraceContextError) -> String {
  match self {
    InvalidTraceId(reason) => "invalid trace id: " + reason
    InvalidSpanId(reason) => "invalid span id: " + reason
    InvalidTraceFlags(reason) => "invalid trace flags: " + reason
    InvalidTraceParent(reason) => "invalid traceparent: " + reason
    UnsupportedTraceParentVersion(version) =>
      "unsupported traceparent version: " + version
    InvalidTraceState(reason) => "invalid tracestate: " + reason
  }
}

///|
pub struct TraceId {
  value : String
} derive(Eq, Compare, Debug)

///|
pub struct SpanId {
  value : String
} derive(Eq, Compare, Debug)

///|
pub struct TraceFlags {
  flags : Int
} derive(Eq, Compare, Debug)

///|
pub struct TraceStateEntry {
  key : String
  value : String
} derive(Eq, Compare, Debug)

///|
pub struct TraceState {
  priv entries : Array[TraceStateEntry]
} derive(Debug)

///|
pub struct SpanContext {
  trace_id : String
  span_id : String
  flags : TraceFlags
  trace_state : TraceState
  is_remote : Bool
} derive(Debug)

///|
fn is_lower_hex_unit(unit : Int) -> Bool {
  (unit >= 48 && unit <= 57) || (unit >= 97 && unit <= 102)
}

///|
fn hex_value_unit(unit : Int) -> Int? {
  if unit >= 48 && unit <= 57 {
    Some(unit - 48)
  } else if unit >= 97 && unit <= 102 {
    Some(unit - 87)
  } else {
    None
  }
}

///|
fn is_lower_hex_string(value : String, expected_len : Int) -> Bool {
  if value.length() != expected_len {
    return false
  }
  let mut ok = true
  for i in 0..<value.length() {
    let unit = value.code_unit_at(i).to_int()
    if !is_lower_hex_unit(unit) {
      ok = false
    }
  }
  ok
}

///|
fn is_all_zero(value : String) -> Bool {
  let mut all_zero = true
  for i in 0..<value.length() {
    let unit = value.code_unit_at(i).to_int()
    if unit != 48 {
      all_zero = false
    }
  }
  all_zero
}

///|
fn hex_digit(value : Int) -> String {
  match value {
    0 => "0"
    1 => "1"
    2 => "2"
    3 => "3"
    4 => "4"
    5 => "5"
    6 => "6"
    7 => "7"
    8 => "8"
    9 => "9"
    10 => "a"
    11 => "b"
    12 => "c"
    13 => "d"
    14 => "e"
    _ => "f"
  }
}

///|
fn parse_hex_byte(value : String) -> Int? {
  guard value.length() == 2 else { return None }
  match
    (
      hex_value_unit(value.code_unit_at(0).to_int()),
      hex_value_unit(value.code_unit_at(1).to_int()),
    ) {
    (Some(hi_val), Some(lo_val)) => Some(hi_val * 16 + lo_val)
    _ => None
  }
}

///|
pub fn TraceId::parse(value : String) -> Result[TraceId, TraceContextError] {
  if !is_lower_hex_string(value, 32) {
    Result::Err(InvalidTraceId("expected 32 lowercase hex characters"))
  } else if is_all_zero(value) {
    Result::Err(InvalidTraceId("all-zero trace id is invalid"))
  } else {
    Result::Ok({ value, })
  }
}

///|
pub fn trace_id(value : String) -> Result[TraceId, TraceContextError] {
  TraceId::parse(value)
}

///|
pub fn TraceId::to_string(self : TraceId) -> String {
  self.value
}

///|
pub impl Show for TraceId with fn output(self, logger) {
  logger.write_string(self.value)
}

///|
pub fn SpanId::parse(value : String) -> Result[SpanId, TraceContextError] {
  if !is_lower_hex_string(value, 16) {
    Result::Err(InvalidSpanId("expected 16 lowercase hex characters"))
  } else if is_all_zero(value) {
    Result::Err(InvalidSpanId("all-zero span id is invalid"))
  } else {
    Result::Ok({ value, })
  }
}

///|
pub fn span_id(value : String) -> Result[SpanId, TraceContextError] {
  SpanId::parse(value)
}

///|
pub fn SpanId::to_string(self : SpanId) -> String {
  self.value
}

///|
pub impl Show for SpanId with fn output(self, logger) {
  logger.write_string(self.value)
}

///|
pub fn TraceFlags::from_int(
  flags : Int,
) -> Result[TraceFlags, TraceContextError] {
  if flags < 0 || flags > 255 {
    Result::Err(InvalidTraceFlags("expected an unsigned 8-bit value"))
  } else {
    Result::Ok({ flags, })
  }
}

///|
pub fn TraceFlags::from_hex(
  value : String,
) -> Result[TraceFlags, TraceContextError] {
  match parse_hex_byte(value) {
    Some(flags) => TraceFlags::from_int(flags)
    None =>
      Result::Err(InvalidTraceFlags("expected 2 lowercase hex characters"))
  }
}

///|
pub fn TraceFlags::sampled() -> TraceFlags {
  { flags: 1 }
}

///|
pub fn TraceFlags::unsampled() -> TraceFlags {
  { flags: 0 }
}

///|
pub fn trace_flags_sampled() -> TraceFlags {
  TraceFlags::sampled()
}

///|
pub fn trace_flags_unsampled() -> TraceFlags {
  TraceFlags::unsampled()
}

///|
pub fn TraceFlags::is_sampled(self : TraceFlags) -> Bool {
  self.flags % 2 == 1
}

///|
pub fn TraceFlags::with_sampled(
  self : TraceFlags,
  sampled : Bool,
) -> TraceFlags {
  match (self.is_sampled(), sampled) {
    (true, false) => { flags: self.flags - 1 }
    (false, true) => { flags: self.flags + 1 }
    _ => self
  }
}

///|
pub fn TraceFlags::to_int(self : TraceFlags) -> Int {
  self.flags
}

///|
pub fn TraceFlags::to_hex(self : TraceFlags) -> String {
  hex_digit(self.flags / 16) + hex_digit(self.flags % 16)
}

///|
fn traceparent_flags_hex(flags : TraceFlags) -> String {
  if flags.is_sampled() {
    "01"
  } else {
    "00"
  }
}

///|
fn traceparent_flags(flags : TraceFlags) -> TraceFlags {
  if flags.is_sampled() {
    TraceFlags::sampled()
  } else {
    TraceFlags::unsampled()
  }
}

///|
pub impl Show for TraceFlags with fn output(self, logger) {
  logger.write_string(self.to_hex())
}

///|
fn is_trace_state_key_start(unit : Int, allow_digit : Bool) -> Bool {
  (unit >= 97 && unit <= 122) || (allow_digit && unit >= 48 && unit <= 57)
}

///|
fn is_trace_state_key_rest(unit : Int) -> Bool {
  (unit >= 97 && unit <= 122) ||
  (unit >= 48 && unit <= 57) ||
  unit == 95 ||
  unit == 45 ||
  unit == 42 ||
  unit == 47
}

///|
fn validate_key_part(
  value : String,
  max_len : Int,
  allow_digit_start : Bool,
) -> Bool {
  guard !value.is_empty() && value.length() <= max_len else { return false }
  for i in 0..<value.length() {
    let unit = value.code_unit_at(i).to_int()
    if i == 0 {
      if !is_trace_state_key_start(unit, allow_digit_start) {
        return false
      }
    } else if !is_trace_state_key_rest(unit) {
      return false
    }
  }
  true
}

///|
fn validate_trace_state_key(key : String) -> Bool {
  guard !key.is_empty() && key.length() <= 256 else { return false }
  match key.split_once("@") {
    Some((tenant_view, system_view)) => {
      let tenant = tenant_view.to_owned()
      let system = system_view.to_owned()
      if system.contains("@") {
        false
      } else {
        validate_key_part(tenant, 241, true) &&
        validate_key_part(system, 14, false)
      }
    }
    None => validate_key_part(key, 256, true)
  }
}

///|
fn validate_trace_state_value(value : String) -> Bool {
  guard !value.is_empty() && value.length() <= 256 else { return false }
  for i in 0..<value.length() {
    let unit = value.code_unit_at(i).to_int()
    if unit < 32 || unit > 126 || unit == 44 || unit == 61 {
      return false
    }
  }
  value.code_unit_at(value.length() - 1).to_int() != 32
}

///|
fn validate_trace_state_entry(
  key : String,
  value : String,
) -> Result[TraceStateEntry, TraceContextError] {
  if !validate_trace_state_key(key) {
    Result::Err(InvalidTraceState("invalid key: " + key))
  } else if !validate_trace_state_value(value) {
    Result::Err(InvalidTraceState("invalid value for key: " + key))
  } else {
    Result::Ok({ key, value })
  }
}

///|
pub fn trace_state_entry(
  key : String,
  value : String,
) -> Result[TraceStateEntry, TraceContextError] {
  validate_trace_state_entry(key, value)
}

///|
fn append_trace_state_entry(
  entries : Array[TraceStateEntry],
  entry : TraceStateEntry,
) -> Array[TraceStateEntry] {
  let next : Array[TraceStateEntry] = []
  entries.each(fn(existing) {
    if existing.key != entry.key {
      next.push(existing)
    }
  })
  next.push(entry)
  next
}

///|
fn prepend_trace_state_entry(
  entries : Array[TraceStateEntry],
  entry : TraceStateEntry,
) -> Array[TraceStateEntry] {
  let next : Array[TraceStateEntry] = [entry]
  entries.each(fn(existing) {
    if existing.key != entry.key {
      next.push(existing)
    }
  })
  next
}

///|
pub fn TraceState::empty() -> TraceState {
  { entries: [] }
}

///|
pub fn TraceState::from_entries(
  entries : Array[TraceStateEntry],
) -> Result[TraceState, TraceContextError] {
  if entries.length() > 32 {
    return Result::Err(InvalidTraceState("expected at most 32 entries"))
  }
  let mut normalized : Array[TraceStateEntry] = []
  for i in 0..<entries.length() {
    match validate_trace_state_entry(entries[i].key, entries[i].value) {
      Result::Ok(entry) =>
        normalized = append_trace_state_entry(normalized, entry)
      Result::Err(err) => return Result::Err(err)
    }
  }
  Result::Ok({ entries: normalized })
}

///|
pub fn trace_state(
  entries : Array[TraceStateEntry],
) -> Result[TraceState, TraceContextError] {
  TraceState::from_entries(entries)
}

///|
pub fn TraceState::len(self : TraceState) -> Int {
  self.entries.length()
}

///|
pub fn TraceState::is_empty(self : TraceState) -> Bool {
  self.entries.is_empty()
}

///|
pub fn TraceState::get(self : TraceState, key : String) -> String? {
  for i in 0..<self.entries.length() {
    if self.entries[i].key == key {
      return Some(self.entries[i].value)
    }
  }
  None
}

///|
pub fn TraceState::set(
  self : TraceState,
  key : String,
  value : String,
) -> Result[TraceState, TraceContextError] {
  match validate_trace_state_entry(key, value) {
    Result::Ok(entry) => {
      let entries = prepend_trace_state_entry(self.entries, entry)
      if entries.length() > 32 {
        Result::Err(InvalidTraceState("expected at most 32 entries"))
      } else {
        Result::Ok({ entries, })
      }
    }
    Result::Err(err) => Result::Err(err)
  }
}

///|
pub fn TraceState::to_header(self : TraceState) -> String {
  let buf = StringBuilder()
  for i in 0..<self.entries.length() {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string(self.entries[i].key)
    buf.write_string("=")
    buf.write_string(self.entries[i].value)
  }
  buf.to_string()
}

///|
pub fn format_tracestate(state : TraceState) -> String {
  state.to_header()
}

///|
fn copy_trace_state(state : TraceState) -> TraceState {
  { entries: state.entries.copy() }
}

///|
pub fn parse_tracestate(
  header : String,
) -> Result[TraceState, TraceContextError] {
  let mut parsed_entries : Array[TraceStateEntry] = []
  let mut non_empty_count = 0
  let parts : Array[String] = header
    .split(",")
    .map(part => part.to_owned())
    .collect()
  for i in 0..<parts.length() {
    let list_member = parts[i].trim(chars=" \t").to_owned()
    if !list_member.is_empty() {
      non_empty_count = non_empty_count + 1
      if non_empty_count > 32 {
        return Result::Err(InvalidTraceState("expected at most 32 entries"))
      }
      match list_member.split_once("=") {
        Some((key_view, value_view)) => {
          let key = key_view.to_owned()
          let value = value_view.to_owned()
          match validate_trace_state_entry(key, value) {
            Result::Ok(entry) =>
              parsed_entries = append_trace_state_entry(parsed_entries, entry)
            Result::Err(err) => return Result::Err(err)
          }
        }
        None =>
          return Result::Err(
            InvalidTraceState("expected key=value list member"),
          )
      }
    }
  }
  Result::Ok({ entries: parsed_entries })
}

///|
pub fn span_context(
  trace_id : TraceId,
  span_id : SpanId,
  flags? : TraceFlags = { flags: 0 },
  trace_state? : TraceState = { entries: [] },
  is_remote? : Bool = false,
) -> SpanContext {
  {
    trace_id: trace_id.value,
    span_id: span_id.value,
    flags,
    trace_state: copy_trace_state(trace_state),
    is_remote,
  }
}

///|
pub fn span_context_from_ids(
  trace_id : String,
  span_id : String,
  flags? : TraceFlags = { flags: 0 },
  trace_state? : TraceState = { entries: [] },
  is_remote? : Bool = false,
) -> Result[SpanContext, TraceContextError] {
  match TraceId::parse(trace_id) {
    Result::Ok(tid) =>
      match SpanId::parse(span_id) {
        Result::Ok(sid) =>
          Result::Ok(span_context(tid, sid, flags~, trace_state~, is_remote~))
        Result::Err(err) => Result::Err(err)
      }
    Result::Err(err) => Result::Err(err)
  }
}

///|
pub fn SpanContext::is_sampled(self : SpanContext) -> Bool {
  self.flags.is_sampled()
}

///|
pub fn SpanContext::is_remote(self : SpanContext) -> Bool {
  self.is_remote
}

///|
pub fn SpanContext::trace_flags_int(self : SpanContext) -> Int {
  self.flags.to_int()
}

///|
pub fn SpanContext::traceparent(self : SpanContext) -> String {
  format_traceparent(self)
}

///|
pub fn format_traceparent(ctx : SpanContext) -> String {
  "00-" +
  ctx.trace_id +
  "-" +
  ctx.span_id +
  "-" +
  traceparent_flags_hex(ctx.flags)
}

///|
pub fn parse_traceparent(
  header : String,
) -> Result[SpanContext, TraceContextError] {
  let parts : Array[String] = header
    .split("-")
    .map(part => part.to_owned())
    .collect()
  if parts.length() < 4 {
    return Result::Err(
      InvalidTraceParent("expected version-trace-id-span-id-flags"),
    )
  }
  let version = parts[0]
  if version.length() != 2 || !is_lower_hex_string(version, 2) {
    return Result::Err(InvalidTraceParent("invalid version"))
  }
  if version == "ff" {
    return Result::Err(InvalidTraceParent("version ff is reserved"))
  }
  if version == "00" && parts.length() != 4 {
    return Result::Err(
      InvalidTraceParent("version 00 cannot contain extra fields"),
    )
  }
  match TraceId::parse(parts[1]) {
    Result::Ok(tid) =>
      match SpanId::parse(parts[2]) {
        Result::Ok(sid) =>
          match TraceFlags::from_hex(parts[3]) {
            Result::Ok(flags) =>
              Result::Ok(
                span_context(
                  tid,
                  sid,
                  flags=traceparent_flags(flags),
                  trace_state=TraceState::empty(),
                  is_remote=true,
                ),
              )
            Result::Err(err) => Result::Err(err)
          }
        Result::Err(err) => Result::Err(err)
      }
    Result::Err(err) => Result::Err(err)
  }
}

///|
pub fn parse_span_context(
  traceparent : String,
  tracestate? : String = "",
) -> Result[SpanContext, TraceContextError] {
  match parse_traceparent(traceparent) {
    Result::Ok(ctx) => {
      let state = match parse_tracestate(tracestate) {
        Result::Ok(state) => state
        Result::Err(_) => TraceState::empty()
      }
      Result::Ok({
        trace_id: ctx.trace_id,
        span_id: ctx.span_id,
        flags: ctx.flags,
        trace_state: state,
        is_remote: true,
      })
    }
    Result::Err(err) => Result::Err(err)
  }
}

///|
pub fn span_trace_flags(span : Span) -> TraceFlags {
  match TraceFlags::from_int(span.trace_flags) {
    Result::Ok(flags) => flags
    Result::Err(_) => TraceFlags::unsampled()
  }
}

///|
pub fn span_trace_state(span : Span) -> TraceState {
  copy_trace_state(span.trace_state)
}

///|
pub fn span_context_from_span(
  span : Span,
) -> Result[SpanContext, TraceContextError] {
  match
    span_context_from_ids(
      span.trace_id,
      span.span_id,
      flags=span_trace_flags(span),
      trace_state=span_trace_state(span),
      is_remote=false,
    ) {
    Result::Ok(ctx) => Result::Ok(ctx)
    Result::Err(err) => Result::Err(err)
  }
}

///|
pub fn traceparent_from_span(span : Span) -> Result[String, TraceContextError] {
  match span_context_from_span(span) {
    Result::Ok(ctx) => Result::Ok(format_traceparent(ctx))
    Result::Err(err) => Result::Err(err)
  }
}

///|
pub fn span_from_remote_context(
  ctx : SpanContext,
  name : String,
  fields? : Array[Field] = [],
  kind? : SpanKind = Server,
) -> Span {
  let s = span_with_ids_unnotified(
    name,
    fields,
    ctx.trace_id,
    ctx.span_id,
    kind,
    trace_flags=ctx.flags.to_int(),
    trace_state=ctx.trace_state,
  )
  notify_span_created(s)
  notify_span_linked(s, {
    trace_id: ctx.trace_id,
    span_id: ctx.span_id,
    kind: SpanChildOf,
    fields: [],
    trace_state: ctx.trace_state.to_header(),
  })
  s
}
