# MoonBit review instructions for moontrace

Follow [AGENTS.md](../../AGENTS.md) for repository layout, language conventions,
state handling, design decisions, and validation. It is the shared contributor
guide; avoid duplicating its rules here.

MoonBit is not Rust, Go, or TypeScript. Check proposed syntax against the pinned
toolchain and generated interfaces rather than assuming another language's rules.

Review for:

- Mutation aliasing where snapshots are promised, especially bound logger JSON
  and completed-span observations.
- Restoration of all modified tracing state in tests, including error paths.
- Correct labeled parameters and forwarding of caller `SourceLoc`.
- Generated interface changes when the public API changes.
- Numeric type and unit mismatches, especially timestamps and durations.
- Runnable documentation examples that match the current APIs.

Do not flag `pub(all)`, `///|`, the `Error_` variant, `Ref[T?]` globals, or
same-package functions defined in separate `.mbt` files merely for their form.
