///|
pub fn Span::to_json(self : Span) -> Json {
  let m : Map[String, Json] = {}
  m.set("name", self.name.to_json())
  m.set("active", self.active.to_json())
  m.set("start_time_ns", self.start_time.to_json())
  m.set("end_time_ns", self.end_time.to_json())
  m.set("duration_ns", self.duration().to_json())
  let fm : Map[String, Json] = {}
  self.fields.each(fn(f) { fm.set(f.key, f.value) })
  m.set("fields", fm.to_json())
  m.to_json()
}
