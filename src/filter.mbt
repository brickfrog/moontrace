///|
/// Global module filter map: package_name -> min_level
let module_filters : Ref[Map[String, Level]] = { val: {} }

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
/// Check if a module+level should be logged based on configured filters
///
/// Parameters:
/// * `source` - The package name from SourceLoc
/// * `level` - The log level of the event
///
/// Returns true if the event should be logged, false otherwise
///
fn should_log_module(source : String, level : Level) -> Bool {
  match module_filters.val.get(source) {
    Some(min) => level >= min
    None => true // no filter = allow all (global min_level still applies)
  }
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
  let s = loc.to_string()
  // Scan from the end so we intentionally use the last '@' delimiter.
  let mut i = s.length() - 1
  while i >= 0 {
    if s[i] == '@' {
      let at_pos = i + 1
      if at_pos >= s.length() {
        return "unknown"
      }
      return s[at_pos:].to_string()
    }
    i = i - 1
  }
  "unknown"
}
