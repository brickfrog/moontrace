///|
pub fn[T : ToJson] Span::with_field(
  self : Span,
  key : String,
  value : T,
) -> Span {
  self.record(key, value)
  self
}
