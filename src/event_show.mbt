///|
pub impl Show for Event with fn output(self, logger) {
  logger.write_string(self.format())
}

///|
pub extend Event with Show::{to_string}
