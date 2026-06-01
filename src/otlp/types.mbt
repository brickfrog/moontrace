// OTLP attribute value

///|
pub(all) enum OtlpValue {
  StringVal(String)
  IntVal(Int64)
  BoolVal(Bool)
  DoubleVal(Double)
} derive(Debug)

///|
pub(all) struct OtlpAttribute {
  key : String
  value : OtlpValue
} derive(Debug)

///|
pub(all) struct OtlpSpan {
  trace_id : String
  span_id : String
  parent_span_id : String
  flags : Int
  name : String
  kind : Int // 1=INTERNAL, 2=SERVER, 3=CLIENT
  start_time_unix_nano : UInt64
  end_time_unix_nano : UInt64
  attributes : Array[OtlpAttribute]
  status_code : Int // 0=UNSET, 1=OK, 2=ERROR
  status_message : String
} derive(Debug)

///|
pub(all) struct OtlpLogRecord {
  time_unix_nano : UInt64
  severity_number : Int
  severity_text : String
  body : String
  attributes : Array[OtlpAttribute]
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
  service_name? : String = "",
  service_version? : String = "",
  attributes? : Array[OtlpAttribute] = [],
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
  { attributes: resource_attributes }
}

///|
pub fn instrumentation_scope(
  name? : String = "moontrace",
  version? : String = "",
  attributes? : Array[OtlpAttribute] = [],
) -> InstrumentationScope {
  { name, version, attributes: attributes.copy() }
}

// Convert OtlpValue to Json

///|
pub fn OtlpValue::to_json(self : OtlpValue) -> Json {
  match self {
    StringVal(s) => {
      let m : Map[String, Json] = {}
      m.set("stringValue", s.to_json())
      m.to_json()
    }
    IntVal(i) => {
      let m : Map[String, Json] = {}
      m.set("intValue", i.to_string().to_json())
      m.to_json()
    }
    BoolVal(b) => {
      let m : Map[String, Json] = {}
      m.set("boolValue", b.to_json())
      m.to_json()
    }
    DoubleVal(d) => {
      let m : Map[String, Json] = {}
      m.set("doubleValue", d.to_json())
      m.to_json()
    }
  }
}

///|
pub fn OtlpAttribute::to_json(self : OtlpAttribute) -> Json {
  let m : Map[String, Json] = {}
  m.set("key", self.key.to_json())
  m.set("value", self.value.to_json())
  m.to_json()
}

///|
pub fn OtlpSpan::to_json(self : OtlpSpan) -> Json {
  let m : Map[String, Json] = {}
  m.set("traceId", self.trace_id.to_json())
  m.set("spanId", self.span_id.to_json())
  if !self.parent_span_id.is_empty() {
    m.set("parentSpanId", self.parent_span_id.to_json())
  }
  m.set("flags", self.flags.to_json())
  m.set("name", self.name.to_json())
  m.set("kind", self.kind.to_json())
  m.set("startTimeUnixNano", self.start_time_unix_nano.to_string().to_json())
  m.set("endTimeUnixNano", self.end_time_unix_nano.to_string().to_json())
  m.set("attributes", self.attributes.map(fn(a) { a.to_json() }).to_json())
  let status : Map[String, Json] = {}
  status.set("code", self.status_code.to_json())
  if !self.status_message.is_empty() {
    status.set("message", self.status_message.to_json())
  }
  m.set("status", status.to_json())
  m.to_json()
}

///|
pub fn OtlpLogRecord::to_json(self : OtlpLogRecord) -> Json {
  let m : Map[String, Json] = {}
  m.set("timeUnixNano", self.time_unix_nano.to_string().to_json())
  m.set("severityNumber", self.severity_number.to_json())
  m.set("severityText", self.severity_text.to_json())
  let body : Map[String, Json] = {}
  body.set("stringValue", self.body.to_json())
  m.set("body", body.to_json())
  m.set("attributes", self.attributes.map(fn(a) { a.to_json() }).to_json())
  m.to_json()
}

///|
pub fn Resource::to_json(self : Resource) -> Json {
  let m : Map[String, Json] = {}
  m.set("attributes", self.attributes.map(fn(a) { a.to_json() }).to_json())
  m.to_json()
}

///|
pub fn InstrumentationScope::to_json(self : InstrumentationScope) -> Json {
  let m : Map[String, Json] = {}
  m.set("name", self.name.to_json())
  if !self.version.is_empty() {
    m.set("version", self.version.to_json())
  }
  m.set("attributes", self.attributes.map(fn(a) { a.to_json() }).to_json())
  m.to_json()
}
