///|
pub fn Span::with_field(self : Span, key : String, value : Json) -> Span {
  self.fields.push({ key, value })
  self
}
