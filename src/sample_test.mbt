///|
fn sample_test_event(
  message : String,
  fields? : Array[@moontrace.Field] = [],
) -> @moontrace.Event {
  @moontrace.Event::{
    level: @moontrace.Info,
    message,
    fields,
    timestamp: 123UL,
    source: "brickfrog/moontrace",
  }
}

///|
fn sample_rand_sequence(values : Array[Double]) -> () -> Double {
  let mut index = 0
  fn() {
    let value = values[index]
    index = index + 1
    value
  }
}

///|
fn sample_field_value(event : @moontrace.Event, key : String) -> Json? {
  let mut found : Json? = None
  event.fields.each(fn(field) {
    if field.key == key {
      found = Some(field.value)
    }
  })
  found
}

///|
fn assert_sample_field(
  event : @moontrace.Event,
  key : String,
  expected : Json,
) -> Unit {
  match sample_field_value(event, key) {
    Some(actual) =>
      if actual.stringify() != expected.stringify() {
        abort("field \{key} did not match expected value")
      }
    None => abort("missing field \{key}")
  }
}

///|
test "ratio sampler uses injected random source and counts kept and dropped" {
  let captured : Array[@moontrace.Event] = []
  let sampler = @moontrace.ratio_sampler(
    fn(event) { captured.push(event) },
    0.5,
    rand=sample_rand_sequence([0.1, 0.8, 0.49, 0.5]),
  )
  let subscriber = sampler.subscriber()

  subscriber(sample_test_event("keep-low"))
  subscriber(sample_test_event("drop-high"))
  subscriber(sample_test_event("keep-under"))
  subscriber(sample_test_event("drop-equal"))

  assert_eq(captured.length(), 2)
  assert_eq(captured[0].message, "keep-low")
  assert_eq(captured[1].message, "keep-under")
  assert_eq(sampler.kept(), 2)
  assert_eq(sampler.dropped(), 2)
}

///|
test "ratio sampler clamps zero and one edges" {
  let dropped_output : Array[@moontrace.Event] = []
  let drop_all = @moontrace.ratio_sampler(
    fn(event) { dropped_output.push(event) },
    -0.25,
    rand=sample_rand_sequence([0.0, 0.0]),
  )
  let drop_subscriber = drop_all.subscriber()
  drop_subscriber(sample_test_event("drop-one"))
  drop_subscriber(sample_test_event("drop-two"))

  let kept_output : Array[@moontrace.Event] = []
  let keep_all = @moontrace.ratio_sampler(
    fn(event) { kept_output.push(event) },
    1.25,
    rand=sample_rand_sequence([0.99, 0.99]),
  )
  let keep_subscriber = keep_all.subscriber()
  keep_subscriber(sample_test_event("keep-one"))
  keep_subscriber(sample_test_event("keep-two"))

  assert_eq(dropped_output.length(), 0)
  assert_eq(drop_all.kept(), 0)
  assert_eq(drop_all.dropped(), 2)
  assert_eq(kept_output.length(), 2)
  assert_eq(keep_all.kept(), 2)
  assert_eq(keep_all.dropped(), 0)
}

///|
test "rate limiter keeps limit per fixed window then resets" {
  let captured : Array[@moontrace.Event] = []
  let mut now = 100UL
  let limiter = @moontrace.rate_limiter(
    fn(event) { captured.push(event) },
    2,
    10UL,
    clock=fn() { now },
  )
  let subscriber = limiter.subscriber()

  subscriber(sample_test_event("one"))
  subscriber(sample_test_event("two"))
  subscriber(sample_test_event("three"))
  now = 110UL
  subscriber(sample_test_event("next-window"))

  assert_eq(captured.length(), 3)
  assert_eq(captured[0].message, "one")
  assert_eq(captured[1].message, "two")
  assert_eq(captured[2].message, "next-window")
  assert_eq(limiter.kept(), 3)
  assert_eq(limiter.dropped(), 1)
}

///|
test "trace sampling predicate is deterministic and clamps edges" {
  let trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"
  assert_true(!@moontrace.should_sample_trace(trace_id, 0.0))
  assert_true(@moontrace.should_sample_trace(trace_id, 1.0))

  let first = @moontrace.should_sample_trace(trace_id, 0.5)
  let second = @moontrace.should_sample_trace(trace_id, 0.5)
  assert_eq(first, second)
}

///|
test "parent trace flags override head sampling and none falls back" {
  let trace_id = "4bf92f3577b34da6a3ce929d0e0e4736"
  assert_true(
    @moontrace.sample_trace_decision(
      Some(@moontrace.trace_flags_sampled()),
      trace_id,
      0.0,
    ),
  )
  assert_true(
    !@moontrace.sample_trace_decision(
      Some(@moontrace.trace_flags_unsampled()),
      trace_id,
      1.0,
    ),
  )
  assert_eq(
    @moontrace.sample_trace_decision(None, trace_id, 0.5),
    @moontrace.should_sample_trace(trace_id, 0.5),
  )
}

///|
test "trace sampler drops unsampled traced events and passes untraced events" {
  let captured : Array[@moontrace.Event] = []
  let sampler = @moontrace.trace_sampler(
    fn(event) { captured.push(event) },
    0.0,
  )
  let subscriber = sampler.subscriber()
  let traced = sample_test_event("traced", fields=[
    @moontrace.field("trace_id", "4bf92f3577b34da6a3ce929d0e0e4736"),
  ])
  let untraced = sample_test_event("untraced")

  subscriber(traced)
  subscriber(untraced)

  assert_eq(captured.length(), 1)
  assert_eq(captured[0].message, "untraced")
  assert_eq(sampler.kept(), 1)
  assert_eq(sampler.dropped(), 1)
}

///|
test "samplers forward the original event without mutation" {
  let captured : Array[@moontrace.Event] = []
  let event = sample_test_event("unchanged", fields=[
    @moontrace.field("trace_id", "4bf92f3577b34da6a3ce929d0e0e4736"),
    @moontrace.field("password", "secret"),
  ])
  let sampler = @moontrace.ratio_sampler(
    fn(forwarded) { captured.push(forwarded) },
    1.0,
    rand=sample_rand_sequence([0.99]),
  )

  sampler.subscriber()(event)

  assert_eq(captured.length(), 1)
  assert_eq(captured[0].message, event.message)
  assert_eq(captured[0].fields.length(), event.fields.length())
  assert_sample_field(
    captured[0],
    "trace_id",
    "4bf92f3577b34da6a3ce929d0e0e4736".to_json(),
  )
  assert_sample_field(captured[0], "password", "secret".to_json())
}

///|
test "samplers compose with compose and redact layers" {
  let sampled : Array[@moontrace.Event] = []
  let side_channel : Array[String] = []
  let sampler = @moontrace.ratio_sampler(
    @moontrace.redact(fn(event) { sampled.push(event) }),
    1.0,
    rand=sample_rand_sequence([0.0]),
  )
  let composed = @moontrace.compose([
    sampler.subscriber(),
    fn(event) { side_channel.push(event.message) },
  ])

  composed(
    sample_test_event("login", fields=[
      @moontrace.field("user", "ada"),
      @moontrace.field("password", "secret"),
    ]),
  )

  assert_eq(sampled.length(), 1)
  assert_eq(side_channel.length(), 1)
  assert_eq(side_channel[0], "login")
  assert_eq(sampler.kept(), 1)
  assert_eq(sampler.dropped(), 0)
  assert_sample_field(sampled[0], "user", "ada".to_json())
  assert_sample_field(sampled[0], "password", "[REDACTED]".to_json())
}
