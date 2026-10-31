///|
fn burst_event(
  message : String,
  level~ : @moontrace.Level = @moontrace.Info,
  fields~ : Array[@moontrace.Field] = [],
) -> @moontrace.Event {
  @moontrace.Event::{
    level,
    message,
    fields,
    timestamp: 0UL,
    source: "brickfrog/moontrace",
    file: "",
    line: 0,
  }
}

///|
test "burst sampler keeps first N then every Mth per key" {
  let seen : Array[String] = []
  let sampler = @moontrace.burst_sampler(
    event => seen.push(event.message),
    2,
    3,
    1000UL,
    clock=() => 0UL,
  )
  let sub = sampler.subscriber()
  for i in 1..<=9 {
    sub(burst_event("a\{i}", fields=[]))
  }
  // Each message is its own key, so all nine pass.
  assert_eq(seen.length(), 9)
  seen.clear()
  for _ in 1..<=9 {
    sub(burst_event("same"))
  }
  // Counts 1, 2 (first), then 5 and 8 (every third after first).
  assert_eq(seen.length(), 4)
  assert_eq(sampler.kept(), 13)
  assert_eq(sampler.dropped(), 5)
}

///|
test "burst sampler resets counts each window" {
  let mut now = 0UL
  let seen : Array[String] = []
  let sampler = @moontrace.burst_sampler(
    event => seen.push(event.message),
    1,
    0,
    100UL,
    clock=() => now,
  )
  let sub = sampler.subscriber()
  sub(burst_event("x"))
  sub(burst_event("x"))
  now = 99UL
  sub(burst_event("x"))
  assert_eq(seen.length(), 1)
  now = 100UL
  sub(burst_event("x"))
  sub(burst_event("x"))
  assert_eq(seen.length(), 2)
  assert_eq(sampler.dropped(), 3)
}

///|
test "burst sampler keys default to level and message" {
  let seen : Array[@moontrace.Level] = []
  let sampler = @moontrace.burst_sampler(
    event => seen.push(event.level),
    1,
    0,
    1000UL,
    clock=() => 0UL,
  )
  let sub = sampler.subscriber()
  sub(burst_event("m", level=@moontrace.Info))
  sub(burst_event("m", level=@moontrace.Warn))
  sub(burst_event("m", level=@moontrace.Info))
  assert_eq(seen, [@moontrace.Info, @moontrace.Warn])
}

///|
test "burst sampler accepts a custom key and bounded buckets" {
  let seen : Array[String] = []
  let sampler = @moontrace.burst_sampler(
    event => seen.push(event.message),
    1,
    0,
    1000UL,
    key=_ => "all",
    buckets=1,
    clock=() => 0UL,
  )
  let sub = sampler.subscriber()
  sub(burst_event("a"))
  sub(burst_event("b"))
  assert_eq(seen, ["a"])
}

///|
test "breadcrumbs hold low events until a trigger" {
  let seen : Array[String] = []
  let crumbs = @moontrace.breadcrumbs(
    event => seen.push(event.message),
    capacity=3,
  )
  let sub = crumbs.subscriber()
  sub(burst_event("d1", level=@moontrace.Debug))
  sub(burst_event("i2"))
  assert_eq(seen, [])
  assert_eq(crumbs.len(), 2)
  sub(burst_event("boom", level=@moontrace.Error_))
  assert_eq(seen, ["d1", "i2", "boom"])
  assert_eq(crumbs.len(), 0)
  assert_eq(crumbs.flushed(), 2)
  sub(burst_event("boom2", level=@moontrace.Error_))
  assert_eq(seen, ["d1", "i2", "boom", "boom2"])
}

///|
test "breadcrumbs keep only the most recent events" {
  let seen : Array[String] = []
  let crumbs = @moontrace.breadcrumbs(
    event => seen.push(event.message),
    capacity=2,
    trigger=@moontrace.Warn,
  )
  let sub = crumbs.subscriber()
  for i in 1..<=5 {
    sub(burst_event("e\{i}"))
  }
  assert_eq(crumbs.len(), 2)
  assert_eq(crumbs.dropped(), 3)
  sub(burst_event("warned", level=@moontrace.Warn))
  assert_eq(seen, ["e4", "e5", "warned"])
}

///|
test "breadcrumbs flush, clear, and isolate held fields" {
  let seen : Array[@moontrace.Event] = []
  let crumbs = @moontrace.breadcrumbs(event => seen.push(event))
  let sub = crumbs.subscriber()
  let fields = [@moontrace.field("k", 1)]
  sub(burst_event("held", fields~))
  fields.push(@moontrace.field("late", 2))
  crumbs.flush()
  assert_eq(seen.length(), 1)
  assert_eq(seen[0].fields.length(), 1)

  sub(burst_event("discarded"))
  crumbs.clear()
  assert_eq(crumbs.len(), 0)
  crumbs.flush()
  assert_eq(seen.length(), 1)
}
