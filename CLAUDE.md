# moontrace

Structured tracing for MoonBit — spans, structured fields, pluggable subscribers.

Inspired by Rust's `tracing` crate (tokio-rs/tracing) and loguru's DX. Not a port of either — designed for MoonBit's type system and async model.

## Why This Exists

MoonBit has no structured logging. The stdlib has `println` and `@debug` (repr dumping). Every MoonBit project hand-rolls `println("[component] message")` or builds ad-hoc JSON span formatters. moontrace replaces all of that with a proper instrumentation API.

## Design Principles

1. **Instrumentation separate from output** — libraries call `@moontrace.info(...)`, applications choose subscribers (JSON, console, OTLP). Same pattern as Rust's tracing.
2. **Spans are first-class** — not just log levels. A span has enter/exit, duration, nested context. Events happen inside spans.
3. **Structured fields, not string interpolation** — `info("dispatched", tool="fork_wave", agent="root")` not `println("[tool] fork_wave agent=root")`.
4. **Zero config for simple cases** — `@moontrace.init()` with console output should work in one line.
5. **MoonBit-native** — use the type system. Derive traits for field extraction. Don't fight the language.

## Architecture

```
moontrace/          # core instrumentation API (zero deps beyond stdlib)
  span.mbt          # Span type, enter/exit, context propagation
  event.mbt         # info/debug/warn/error event constructors
  field.mbt         # structured field types and Field trait
  subscriber.mbt    # Subscriber trait, global subscriber registry

moontrace/json/     # JSON subscriber (structured output to stderr/file)
moontrace/console/  # Pretty console subscriber (colored, human-readable)
moontrace/otlp/     # OpenTelemetry export (future)
```

## Package Structure (mooncakes)

```
@moontrace            # core — what libraries depend on
@moontrace/json       # what applications add for JSON output
@moontrace/console    # what applications add for pretty output
```

Libraries instrument with `@moontrace`. Applications pick subscribers.

## API Sketch

```moonbit
// Events — fire-and-forget structured log entries
@moontrace.info("tool dispatched", fields={"tool": "fork_wave", "agent": "root"})
@moontrace.warn("retry", fields={"attempt": 3, "max": 5})
@moontrace.error("delivery failed", fields={"target": "leaf-1", "exit_code": 2})

// Spans — enter/exit with duration tracking
let span = @moontrace.span("poller_tick", fields={"tracked_prs": 3})
span.enter()
// ... work ...
span.exit()

// Subscriber setup (application-level)
@moontrace.set_subscriber(@moontrace_json.subscriber(output=Stderr))
// or
@moontrace.set_subscriber(@moontrace_console.subscriber(min_level=Info))
```

## MoonBit Idioms to Follow

### Visibility
- `pub` types: visible but read-only from other packages (can match, can't construct)
- `pub(all)` types: fully constructable — use for anything subscribers need to create
- Core instrumentation types should be `pub(all)` so subscribers can work with them

### Json constructors are read-only
- Can't write `Json::String("x")` from outside builtin — use `"x".to_json()`
- `(42).to_json()` not `42.to_json()` (integer literal gotcha)
- `Map[String, Json].to_json()` wraps in `Json::Object` via identity conversion
- Pattern matching on Json works fine: `guard json is Object(obj)`

### Error handling
- `Result[T, E]` with explicit `match`, no `?` operator
- `catch` is for `raise` (suberror), not for `Result`
- Use `try { ... } catch { e => ... }` for async operations

### Package naming
- Don't name packages `io` — conflicts with `moonbitlang/async/io`
- MoonBit's moon.pkg DSL has no import alias syntax
- If two packages want the same short name, rename yours

### Async pitfalls
- `@process.run` with `stdout=pipe` deadlocks — use `spawn_orphan` + read + `wait_pid`
- `@process.collect_stdout` uses nested `with_task_group` — deadlocks inside `spawn_bg`
- Blocking C FFI (`system()`) inside async context blocks the entire event loop
- `@async.sleep` yields correctly but `@process.run` awaiting child exit does not yield while pipe buffer is full

### Testing
- `moon test --target native` for unit tests
- `moon build --target native --release` for release binary (symlinks may point to release path)
- `moon build` alone targets debug — don't forget `--release` if binary path matters
- Test files (`*_test.mbt`) are auto-discovered as black-box tests
- `assert_eq(a, b)` not `assert_eq!(a, b)`

### Formatting
- `moon fmt` before commit, always
- Adds `///|` markers before definitions — this is normal
- Converts `fn(_)` arrow syntax automatically

## Known Hard Problems

1. **Async span propagation** — MoonBit has no task-local storage. Spans can't automatically propagate across `@async.sleep` boundaries. Options: explicit span passing (verbose but correct), global span stack (fragile under concurrency), or punt and require manual context.

2. **Zero-cost disabled spans** — No compile-time macros in MoonBit. Every log call allocates even if no subscriber is listening. Can mitigate with a global level check before allocation, but can't eliminate the function call overhead.

3. **Subscriber composition** — Multiple subscribers with different level filters need a dispatch layer. Not hard but must be designed upfront.

## Development Rules

- `moon fmt` before committing
- `moon test` must pass
- Immutable by default, explicit `mut` only where needed
- Pattern matching over conditionals
- No hand-rolled JSON — use `.to_json().stringify()`
- Test round-trips for any serialization

## First Milestone

Ship the "easy weekend" version:
- Event struct with level, message, fields (`Map[String, Json]`)
- `info/debug/warn/error` functions
- Global subscriber slot
- JSON subscriber (to stderr)
- Console subscriber (human-readable, colored if terminal)
- Publish to mooncakes

Then iterate with spans, context propagation, OTLP.

## Acknowledgements

Architecture informed by:
- [tokio-rs/tracing](https://github.com/tokio-rs/tracing) — span model, subscriber pattern
- [loguru](https://github.com/Delgan/loguru) — developer experience, sensible defaults
- choir (github.com/brickfrog/choir) — the production codebase driving requirements
