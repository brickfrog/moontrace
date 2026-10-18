///|
#cfg(target="native")
extern "C" fn stderr_is_terminal_ffi() -> Int32 = "moontrace_console_stderr_is_terminal"

///|
#cfg(target="native")
fn stderr_is_terminal() -> Bool {
  stderr_is_terminal_ffi() != 0
}

///|
#cfg(target="js")
extern "js" fn stderr_is_terminal() -> Bool =
  #| () => typeof process !== "undefined" && !!process.stderr && process.stderr.isTTY === true

///|
#cfg(not(any(target="native", target="js")))
fn stderr_is_terminal() -> Bool {
  false
}
