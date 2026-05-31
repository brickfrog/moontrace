///|
let env_filter_ws = " \t\r\n"

///|
pub(all) enum EnvFilterError {
  InvalidLevel(String)
  MalformedDirective(String)
} derive(Eq, Compare, Debug)

///|
pub fn EnvFilterError::to_string(self : EnvFilterError) -> String {
  match self {
    InvalidLevel(level) => "invalid env filter level: " + level
    MalformedDirective(directive) =>
      "malformed env filter directive: " + directive
  }
}

///|
pub impl Show for EnvFilterError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) struct ParsedFilter {
  default_level : Level
  module_filters : Map[String, Level]
} derive(Debug)

///|
fn trim_env_filter_part(value : StringView) -> String {
  value.trim(chars=env_filter_ws).to_owned()
}

///|
fn parse_env_filter_level(level : String) -> Result[Level, EnvFilterError] {
  match Level::from_string(level) {
    Some(parsed) => Ok(parsed)
    None => Err(InvalidLevel(level))
  }
}

///|
/// Parse a compact filter directive string.
///
/// Supported directives are comma-separated bare levels (`info`) and exact
/// package filters (`brickfrog/moontrace=debug`). Empty directives are skipped,
/// duplicate defaults or package filters are accepted, and the last directive
/// wins. If no bare default is present, the parsed default is `Info`.
pub fn parse_env_filter(
  directive : String,
) -> Result[ParsedFilter, EnvFilterError] {
  let mut default_level = Info
  let filters : Map[String, Level] = {}
  for raw_part in directive.split(",") {
    let part = trim_env_filter_part(raw_part)
    if !part.is_empty() {
      match part.split_once("=") {
        Some((target_view, level_view)) => {
          let level_raw = level_view.to_owned()
          if level_raw.contains("=") {
            return Err(MalformedDirective(part))
          }
          let target = trim_env_filter_part(target_view)
          let level_text = trim_env_filter_part(level_view)
          if target.is_empty() || level_text.is_empty() {
            return Err(MalformedDirective(part))
          }
          match parse_env_filter_level(level_text) {
            Ok(level) => filters.set(target, level)
            Err(err) => return Err(err)
          }
        }
        None =>
          match parse_env_filter_level(part) {
            Ok(level) => default_level = level
            Err(err) => return Err(err)
          }
      }
    }
  }
  Ok({ default_level, module_filters: filters })
}

///|
/// Apply a parsed filter deterministically by replacing global filter state.
pub fn apply_env_filter(parsed : ParsedFilter) -> Unit {
  clear_module_filters()
  set_min_level(parsed.default_level)
  parsed.module_filters.each(fn(target, level) {
    set_module_filter(target, level)
  })
}

///|
pub fn ParsedFilter::apply(self : ParsedFilter) -> Unit {
  apply_env_filter(self)
}

///|
pub fn set_filter_from_directives(
  directive : String,
) -> Result[Unit, EnvFilterError] {
  match parse_env_filter(directive) {
    Ok(parsed) => {
      apply_env_filter(parsed)
      Ok(())
    }
    Err(err) => Err(err)
  }
}

///|
/// Initialize filters from `MOONTRACE_LOG` by default.
///
/// Unset or ASCII-whitespace-only values are no-ops. Present non-empty values
/// are parsed and applied, with invalid directives returned as structured
/// errors so logging is never widened by ignoring a bad filter.
pub fn initialize_from_env(
  env_var? : String = "MOONTRACE_LOG",
) -> Result[Unit, EnvFilterError] {
  match @env.get_env_var(env_var) {
    Some(value) =>
      if value.trim(chars=env_filter_ws).is_empty() {
        Ok(())
      } else {
        set_filter_from_directives(value)
      }
    None => Ok(())
  }
}
