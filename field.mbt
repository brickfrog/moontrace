///|
pub(all) struct Field {
  key : String
  value : Json
}

///|
pub fn fields(pairs : Array[(String, Json)]) -> Array[Field] {
  pairs.map(fn(pair) { { key: pair.0, value: pair.1 } })
}
