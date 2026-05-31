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
  let s = child_span(parent, name, fields~)
  s.enter()
  let result = f(s)
  s.exit()
  result
}
