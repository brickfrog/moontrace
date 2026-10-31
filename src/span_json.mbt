///|
pub fn Span::to_json(self : Span) -> Json {
  let m : Map[String, Json] = Map([])
  m.set("name", Json(self.name))
  m.set("trace_id", Json(self.trace_id))
  m.set("span_id", Json(self.span_id))
  if !self.parent_span_id.is_empty() {
    m.set("parent_span_id", Json(self.parent_span_id))
  }
  m.set("kind", self.kind.to_json())
  m.set("active", Json(self.active))
  m.set("start_time_ns", Json(self.start_time))
  m.set("end_time_ns", Json(self.end_time))
  m.set("duration_ns", Json(self.duration()))
  if self.status != Unset {
    m.set("status", self.status.to_json())
    if !self.status_message.is_empty() {
      m.set("status_message", Json(self.status_message))
    }
  }
  m.set("fields", fields_to_json(self.fields))
  m.set("links", Json(self.links.map(fn(link) { link.to_json() })))
  if !self.events.is_empty() {
    m.set(
      "events",
      Json(
        self.events.map(event => {
          let entry : Map[String, Json] = Map([])
          entry.set("name", Json(event.name))
          entry.set("timestamp", Json(event.timestamp))
          entry.set("fields", fields_to_json(event.fields))
          Json(entry)
        }),
      ),
    )
  }
  Json(m)
}
