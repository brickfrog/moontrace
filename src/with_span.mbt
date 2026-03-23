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
