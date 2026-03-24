///|
pub fn Span::with_field(self : Span, key : String, value : Json) -> Span {
  self.record(key, value)
  self
}
