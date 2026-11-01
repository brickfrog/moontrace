// OTLP attribute value

///|
pub(all) enum OtlpValue {
  StringVal(String)
  IntVal(Int64)
  BoolVal(Bool)
  DoubleVal(Double)
  ArrayVal(Array[OtlpValue])
  KvlistVal(Array[OtlpAttribute])
  /// An `AnyValue` with no value set, OTLP's representation of null.
  EmptyVal
} derive(Debug)

///|
pub(all) struct OtlpAttribute {
  key : String
  value : OtlpValue
} derive(Debug)

///|
pub(all) struct OtlpLink {
  trace_id : String
  span_id : String
  trace_state : String
  attributes : Array[OtlpAttribute]
  dropped_attributes_count : Int32
} derive(Debug)

///|
pub(all) struct OtlpSpanEvent {
  time_unix_nano : UInt64
  name : String
  attributes : Array[OtlpAttribute]
  dropped_attributes_count : Int32
} derive(Debug)

///|
pub(all) struct OtlpSpan {
  trace_id : String
  span_id : String
  parent_span_id : String
  flags : Int32
  name : String
  kind : Int32 // 1=INTERNAL, 2=SERVER, 3=CLIENT
  start_time_unix_nano : UInt64
  end_time_unix_nano : UInt64
  attributes : Array[OtlpAttribute]
  events : Array[OtlpSpanEvent]
  links : Array[OtlpLink]
  status_code : Int32 // 0=UNSET, 1=OK, 2=ERROR
  status_message : String
  dropped_attributes_count : Int32
  dropped_events_count : Int32
  dropped_links_count : Int32
} derive(Debug)

///|
pub(all) struct OtlpLogRecord {
  time_unix_nano : UInt64
  severity_number : Int32
  severity_text : String
  body : String
  attributes : Array[OtlpAttribute]
  trace_id : String
  span_id : String
  dropped_attributes_count : Int32
} derive(Debug)

///|
pub(all) struct Resource {
  attributes : Array[OtlpAttribute]
} derive(Debug)

///|
pub(all) struct InstrumentationScope {
  name : String
  version : String
  attributes : Array[OtlpAttribute]
} derive(Debug)

///|
const SERVICE_NAME_KEY : String = "service.name"

///|
const SERVICE_VERSION_KEY : String = "service.version"

///|
pub fn resource(
  service_name~ : String = "",
  service_version~ : String = "",
  attributes~ : Array[OtlpAttribute] = [],
) -> Resource {
  let resource_attributes : Array[OtlpAttribute] = []
  if !service_name.is_empty() {
    resource_attributes.push({
      key: SERVICE_NAME_KEY,
      value: StringVal(service_name),
    })
  }
  if !service_version.is_empty() {
    resource_attributes.push({
      key: SERVICE_VERSION_KEY,
      value: StringVal(service_version),
    })
  }
  for attribute in attributes {
    resource_attributes.push(attribute)
  }
  { attributes: resource_attributes, }
}

///|
pub fn instrumentation_scope(
  name~ : String = "moontrace",
  version~ : String = "",
  attributes~ : Array[OtlpAttribute] = [],
) -> InstrumentationScope {
  { name, version, attributes: attributes.copy(), }
}

// Convert OtlpValue to Json

///|
pub fn OtlpValue::to_json(self : OtlpValue) -> Json {
  match self {
    StringVal(s) => {
      let m : Map[String, Json] = Map([])
      m.set("stringValue", Json(s))
      Json(m)
    }
    IntVal(i) => {
      let m : Map[String, Json] = Map([])
      m.set("intValue", Json(i.to_string()))
      Json(m)
    }
    BoolVal(b) => {
      let m : Map[String, Json] = Map([])
      m.set("boolValue", Json(b))
      Json(m)
    }
    DoubleVal(d) => {
      let m : Map[String, Json] = Map([])
      m.set("doubleValue", Json(d))
      Json(m)
    }
    ArrayVal(values) => {
      let inner : Map[String, Json] = Map([])
      inner.set("values", Json(values.map(v => v.to_json())))
      let m : Map[String, Json] = Map([])
      m.set("arrayValue", Json(inner))
      Json(m)
    }
    KvlistVal(entries) => {
      let inner : Map[String, Json] = Map([])
      inner.set("values", Json(entries.map(a => a.to_json())))
      let m : Map[String, Json] = Map([])
      m.set("kvlistValue", Json(inner))
      Json(m)
    }
    EmptyVal => {
      let m : Map[String, Json] = Map([])
      Json(m)
    }
  }
}

