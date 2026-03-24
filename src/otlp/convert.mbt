// Convert moontrace Level to OTLP severity number

///|
pub fn level_to_severity(level : @moontrace.Level) -> Int {
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
pub fn field_to_attribute(field : @moontrace.Field) -> OtlpAttribute {
  { key: field.key, value: StringVal(field.value.stringify()) }
}

// Convert moontrace Event to OTLP log record

///|
pub fn event_to_log_record(event : @moontrace.Event) -> OtlpLogRecord {
  {
    time_unix_nano: event.timestamp,
    severity_number: level_to_severity(event.level),
    severity_text: event.level.to_string(),
    body: event.message,
    attributes: event.fields.map(fn(f) { field_to_attribute(f) }),
  }
}

// Wrap log records in OTLP resourceLogs envelope

///|
pub fn wrap_log_records(records : Array[OtlpLogRecord]) -> Json {
  let scope : Map[String, Json] = {}
  scope.set("name", "moontrace".to_json())
  scope.set("version", "0.1.0".to_json())

  let scope_logs : Map[String, Json] = {}
  scope_logs.set("scope", scope.to_json())
  scope_logs.set("logRecords", records.map(fn(r) { r.to_json() }).to_json())

  let resource_logs : Map[String, Json] = {}
  let resource : Map[String, Json] = {}
  resource.set("attributes", ([] : Array[Json]).to_json())
  resource_logs.set("resource", resource.to_json())
  resource_logs.set("scopeLogs", [scope_logs.to_json()].to_json())

  let root : Map[String, Json] = {}
  root.set("resourceLogs", [resource_logs.to_json()].to_json())
  root.to_json()
}

// Wrap spans in OTLP resourceSpans envelope

///|
pub fn wrap_spans(spans : Array[OtlpSpan]) -> Json {
  let scope : Map[String, Json] = {}
  scope.set("name", "moontrace".to_json())
  scope.set("version", "0.1.0".to_json())

  let scope_spans : Map[String, Json] = {}
  scope_spans.set("scope", scope.to_json())
  scope_spans.set("spans", spans.map(fn(s) { s.to_json() }).to_json())

  let resource_spans : Map[String, Json] = {}
  let resource : Map[String, Json] = {}
  resource.set("attributes", ([] : Array[Json]).to_json())
  resource_spans.set("resource", resource.to_json())
  resource_spans.set("scopeSpans", [scope_spans.to_json()].to_json())

  let root : Map[String, Json] = {}
  root.set("resourceSpans", [resource_spans.to_json()].to_json())
  root.to_json()
}
