///|
pub fn Span::record(self : Span, key : String, value : Json) -> Unit {
  self.fields.push({ key, value })
}
