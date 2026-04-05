///|
pub impl Show for Event with output(self, logger) {
  logger.write_string(self.format())
}
