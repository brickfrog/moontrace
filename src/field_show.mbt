///|
pub impl Show for Field with output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub impl Show for Field with to_string(self) {
  self.key + "=" + self.value.stringify()
}

///|
pub fn Field::to_json(self : Field) -> Json {
  let m : Map[String, Json] = {}
  m.set(self.key, self.value)
  m.to_json()
}
