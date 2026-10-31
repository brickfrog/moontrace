///|
/// Global module filter map: package_name -> min_level
let module_filters : Ref[Map[String, Level]] = { val: {}, }

///|
/// Set a filter for a specific module to the given minimum level
///
/// Parameters:
/// * `module_name` - The package name (e.g., "my/package")
/// * `level` - The minimum level to log for this module
///
pub fn set_module_filter(module_name : String, level : Level) -> Unit {
  module_filters.val.set(module_name, level)
}

///|
/// Clear all module-specific filters
///
pub fn clear_module_filters() -> Unit {
  module_filters.val = {}
}

///|
/// Resolve the effective minimum level for a source package.
///
/// A package filter applies to that package and its subpackages: `my/app`
/// matches `my/app` and `my/app/db`, but not `my/apple`. The longest matching
/// package path wins, so an exact filter overrides a parent filter. Sources
/// without a matching filter fall back to the global minimum level.
fn effective_min(source : String) -> Level {
  resolve_module_level(module_filters.val, global_min_level.val, source)
}

///|
/// Resolve `source` against package filters by longest matching package path,
/// falling back to `default_level`.
fn resolve_module_level(
  filters : Map[String, Level],
  default_level : Level,
  source : String,
) -> Level {
  if filters.is_empty() {
    return default_level
  }
  let mut prefix = source
  while true {
    match filters.get(prefix) {
      Some(min) => return min
      None => ()
    }
    match prefix.rev_split_once("/") {
      Some((parent, _)) => prefix = parent.to_owned()
      None => break
    }
  }
  default_level
}

///|
/// Check if a module+level should be logged based on the effective threshold.
///
/// Parameters:
/// * `source` - The package name from SourceLoc
/// * `level` - The log level of the event
///
/// Returns true if the event should be logged, false otherwise
///
fn should_log_module(source : String, level : Level) -> Bool {
  level >= effective_min(source)
}

///|
/// Extract package name from SourceLoc
///
/// SourceLoc::to_string() returns format: "file:start_line:start_column-end_line:end_column@package/name"
/// We need to extract the package part (after the @ sign)
///
/// Parameters:
/// * `loc` - The source location
///
/// Returns the package name, or "unknown" if parsing fails
///
fn extract_package(loc : SourceLoc) -> String {
  match loc.to_string().rev_split_once("@") {
    Some((_, pkg)) => if pkg.is_empty() { "unknown" } else { pkg.to_owned() }
    None => "unknown"
  }
}

///|
/// Extract the file path and start line from a `SourceLoc`, whose string form
/// is `file:start_line:start_column-end_line:end_column@package/name`. The path
/// is relative to the module root. Returns `("", 0)` if parsing fails.
fn extract_file_line(loc : SourceLoc) -> (String, Int32) {
  parse_file_line_text(loc.to_string())
}

///|
fn parse_file_line_text(text : String) -> (String, Int32) {
  let without_package = match text.rev_split_once("@") {
    Some((before, _)) => before
    None => text[:]
  }
  let start = match without_package.rev_split_once("-") {
    Some((before, _)) => before
    None => return ("", 0)
  }
  let file_line = match start.rev_split_once(":") {
    Some((before, _)) => before
    None => return ("", 0)
  }
  match file_line.rev_split_once(":") {
    Some((file, line)) =>
      match parse_line_number(line) {
        Some(n) if !file.is_empty() => (file.to_owned(), n)
        _ => ("", 0)
      }
    None => ("", 0)
  }
}

///|
fn parse_line_number(digits : StringView) -> Int32? {
  if digits.is_empty() {
    return None
  }
  let mut n = 0
  for c in digits {
    if c < '0' || c > '9' {
      return None
    }
    n = n * 10 + (c.to_int() - '0'.to_int())
  }
  Some(n)
}

///|
/// Report whether an event at `level` from the caller's package would reach the
/// installed subscriber after global and module filters. Call arguments are
/// evaluated even when an event is filtered out, so use this to skip building
/// expensive messages or fields. Wrappers should forward their own `loc`.
#callsite(autofill(loc))
pub fn enabled(level : Level, loc~ : SourceLoc) -> Bool {
  global_subscriber.val is Some(_) &&
  should_log_module(extract_package(loc), level)
}
