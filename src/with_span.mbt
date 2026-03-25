///|
pub fn[T] with_span(
  name : String,
  fields? : Array[Field] = [],
  f : () -> T,
) -> T {
  let s = span(name, fields~)
  s.enter()
  let result = f()
  s.exit()
  result
}

///|
pub fn[T] with_span_ctx(
  name : String,
  fields? : Array[Field] = [],
  f : (Span) -> T,
) -> T {
  let s = span(name, fields~)
  s.enter()
  let result = f(s)
  s.exit()
  result
}

///|
pub fn[T] with_child_span(
  parent : Span,
  name : String,
  fields? : Array[Field] = [],
  f : (Span) -> T,
) -> T {
  let child_fields = fields
  child_fields.push({ key: "parent", value: parent.name.to_json() })
  let s = span_with_ids(name, child_fields, parent.trace_id, parent.span_id)
  s.enter()
  let result = f(s)
  s.exit()
  result
}
