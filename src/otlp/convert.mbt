// Convert moontrace Level to OTLP severity number

///|
pub fn level_to_severity(level : @moontrace.Level) -> Int32 {
  match level {
    @moontrace.Trace => 1
    @moontrace.Debug => 5
    @moontrace.Info => 9
    @moontrace.Warn => 13
    @moontrace.Error_ => 17
  }
}

// Convert moontrace Field to OTLP attribute

///|
fn json_to_otlp_value(value : Json) -> OtlpValue {
  match value {
    String(s) => StringVal(s)
    Number(n, ..) =>
      if n == n.floor() {
        IntVal(n.floor().to_int64())
      } else {
        DoubleVal(n)
      }
    True => BoolVal(true)
    False => BoolVal(false)
    Array(values) => ArrayVal(values.map(json_to_otlp_value))
    Object(entries) => {
      let attributes : Array[OtlpAttribute] = []
      for key, nested in entries {
        attributes.push({ key, value: json_to_otlp_value(nested), })
      }
      KvlistVal(attributes)
    }
    _ => StringVal(value.stringify())
  }
}

///|
pub fn field_to_attribute(field : @moontrace.Field) -> OtlpAttribute {
  { key: field.key, value: json_to_otlp_value(field.value), }
}

// Convert moontrace Event to OTLP log record

///|
/// Convert an event, applying `limits` (OpenTelemetry defaults unless given)
/// to its attributes.
pub fn event_to_log_record(
  event : @moontrace.Event,
  limits~ : OtlpLimits = otlp_limits(),
) -> OtlpLogRecord {
  let trace_id = match event_string_field(event, "trace_id") {
    Some(value) =>
      match @moontrace.TraceId::parse(value) {
        Ok(_) => value
        Err(_) => ""
      }
    None => ""
  }
  let span_id = match (trace_id, event_string_field(event, "span_id")) {
    ("", _) | (_, None) => ""
    (_, Some(value)) =>
      match @moontrace.SpanId::parse(value) {
        Ok(_) => value
        Err(_) => ""
      }
  }
  let (attributes, dropped_attributes_count) = limit_attributes(
    log_record_attributes(event),
    limits,
  )
  {
    time_unix_nano: milliseconds_to_nanoseconds(event.timestamp),
    severity_number: level_to_severity(event.level),
    severity_text: event.level.to_string(),
    body: event.message,
    attributes,
    trace_id,
    span_id,
    dropped_attributes_count,
  }
}

///|
/// Event fields plus OpenTelemetry `code.file.path` and `code.line.number`
/// when the event carries a call-site location. A field with either key wins
/// over the captured location so OTLP attribute keys stay unique.
fn log_record_attributes(event : @moontrace.Event) -> Array[OtlpAttribute] {
  let attributes = event.fields.map(fn(f) { field_to_attribute(f) })
  if !event.file.is_empty() {
    let has_field = key => event.fields.iter().any(f => f.key == key)
    if !has_field("code.file.path") {
      attributes.push({ key: "code.file.path", value: StringVal(event.file), })
    }
    if !has_field("code.line.number") {
      attributes.push({
        key: "code.line.number",
        value: IntVal(event.line.to_int64()),
      })
    }
  }
  attributes
}

///|
/// Return the last string value for `key`; span-associated events append
/// their protected correlation fields after caller fields.
fn event_string_field(event : @moontrace.Event, key : String) -> String? {
  let mut found = None
  for field in event.fields {
    if field.key == key {
      match field.value {
        String(value) => found = Some(value)
        _ => ()
      }
    }
  }
  found
}

// Wrap log records in OTLP resourceLogs envelope

///|
pub fn wrap_log_records(
  records : Array[OtlpLogRecord],
  resource~ : Resource = resource(),
  scope~ : InstrumentationScope = instrumentation_scope(),
) -> Json {
  let scope_logs : Map[String, Json] = Map([])
  scope_logs.set("scope", scope.to_json())
  scope_logs.set("logRecords", Json(records.map(fn(r) { r.to_json() })))

  let resource_logs : Map[String, Json] = Map([])
  resource_logs.set("resource", resource.to_json())
  resource_logs.set("scopeLogs", Json([Json(scope_logs)]))

  let root : Map[String, Json] = Map([])
  root.set("resourceLogs", Json([Json(resource_logs)]))
  Json(root)
}

// Wrap spans in OTLP resourceSpans envelope

///|
pub fn wrap_spans(
  spans : Array[OtlpSpan],
  resource~ : Resource = resource(),
  scope~ : InstrumentationScope = instrumentation_scope(),
) -> Json {
  let scope_spans : Map[String, Json] = Map([])
  scope_spans.set("scope", scope.to_json())
  scope_spans.set("spans", Json(spans.map(fn(s) { s.to_json() })))

  let resource_spans : Map[String, Json] = Map([])
  resource_spans.set("resource", resource.to_json())
  resource_spans.set("scopeSpans", Json([Json(scope_spans)]))

  let root : Map[String, Json] = Map([])
  root.set("resourceSpans", Json([Json(resource_spans)]))
  Json(root)
}

///|
/// Convert core clock milliseconds only at the Moontrace -> OTLP boundary.
/// Saturate unrepresentable values rather than silently wrapping fixed64.
fn milliseconds_to_nanoseconds(value : UInt64) -> UInt64 {
  if value > 18446744073709UL {
    18446744073709551615UL
  } else {
    value * 1000000UL
  }
}
