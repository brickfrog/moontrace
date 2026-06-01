# Flame Export

`brickfrog/moontrace/flame` provides an opt-in folded-stack exporter for
flamegraph and flamechart tools such as `inferno-flamegraph` and Brendan Gregg's
`flamegraph.pl`.

The exporter observes completed spans through `@moontrace.set_span_observer`.
It does not parse formatted log strings and it does not maintain a live global
span stack. On `flush()`, it reconstructs parent/child stacks from
`parent_span_id`, computes each span's self time as its duration minus the
duration of direct children, collapses identical stack strings by summing their
self time, sorts lines lexicographically for deterministic output, and clears
the buffer. Stacks with zero self time are omitted. Frame names replace `;` and
ASCII whitespace with `_` so names cannot corrupt the collapsed-stack delimiter.

```moonbit
let exp = @flame.flame_exporter(output=fn(folded) { println(folded) })
@moontrace.set_span_observer(exp.span_observer())

let root = @moontrace.span("request")
root.enter()
let child = @moontrace.child_span(root, "db query")
child.enter()
child.exit()
root.exit()

exp.flush()
@moontrace.clear_span_observer()
```

Write the folded output to a file, then render it with your flamegraph tool:

```sh
moon run src/cmd/main --target native > trace.folded
inferno-flamegraph trace.folded > flame.svg
```

The same folded file works with `flamegraph.pl`:

```sh
moon run src/cmd/main --target native > trace.folded
flamegraph.pl trace.folded > flame.svg
```
