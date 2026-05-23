///|
pub impl Show for Event with fn output(self, logger) {
  logger.write_string(self.format())
}
