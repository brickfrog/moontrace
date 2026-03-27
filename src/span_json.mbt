///|
pub fn Span::to_json(self : Span) -> Json {
  let m : Map[String, Json] = {}
  m.set("name", self.name.to_json())
  m.set("trace_id", self.trace_id.to_json())
  m.set("span_id", self.span_id.to_json())
  if self.parent_span_id.length() > 0 {
    m.set("parent_span_id", self.parent_span_id.to_json())
  }
  m.set("active", self.active.to_json())
  m.set("start_time_ns", self.start_time.to_json())
  m.set("end_time_ns", self.end_time.to_json())
  m.set("duration_ns", self.duration().to_json())
  m.set("fields", fields_to_json(self.fields))
  m.to_json()
}
