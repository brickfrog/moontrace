///|
test "counters accumulate per attribute set and ignore negatives" {
  let m = @metrics.meter(clock=() => 1000UL)
  let requests = m.counter("http.requests", unit="1", description="Requests")
  requests.add(1.0, attributes=[@moontrace.field("route", "/a")])
  requests.add(2.0, attributes=[@moontrace.field("route", "/a")])
  requests.add(5.0, attributes=[@moontrace.field("route", "/b")])
  requests.add(-3.0, attributes=[@moontrace.field("route", "/a")])
  requests.add(1.0)
  let data = m.collect()[0]
  assert_eq(data.name, "http.requests")
  assert_true(data.kind is MonotonicSum)
  assert_eq(data.points.map(p => p.value), [1.0, 3.0, 5.0])
  assert_eq(data.points[0].attributes.length(), 0)
}

///|
test "attribute sets are order-insensitive and last value wins" {
  let m = @metrics.meter(clock=() => 0UL)
  let c = m.counter("c")
  c.add(1.0, attributes=[@moontrace.field("a", 1), @moontrace.field("b", 2)])
  c.add(1.0, attributes=[@moontrace.field("b", 2), @moontrace.field("a", 1)])
  c.add(1.0, attributes=[
    @moontrace.field("a", 9),
    @moontrace.field("b", 2),
    @moontrace.field("a", 1),
  ])
  let points = m.collect()[0].points
  assert_eq(points.length(), 1)
  assert_eq(points[0].value, 3.0)
  assert_eq(points[0].attributes.map(f => f.key), ["a", "b"])
}

///|
test "up-down counters go both ways and skip NaN" {
  let m = @metrics.meter(clock=() => 0UL)
  let in_flight = m.up_down_counter("in_flight")
  in_flight.add(3.0)
  in_flight.add(-1.0)
  in_flight.add(0.0 / 0.0)
  let data = m.collect()[0]
  assert_true(data.kind is NonMonotonicSum)
  assert_eq(data.points[0].value, 2.0)
}

///|
test "histograms bucket inclusively and track count, sum, min, max" {
  let m = @metrics.meter(clock=() => 0UL)
  let latency = m.histogram("latency", unit="ms", bounds=[100.0, 10.0, 10.0])
  for v in [5.0, 10.0, 50.0, 500.0] {
    latency.record(v)
  }
  latency.record(0.0 / 0.0)
  let data = m.collect()[0]
  assert_eq(data.bucket_bounds, [10.0, 100.0])
  let point = data.points[0]
  assert_eq(point.count, 4L)
  assert_eq(point.value, 565.0)
  assert_eq(point.min, 5.0)
  assert_eq(point.max, 500.0)
  assert_eq(point.bucket_counts, [2L, 1L, 1L])
}

///|
test "collect returns cumulative copies with start and collection times" {
  let now = Ref(1000UL)
  let m = @metrics.meter(clock=() => now.val)
  let c = m.counter("c")
  let _unused = m.counter("unused")
  c.add(1.0)
  now.val = 2000UL
  let first = m.collect()
  c.add(1.0)
  assert_eq(first[0].points[0].value, 1.0)
  assert_eq(first[0].start_time_ms, 1000UL)
  assert_eq(first[0].time_ms, 2000UL)
  assert_eq(first[1].points.length(), 0)
  assert_eq(m.collect()[0].points[0].value, 2.0)
}

///|
test "to_otlp_json builds an ExportMetricsServiceRequest" {
  let m = @metrics.meter(name="svc", version="1.0", clock=() => 2UL)
  m
  .counter("reqs", unit="1")
  .add(3.0, attributes=[@moontrace.field("ok", true)])
  m.up_down_counter("active").add(-1.0)
  m.histogram("lat", bounds=[10.0]).record(4.0)
  let json = m.to_otlp_json(resource=@otlp.resource(service_name="api"))
  assert_eq(
    json.stringify(),
    "{\"resourceMetrics\":[{\"resource\":{\"attributes\":[{\"key\":\"service.name\",\"value\":{\"stringValue\":\"api\"}}]},\"scopeMetrics\":[{\"scope\":{\"name\":\"svc\",\"version\":\"1.0\",\"attributes\":[]},\"metrics\":[{\"name\":\"reqs\",\"unit\":\"1\",\"sum\":{\"dataPoints\":[{\"attributes\":[{\"key\":\"ok\",\"value\":{\"boolValue\":true}}],\"startTimeUnixNano\":\"2000000\",\"timeUnixNano\":\"2000000\",\"asDouble\":3}],\"aggregationTemporality\":2,\"isMonotonic\":true}},{\"name\":\"active\",\"sum\":{\"dataPoints\":[{\"attributes\":[],\"startTimeUnixNano\":\"2000000\",\"timeUnixNano\":\"2000000\",\"asDouble\":-1}],\"aggregationTemporality\":2,\"isMonotonic\":false}},{\"name\":\"lat\",\"histogram\":{\"dataPoints\":[{\"attributes\":[],\"startTimeUnixNano\":\"2000000\",\"timeUnixNano\":\"2000000\",\"count\":\"1\",\"sum\":4,\"bucketCounts\":[\"1\",\"0\"],\"explicitBounds\":[10],\"min\":4,\"max\":4}],\"aggregationTemporality\":2}}]}]}]}",
  )
}

///|
test "series attributes are isolated from callers and snapshots" {
  let m = @metrics.meter(clock=() => 0UL)
  let c = m.counter("c")
  let tags : Json = ["a"]
  c.add(1.0, attributes=[@moontrace.field("tags", tags)])
  if tags is Array(items) {
    items.push(Json("caller-mutated"))
  }
  let first = m.collect()
  if first[0].points[0].attributes[0].value is Array(items) {
    items.push(Json("snapshot-mutated"))
  }
  let second = m.collect()
  assert_eq(second[0].points[0].attributes[0].value, Json(["a"]))
  c.add(1.0, attributes=[@moontrace.field("tags", ["a"])])
  assert_eq(m.collect()[0].points.length(), 1)
  assert_eq(m.collect()[0].points[0].value, 2.0)
}
