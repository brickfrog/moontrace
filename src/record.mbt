///|
pub fn[T : ToJson] Span::record(self : Span, key : String, value : T) -> Unit {
  self.fields.push({ key, value: value.to_json() })
}