///|
pub fn OtlpAttribute::to_json(self : OtlpAttribute) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("key", Json(self.key))
  m.set("value", self.value.to_json())
  Json(m)
}

///|
pub fn OtlpLink::to_json(self : OtlpLink) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("traceId", Json(self.trace_id))
  m.set("spanId", Json(self.span_id))
  if !self.trace_state.is_empty() {
    m.set("traceState", Json(self.trace_state))
  }
  m.set("attributes", Json(self.attributes.map(fn(a) { a.to_json() })))
  set_dropped(m, "droppedAttributesCount", self.dropped_attributes_count)
  Json(m)
}

///|
/// Write a dropped count only when it is non-zero, as OTLP JSON omits defaults.
fn set_dropped(m : Map[String, Json], key : String, count : Int32) -> Unit {
  if count > 0 {
    m.set(key, Json(count))
  }
}

///|
pub fn OtlpSpanEvent::to_json(self : OtlpSpanEvent) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("timeUnixNano", Json(self.time_unix_nano.to_string()))
  m.set("name", Json(self.name))
  m.set("attributes", Json(self.attributes.map(a => a.to_json())))
  set_dropped(m, "droppedAttributesCount", self.dropped_attributes_count)
  Json(m)
}

///|
pub fn OtlpSpan::to_json(self : OtlpSpan) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("traceId", Json(self.trace_id))
  m.set("spanId", Json(self.span_id))
  if !self.parent_span_id.is_empty() {
    m.set("parentSpanId", Json(self.parent_span_id))
  }
  m.set("flags", Json(self.flags))
  m.set("name", Json(self.name))
  m.set("kind", Json(self.kind))
  m.set("startTimeUnixNano", Json(self.start_time_unix_nano.to_string()))
  m.set("endTimeUnixNano", Json(self.end_time_unix_nano.to_string()))
  m.set("attributes", Json(self.attributes.map(fn(a) { a.to_json() })))
  set_dropped(m, "droppedAttributesCount", self.dropped_attributes_count)
  if !self.events.is_empty() {
    m.set("events", Json(self.events.map(event => event.to_json())))
  }
  set_dropped(m, "droppedEventsCount", self.dropped_events_count)
  m.set("links", Json(self.links.map(fn(link) { link.to_json() })))
  set_dropped(m, "droppedLinksCount", self.dropped_links_count)
  let status : Map[String, Json] = Map([])
  status.set("code", Json(self.status_code))
  if !self.status_message.is_empty() {
    status.set("message", Json(self.status_message))
  }
  m.set("status", Json(status))
  Json(m)
}

///|
pub fn OtlpLogRecord::to_json(self : OtlpLogRecord) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("timeUnixNano", Json(self.time_unix_nano.to_string()))
  m.set("severityNumber", Json(self.severity_number))
  m.set("severityText", Json(self.severity_text))
  let body : Map[String, Json] = Map([])
  body.set("stringValue", Json(self.body))
  m.set("body", Json(body))
  m.set("attributes", Json(self.attributes.map(fn(a) { a.to_json() })))
  if !self.trace_id.is_empty() {
    m.set("traceId", Json(self.trace_id))
  }
  if !self.span_id.is_empty() {
    m.set("spanId", Json(self.span_id))
  }
  set_dropped(m, "droppedAttributesCount", self.dropped_attributes_count)
  Json(m)
}

///|
pub fn Resource::to_json(self : Resource) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("attributes", Json(self.attributes.map(fn(a) { a.to_json() })))
  Json(m)
}

///|
pub fn InstrumentationScope::to_json(self : InstrumentationScope) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("name", Json(self.name))
  if !self.version.is_empty() {
    m.set("version", Json(self.version))
  }
  m.set("attributes", Json(self.attributes.map(fn(a) { a.to_json() })))
  Json(m)
}
