///|
pub impl Show for Field with fn output(self, logger) {
  logger.write_string(escape_control_chars(self.key))
  logger.write_string("=")
  logger.write_string(self.value.stringify())
}

///|
pub fn Field::to_json(self : Field) -> Json {
  let m : Map[String, Json] = {}
  m.set(self.key, self.value)
  m.to_json()
}
