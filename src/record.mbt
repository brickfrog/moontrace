///|
pub fn[T : ToJson] Span::record(self : Span, key : String, value : T) -> Unit {
  let field = { key, value: value.to_json() }
  self.fields.push(field)
  notify_span_recorded(self, field)
}
