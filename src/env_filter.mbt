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
/// A parsed filter directive. `default_off` is set by a bare `off`, and
/// `silenced_modules` lists packages set to `off`; a package appears in at
/// most one of `module_filters` and `silenced_modules`.
pub(all) struct ParsedFilter {
  default_level : Level
  module_filters : Map[String, Level]
  silenced_modules : Array[String]
  default_off : Bool
} derive(Debug)

///|
/// Package filters in resolver form, with silenced packages as `None`.
fn ParsedFilter::resolved_filters(self : ParsedFilter) -> Map[String, Level?] {
  let resolved : Map[String, Level?] = Map([])
  self.module_filters.each((target, level) => resolved.set(target, Some(level)))
  self.silenced_modules.each(target => resolved.set(target, None))
  resolved
}

///|
fn ParsedFilter::resolved_default(self : ParsedFilter) -> Level? {
  if self.default_off {
    None
  } else {
    Some(self.default_level)
  }
}

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
/// Supported directives are comma-separated bare levels (`info`) and package
/// filters (`brickfrog/moontrace=debug`). `off` (any case) silences: a bare
/// `off` silences every package without a more specific filter, and
/// `my/app=off` silences that package. A package filter also applies to its
/// subpackages; the longest matching package wins. Empty directives are skipped,
/// duplicate defaults or package filters are accepted, and the last directive
/// wins. If no bare default is present, the parsed default is `Info`.
pub fn parse_env_filter(
  directive : String,
) -> Result[ParsedFilter, EnvFilterError] {
  let mut default_level = Info
  let mut default_off = false
  let filters : Map[String, Level?] = Map([])
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
          if level_text.to_lower() == "off" {
            filters.set(target, None)
          } else {
            match parse_env_filter_level(level_text) {
              Ok(level) => filters.set(target, Some(level))
              Err(err) => return Err(err)
            }
          }
        }
        None =>
          if part.to_lower() == "off" {
            default_off = true
          } else {
            match parse_env_filter_level(part) {
              Ok(level) => {
                default_level = level
                default_off = false
              }
              Err(err) => return Err(err)
            }
          }
      }
    }
  }
  let module_filters : Map[String, Level] = Map([])
  let silenced_modules : Array[String] = []
  filters.each((target, level) => {
    match level {
      Some(level) => module_filters.set(target, level)
      None => silenced_modules.push(target)
    }
  })
  Ok({ default_level, module_filters, silenced_modules, default_off, })
}

///|
/// Apply a parsed filter deterministically by replacing global filter state.
pub fn apply_env_filter(parsed : ParsedFilter) -> Unit {
  clear_module_filters()
  set_min_level(parsed.default_level)
  if parsed.default_off {
    silence_all()
  }
  parsed.module_filters.each(fn(target, level) {
    set_module_filter(target, level)
  })
  parsed.silenced_modules.each(silence_module)
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
  env_var~ : String = "MOONTRACE_LOG",
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
