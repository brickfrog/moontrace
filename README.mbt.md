# brickfrog/moontrace

Structured tracing for MoonBit. Spans, structured fields, pluggable subscribers.

Inspired by Rust's [tracing](https://github.com/tokio-rs/tracing) crate and [loguru](https://github.com/Delgan/loguru)'s developer experience.

## Install

```
moon add brickfrog/moontrace
```

## Quick Start

```moonbit
fn main {
  // One-liner setup with colored console output
  @console.initialize()

  // Structured events
  @moontrace.info("server started", fields=[@moontrace.field("port", 8080)])
  @moontrace.warn("slow query", fields=[@moontrace.field("ms", 250)])

  // Spans with duration tracking
  @moontrace.with_span("handle_request", fn() {
    @moontrace.info("processing")
  })
}
```

Output:

```
14:31:43.903 | INFO  | myapp — server started  port=8080
14:31:43.904 | WARN  | myapp — slow query  ms=250
14:31:43.904 | TRACE | moontrace — span.enter handle_request
14:31:43.904 | INFO  | myapp — processing
14:31:43.904 | TRACE | moontrace — span.exit handle_request  duration_ns=12345
```

## Events

Fire-and-forget structured log entries at five levels:

```moonbit
@moontrace.trace("verbose detail")
@moontrace.debug("debugging info")
@moontrace.info("normal operation")
@moontrace.warn("something unexpected")
@moontrace.error("something broke")
```

Attach structured fields to any event:

```moonbit
@moontrace.info("request handled",
  fields=[
    @moontrace.field("method", "GET"),
    @moontrace.field("path", "/api/users"),
    @moontrace.field("status", 200),
  ])
```

The `field()` function uses MoonBit's `ToJson` trait dispatch — any type implementing `ToJson` works. For raw `Json` values, use `fields()` instead.

Every event automatically captures its source package via `SourceLoc`, available as `event.source`.

## Global Context

Set fields once, automatically included in every event:

```moonbit
@moontrace.set_global_field("service", "my-app")
@moontrace.set_global_field("version", "1.2.0")

@moontrace.info("started")  // automatically includes service and version fields
```

Explicit fields override global context on key collision.

```moonbit
@moontrace.remove_global_field("version")  // remove a single field
@moontrace.clear_global_fields()            // remove all
```

## Per-Module Filtering

Filter log levels by package:

```moonbit
@moontrace.set_module_filter("my/db/package", @moontrace.Debug)
@moontrace.set_module_filter("my/http/package", @moontrace.Warn)
```

Module names are extracted automatically from `SourceLoc` at each call site. No manual tagging needed.

## Scoped State Guards

For tests or temporary overrides, wrap work in a synchronous scope:

```moonbit
@moontrace.with_subscriber(collecting_subscriber, fn() {
  @moontrace.with_min_level(@moontrace.Debug, fn() {
    @moontrace.with_global_field("request_id", "abc", fn() {
      @moontrace.debug("captured only inside this scope")
    })
  })
})
```

`with_trace_state(fn() { ... })` snapshots the subscriber, global minimum level,
global context fields, and module filters, then restores them when the closure
returns or raises. The convenience helpers `with_subscriber`, `with_min_level`,
`with_global_field`, `with_global_fields`, and `with_module_filter` use the same
guard, so state changed inside nested scopes restores in LIFO order and does not
leak into later tests.

These guards are synchronous call-stack scopes only. They are not task-local
storage and do not propagate tracing state across async tasks.

## Spans

Spans track operations with enter/exit lifecycle, duration, and distributed tracing IDs:

```moonbit
let s = @moontrace.span("db_query")
  .with_field("table", "users")
  .with_field("limit", 100)
s.enter()
// ... do work ...
s.record("rows", 42)  // add fields after creation
s.exit()
// s.duration() returns elapsed nanoseconds
```

Spans are single-use lifecycles: `exit()` closes a span, and later `enter()`/`exit()` calls on the same span are ignored. Create a new child span for repeated or nested work.

Every span gets auto-generated `trace_id` (32 hex chars) and `span_id` (16 hex chars).

### Error Handling on Spans

```moonbit
@moontrace.with_span_ctx("db_query", fn(s) {
  match run_query() {
    Ok(result) => s.set_status(@moontrace.Ok)
    Err(e) => s.record_error(e.to_string())  // sets SpanError + records error field
  }
})
```

`record_error` sets the span status to `SpanError`, records the error message as a field, and includes both in the span's exit event and JSON output.

### Convenience Wrappers

```moonbit
// Auto enter/exit
@moontrace.with_span("operation", fn() {
  @moontrace.info("inside span")
})

// Access the span inside the closure
@moontrace.with_span_ctx("operation", fn(span) {
  span.record("result", "ok")
})

// Nested spans with parent linking
@moontrace.with_span_ctx("parent_op", fn(parent) {
  @moontrace.with_child_span(parent, "child_op", fn(_child) {
    @moontrace.info("in child span")
  })
})
```

`with_child_span` propagates the parent's `trace_id` and sets `parent_span_id`, linking spans in a trace.

