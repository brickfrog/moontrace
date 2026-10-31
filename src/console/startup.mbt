///|
/// Set up application logging with Info as the default filter and stderr output.
/// MOONTRACE_LOG (or env_var) replaces the global and package filters. Missing
/// or blank values select Info with no package overrides. Invalid filters leave
/// all tracing state unchanged.
///
/// Explicit color wins. Otherwise color requires stderr to be a terminal,
/// NO_COLOR to be unset/empty, and TERM not to be "dumb". Custom outputs default
/// to plain text. On wasm-gc, the runtime's eprintln falls back to stdout; supply
/// output to route records through a host-specific error stream instead.
/// `location=true` appends each event's `file:line`.
pub fn initialize_from_env(
  env_var~ : String = "MOONTRACE_LOG",
  color? : Bool,
  output? : (String) -> Unit,
  location~ : Bool = false,
) -> Result[Unit, @moontrace.EnvFilterError] {
  configure_startup(
    @env.get_env_var,
    stderr_is_terminal,
    env_var,
    color,
    output,
    location~,
  )
}

///|
fn startup_color(
  explicit : Bool?,
  custom_output : Bool,
  read_env : (String) -> String?,
  terminal : () -> Bool,
) -> Bool {
  match explicit {
    Some(value) => value
    None => {
      if custom_output {
        return false
      }
      if read_env("NO_COLOR") is Some(value) && !value.is_empty() {
        return false
      }
      if read_env("TERM") == Some("dumb") {
        return false
      }
      terminal()
    }
  }
}

///|
fn configure_startup(
  read_env : (String) -> String?,
  terminal : () -> Bool,
  env_var : String,
  color : Bool?,
  output : ((String) -> Unit)?,
  location~ : Bool = false,
) -> Result[Unit, @moontrace.EnvFilterError] {
  let directive = read_env(env_var).unwrap_or("")
  let parsed = match @moontrace.parse_env_filter(directive) {
    Ok(parsed) => parsed
    Err(err) => return Err(err)
  }
  let use_color = startup_color(color, output is Some(_), read_env, terminal)
  let sink = match output {
    Some(sink) => sink
    None => fn(line) { eprintln(line) }
  }
  // Keep the subscriber's floor at Trace so a package override can be more
  // verbose than the global default. Parsing completes before either mutation.
  let installed = subscriber(
    min_level=@moontrace.Trace,
    color=use_color,
    output=sink,
    location~,
  )
  parsed.apply()
  @moontrace.set_subscriber(installed)
  Ok(())
}
