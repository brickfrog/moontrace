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
  let filters = module_filters.val
  if filters.is_empty() {
    return global_min_level.val
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
  global_min_level.val
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
/// Report whether an event at `level` from the caller's package would reach the
/// installed subscriber after global and module filters. Call arguments are
/// evaluated even when an event is filtered out, so use this to skip building
/// expensive messages or fields. Wrappers should forward their own `loc`.
#callsite(autofill(loc))
pub fn enabled(level : Level, loc~ : SourceLoc) -> Bool {
  global_subscriber.val is Some(_) &&
  should_log_module(extract_package(loc), level)
}
