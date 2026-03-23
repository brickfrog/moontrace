///|
pub(all) struct Span {
  name : String
  fields : Array[Field]
  start_time : UInt64
  mut end_time : UInt64
  mut active : Bool
}

///|
pub fn span(name : String, fields? : Array[Field] = []) -> Span {
  {
    name,
    fields,
    start_time: @env.now(),
    end_time: (0 : UInt64),
    active: false,
  }
}

///|
pub fn Span::enter(self : Span) -> Unit {
  self.active = true
  emit(Trace, "span.enter " + self.name, self.fields)
}

///|
pub fn Span::exit(self : Span) -> Unit {
  self.end_time = @env.now()
  self.active = false
  let duration = self.end_time - self.start_time
  let exit_fields = []
  self.fields.each(fn(f) { exit_fields.push(f) })
  exit_fields.push({ key: "duration_ns", value: duration.to_string().to_json() })
  emit(Trace, "span.exit " + self.name, exit_fields)
}

///|
pub fn Span::is_active(self : Span) -> Bool {
  self.active
}

///|
pub fn Span::duration(self : Span) -> UInt64 {
  if self.end_time > self.start_time {
    self.end_time - self.start_time
  } else {
    (0 : UInt64)
  }
}
