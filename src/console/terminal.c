#include <moonbit.h>
#include <stdio.h>
#ifdef _WIN32
#include <io.h>
#else
#include <unistd.h>
#endif

MOONBIT_FFI_EXPORT
int moontrace_console_stderr_is_terminal(void) {
#ifdef _WIN32
  return _isatty(_fileno(stderr));
#else
  return isatty(STDERR_FILENO);
#endif
}
