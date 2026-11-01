///|
fn timed_span(
  name : String,
  duration_ms : UInt64,
  kind~ : @moontrace.SpanKind = @moontrace.Internal,
  error~ : Bool = false,
) -> @moontrace.Span {
  let span = @moontrace.span(name, kind~)
  span.start_time = 1_000UL
  span.end_time = 1_000UL + duration_ms
  if error {
    span.set_status(@moontrace.SpanError, message=Some("boom"))
  }
  span
}

///|
test "span metrics count requests, errors, and durations per name and kind" {
  let metrics = @metrics.span_metrics(buckets_ms=[10UL, 100UL])
  metrics.record(timed_span("GET /users", 5UL, kind=@moontrace.Server))
  metrics.record(timed_span("GET /users", 10UL, kind=@moontrace.Server))
  metrics.record(
    timed_span("GET /users", 250UL, kind=@moontrace.Server, error=true),
  )
  metrics.record(timed_span("GET /users", 20UL, kind=@moontrace.Client))
  metrics.record(timed_span("db.query", 50UL))
  let snapshot = metrics.snapshot()
  assert_eq(snapshot.map(s => "\{s.name}/\{s.kind}"), [
    "GET /users/CLIENT", "GET /users/SERVER", "db.query/INTERNAL",
  ])
  let server = snapshot[1]
  assert_eq(server.count, 3L)
  assert_eq(server.errors, 1L)
  assert_eq(server.duration_sum_ms, 265UL)
  assert_eq(server.duration_min_ms, 5UL)
  assert_eq(server.duration_max_ms, 250UL)
  assert_eq(server.bucket_bounds_ms, [10UL, 100UL])
  // 5 and 10 are <= 10 (bounds are inclusive), 250 overflows past 100.
  assert_eq(server.bucket_counts, [2L, 0L, 1L])
}

///|
test "custom buckets are sorted and de-duplicated" {
  let metrics = @metrics.span_metrics(buckets_ms=[100UL, 10UL, 100UL])
  metrics.record(timed_span("op", 100UL))
  let series = metrics.snapshot()[0]
  assert_eq(series.bucket_bounds_ms, [10UL, 100UL])
  assert_eq(series.bucket_counts, [0L, 1L, 0L])
  assert_eq(@metrics.span_metrics().snapshot().length(), 0)
  assert_eq(@metrics.default_duration_buckets_ms.length(), 15)
}

///|
test "the observer records completed sampled spans only" {
  let metrics = @metrics.span_metrics()
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_observer(metrics.observer())
    let done = @moontrace.span("done")
    done.enter()
    done.exit()
    let open = @moontrace.span("open")
    open.enter()
    @moontrace.with_span_sampler(@moontrace.always_off_sampler(), () => {
      let dropped = @moontrace.span("dropped")
      dropped.enter()
      dropped.exit()
    })
  })
  assert_eq(metrics.snapshot().map(s => s.name), ["done"])
}

///|
test "snapshots are copies and reset clears series" {
  let metrics = @metrics.span_metrics(buckets_ms=[10UL])
  metrics.record(timed_span("op", 1UL))
  let before = metrics.snapshot()
  metrics.record(timed_span("op", 1UL))
  assert_eq(before[0].count, 1L)
  assert_eq(before[0].bucket_counts, [1L, 0L])
  assert_eq(metrics.snapshot()[0].count, 2L)
  metrics.reset()
  assert_eq(metrics.snapshot().length(), 0)
}

///|
test "series snapshots serialize to JSON" {
  let metrics = @metrics.span_metrics(buckets_ms=[10UL])
  metrics.record(timed_span("op", 3UL, error=true))
  assert_eq(
    metrics.snapshot()[0].to_json().stringify(),
    "{\"name\":\"op\",\"kind\":\"INTERNAL\",\"count\":1,\"errors\":1,\"duration_ms\":{\"sum\":3,\"min\":3,\"max\":3},\"histogram\":{\"bounds_ms\":[10],\"counts\":[1,0]}}",
  )
}

///|
test "level-disabled spans are not counted; unleveled spans always are" {
  let metrics = @metrics.span_metrics()
  @moontrace.with_trace_state(() => {
    @moontrace.set_min_level(@moontrace.Info)
    @moontrace.set_span_observer(metrics.observer())
    let quiet = @moontrace.span("quiet", level=@moontrace.Debug)
    quiet.enter()
    quiet.exit()
    let plain = @moontrace.span("plain")
    plain.enter()
    plain.exit()
  })
  assert_eq(metrics.snapshot().map(s => s.name), ["plain"])
}
