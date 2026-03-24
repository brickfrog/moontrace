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
  // One-liner setup with console output
  @console.initialize()

  // Structured events
  @moontrace.info("server started", fields=@moontrace.fields([("port", (8080).to_json())]))
  @moontrace.warn("slow query", fields=@moontrace.fields([("ms", (250).to_json())]))

  // Spans with duration tracking
  @moontrace.with_span("handle_request", fn() {
    @moontrace.info("processing")
  })
}
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
  fields=@moontrace.fields([
    ("method", "GET".to_json()),
    ("path", "/api/users".to_json()),
    ("status", (200).to_json()),
  ]))
```

## Spans

Spans track operations with enter/exit lifecycle and duration:

```moonbit
// Manual span control
let s = @moontrace.span("db_query")
  .with_field("table", "users".to_json())
  .with_field("limit", (100).to_json())
s.enter()
// ... do work ...
s.record("rows", (42).to_json())  // add fields after creation
s.exit()
// s.duration() returns elapsed nanoseconds
```

### Convenience Wrappers

```moonbit
// Auto enter/exit
@moontrace.with_span("operation", fn() {
  @moontrace.info("inside span")
})

// Access the span inside the closure
@moontrace.with_span_ctx("operation", fn(span) {
  span.record("result", "ok".to_json())
})

// Nested spans with parent linking
@moontrace.with_span_ctx("parent_op", fn(parent) {
  @moontrace.with_child_span(parent, "child_op", fn(_child) {
    @moontrace.info("in child span")
  })
})
```

### Async Span Propagation

MoonBit has no task-local storage, so spans must be passed explicitly across async boundaries. Use `with_span_ctx` and `with_child_span`:

```moonbit
@moontrace.with_span_ctx("request", fn(parent) {
  // Pass parent span to async work explicitly
  async_work(parent)
})

pub async fn async_work(parent : @moontrace.Span) -> Unit {
  @moontrace.with_child_span(parent, "async_step", fn(_s) {
    // ... async work ...
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

### JSON Subscriber

Machine-readable JSON output:

```moonbit
@json.initialize()
// or with options:
@moontrace.set_subscriber(@json.subscriber(min_level=@moontrace.Warn))
```

### Console Subscriber

Human-readable colored output:

```moonbit
@console.initialize()
// or with options:
@moontrace.set_subscriber(@console.subscriber(
  min_level=@moontrace.Info,
  color=true,
))
```

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

// Tap (side-effect without replacing subscriber)
@moontrace.set_subscriber(@moontrace.tap(
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

## Serialization

Events, spans, and fields all support JSON serialization:

```moonbit
let event_json = event.to_json().stringify()
let span_json = span.to_json().stringify()
```

And human-readable formatting:

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
