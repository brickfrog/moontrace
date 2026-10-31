# Moontrace contributor guide

Moontrace provides structured tracing for [MoonBit](https://docs.moonbitlang.com).
Libraries emit events and create spans; applications choose subscribers. Keep
instrumentation separate from output, use structured `Field` values, and keep
request and async context explicit.

## Repository layout

- `moon.mod` contains module metadata and dependencies; `src/` is the source root.
- Each package directory has a `moon.pkg`. Its `.mbt` files share one package.
- `src/` contains events, fields, levels, spans, bound loggers, filters, context,
  subscriber composition, sampling, and redaction. Subscribers are
  `(Event) -> Unit` functions, not a trait; `emit` is package-private.
- `src/console/`, `src/json/`, and `src/logfmt/` provide console, JSON, and
  logfmt subscribers.
- `src/otlp/` handles OTLP conversion and buffering; `src/otlp/transport/` handles
  async HTTP transport and JSON/protobuf encoding.
- `src/span_async/` provides async span wrappers; `src/flame/` observes completed
  spans; `src/file/` provides the native buffered file subscriber.
- `src/test/` provides test subscribers and assertion helpers. `*_test.mbt`
  files are blackbox tests; `*_wbtest.mbt` files can access package internals.
- See [README.mbt.md](README.mbt.md) for usage and the guides in [docs](docs).

## Development and validation

- Match the MoonBit version pinned in [.github/scripts/setup-moonbit.sh](.github/scripts/setup-moonbit.sh).
  That script expects GitHub Actions environment variables; it is not a generic
  local installer. Use the pinned toolchain and run `moon update` for dependencies.
- Run `moon info --target native && moon fmt` after changes. Review generated
  `pkg.generated.mbti` diffs and include intended API changes. Unchanged interfaces
  do not guarantee unchanged behavior.
- Run `moon test --target native`; for cross-backend changes also check and test
  `--target js` and `--target wasm-gc`, as [.github/workflows/ci.yml](.github/workflows/ci.yml) does.
  Native transport tests use synthetic localhost fixtures.
- Specify `--target native` for native builds; `--release` independently selects
  release mode, for example `moon build --target native --release`.
- Format before committing. The optional [.githooks/pre-commit](.githooks/pre-commit)
  hook checks formatting and runs `moon check --target native`.
- Prefer assertions for stable behavior; use snapshots for output representations.
  Update snapshots intentionally with `moon test --target native --update`.
  Test serialization round trips. `moon coverage analyze` can identify gaps.
- Compile changed runnable documentation examples with their actual package
  imports. Preserve caller metadata and verify examples against generated APIs.
- `moon ide` provides navigation such as `peek-def`, `outline`, and `find-references`.
  Additional MoonBit skills are available at <https://github.com/moonbitlang/skills>.

## MoonBit conventions

- Keep `///|` block markers; `moon fmt` adds them. Prefer immutable bindings,
  explicit `mut` where required, and pattern matching for variant handling.
  Keep deprecated definitions in `deprecated.mbt` where practical.
- `pub(all)` permits construction outside the package. Use it where consumers
  need to construct instrumentation values; use private fields for protected
  state such as `Logger` and `TraceState`.
- Defaulted labeled parameters use `fields~ : Array[Field] = []`; optional values
  use `span? : Span`. Calls use `fields=value`, or `fields~` to forward a binding.
- Generic parameters follow `fn`: `pub fn[T] name(...) -> T`.
- Use `Json(value)` or `field(key, value)` with the pinned toolchain. Read-only
  JSON variants cannot be constructed as `Json::String(...)` from another
  package, but can be pattern-matched. Build JSON structurally and serialize
  with `.stringify()`; do not hand-roll JSON text.
- Handle `Result` with `match`; use `catch` for raised errors. Preserve `raise?`
  polymorphism on synchronous wrappers when non-raising callers must remain so.
- Use `assert_eq(a, b)`, not a macro-style `assert_eq!(a, b)`.
- Alias imports when short names conflict. Avoid naming a package `io` when
  using `moonbitlang/async/io`; `span_async` avoids clashing with `@async`.

## State and async behavior

- Use `with_trace_state` or its scoped helpers to restore synchronous test state,
  including subscriber, observer, filters, and global fields. Merely clearing a
  subscriber does not restore all state. Async tests must restore state on exit
  without treating a synchronous guard as task-local storage.
- Pass `Span` or `Logger` explicitly across async boundaries. There is no implicit
  current-span stack or automatic task-local propagation. Use `span_async`
  wrappers for callbacks that suspend; synchronous wrappers accept sync callbacks.
- Avoid blocking C calls on the async event loop. Drain piped process output
  concurrently with waiting for completion so full pipes cannot deadlock work.
- Preserve snapshot isolation where promised, including bound logger JSON and
  completed-span observations. Do not assume all existing event arrays are deep
  copies. Caller arguments are evaluated even when logging is filtered out.

## Design decisions to preserve

- `Level`, `SpanKind`, and `SpanStatus` have manual uppercase `Show`/string output;
  do not replace it with variant-name formatting. `Error_` is intentional.
  Levels order as `Trace < Debug < Info < Warn < Error_`.
- `merge_fields` uses a map for key collisions. Keep this clear rather than
  micro-optimizing small field lists. Explicit event fields override global fields.
- `field()` and `fields()` coexist: the former uses `ToJson`, the latter accepts
  pairs containing raw JSON. Neither replaces the other.
- Setting a non-error status without a message clears an old status message.
  `message=Some("")` is a valid explicit empty message.
- `intercept(inner, callback)` runs the callback before the subscriber. Use
  `compose()` for fan-out; preserve this ordering.
- Blackbox `SourceLoc` reports the package under test, not a synthetic
  `_blackbox_test` suffix. Forward call-site metadata through wrappers so module
  filters use the caller's package.
- Span-associated events protect correlation IDs from supplied-field overrides;
  subscriber redaction still runs afterward. Bound loggers preserve explicit
  parent/child isolation and do not manage span lifetimes.

Architecture draws on Rust's [tracing](https://github.com/tokio-rs/tracing),
[loguru](https://github.com/Delgan/loguru), and requirements from
[choir](https://github.com/brickfrog/choir).
