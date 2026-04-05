///|
pub(all) struct Field {
  key : String
  value : Json
}

///|
pub fn fields_to_json(fields : Array[Field]) -> Json {
  let m : Map[String, Json] = {}
  fields.each(fn(f) { m.set(f.key, f.value) })
  m.to_json()
}

///|
pub fn[T : ToJson] field(key : String, value : T) -> Field {
  { key, value: value.to_json() }
}

///|
pub fn fields(pairs : Array[(String, Json)]) -> Array[Field] {
  pairs.map(fn(pair) { { key: pair.0, value: pair.1 } })
}