### Cross-Process Trace Correlation

For distributed tracing across process boundaries, inject an existing trace ID:

```moonbit
let s = @moontrace.span_with_trace("handle_request", external_trace_id)
```

### Async Span Propagation

MoonBit has no task-local storage, so spans must be passed explicitly across async boundaries:

```moonbit
@moontrace.with_span_ctx("request", fn(parent) {
  async_work(parent)
})

pub async fn async_work(parent : @moontrace.Span) -> Unit {
  @moontrace.with_child_span(parent, "async_step", fn(_s) {
    // child inherits parent's trace_id
  })
}
```

## Subscribers

Subscribers receive events. Set one globally:

```moonbit
@moontrace.set_subscriber(fn(event) {
  println(event.format())
})
```

### Console Subscriber

Human-readable colored output with timestamps, source, and pipe separators:

```moonbit
@console.initialize()
// or with options:
@moontrace.set_subscriber(@console.subscriber(
  min_level=@moontrace.Info,
  color=true,
))
```

Output:

```
14:31:43.903 | INFO  | server — UDS server listening  path=".choir/server.sock"
14:31:44.012 | WARN  | poller — retry  attempt=3 max=5
14:31:44.500 | ERROR | handler — delivery failed  target="leaf-1" exit_code=2
```

### JSON Subscriber

Machine-readable JSON output:

```moonbit
@json.initialize()
// or with options:
@moontrace.set_subscriber(@json.subscriber(min_level=@moontrace.Warn))
```

### OTLP Export

Convert events and completed spans to OpenTelemetry-compatible JSON:

```moonbit
let exp = @otlp.exporter(
  log_output=fn(json) { send_to_collector(json) },
  span_output=fn(json) { send_to_collector(json) },
  capacity=100,
)
@moontrace.set_subscriber(exp.subscriber())
@moontrace.set_span_observer(exp.span_observer())

let s = @moontrace.span("operation")
s.enter()
// ... work ...
s.exit()
exp.flush()  // send remaining batched data
```

`span_observer()` captures completed spans when they close, without parsing `span.enter` / `span.exit` trace messages or calling `add_span` manually. Manual `add_span(@otlp.span_to_otlp(s))` remains available for spans collected outside the global observer path. The OTLP package handles format conversion (events to log records, spans to OTLP spans with proper severity codes and attributes). You provide the transport.

### Subscriber Composition

Route events to multiple subscribers:

```moonbit
@moontrace.set_subscriber(@moontrace.compose([
  @console.subscriber(min_level=@moontrace.Info),
  @json.subscriber(min_level=@moontrace.Debug),
]))
```

Filter events for any subscriber:

```moonbit
@moontrace.set_subscriber(
  @moontrace.with_filter(@json.subscriber(), @moontrace.Warn)
)
```

### Utility Subscribers

```moonbit
// No-op (for benchmarks/testing)
@moontrace.set_subscriber(@moontrace.noop())

// Intercept (run a side-effect before the main subscriber)
@moontrace.set_subscriber(@moontrace.intercept(
  main_subscriber,
  fn(e) { metrics.increment(e.level.to_string()) },
))
```

### Buffered Subscriber

Batch events and flush on demand or at capacity:

```moonbit
let buf = @moontrace.buffer(@json.subscriber(), capacity=100)
@moontrace.set_subscriber(buf.subscriber())
// ... events are batched ...
buf.flush()  // send all buffered events
```

## Performance

Set a global minimum level to skip event allocation entirely:

```moonbit
@moontrace.set_min_level(@moontrace.Info)
// trace() and debug() calls now short-circuit before allocating Event
```

Global context fields use a fast path — zero allocation overhead when no context is set.

## Serialization

Events, spans, and fields all support JSON serialization:

```moonbit
let event_json = event.to_json().stringify()
let span_json = span.to_json().stringify()
```

Span JSON includes trace_id, span_id, parent_span_id, status, and duration.

Human-readable formatting with the new pipe-separated style:

```moonbit
let plain = event.format()           // no color
let colored = event.format(color=true) // ANSI colored
```

All types implement `Show` for `println` and string interpolation:

```moonbit
println(event)       // human-readable output
let s = "\{span}"    // string interpolation works
```

## Architecture

```
@moontrace           # core — what libraries depend on
@moontrace/json      # JSON subscriber (structured output)
@moontrace/console   # console subscriber (colored, human-readable)
@moontrace/otlp      # OpenTelemetry JSON format conversion
```

Libraries instrument with `@moontrace`. Applications choose subscribers.

## Contributing

Contributions welcome! Please:

1. `moon fmt` before committing
2. `moon test --target native` must pass
3. Run `moon info && moon fmt` if you change public APIs (updates `.mbti` files)
4. Add tests for new features

The pre-commit hook runs `moon fmt` and `moon check` automatically.

### Development

```sh
git clone https://github.com/brickfrog/moontrace
cd moontrace
git config core.hooksPath .githooks
moon test --target native
```

## License

Apache-2.0
