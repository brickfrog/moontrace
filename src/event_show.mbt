///|
pub fn Event::to_string(self : Event) -> String {
  self.format()
}

///|
pub fn Event::output(self : Event, logger : &Logger) -> Unit {
  logger.write_string(self.format())
}
