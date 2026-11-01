///|
fn ok_replies(count : Int32) -> Array[FakeReply] {
  Array::makei(count, _ => FakeResponse(response(200)))
}

///|
async test "metric reader flush exports each meter with data and skips empty ones" {
  let client = fake_client(ok_replies(4))
  let other = @metrics.meter(name="other")
  other.counter("jobs").add(1.0)
  let empty = @metrics.meter(name="empty")
  ignore(empty.counter("unused"))
  let reader = @transport.periodic_metric_reader(
    @transport.transport(client, "http://collector:4318"),
    [test_meter(), empty, other],
  )
  let stats = @async.with_timeout(1000, () => reader.flush())
  assert_eq(stats.exports, 2L)
  assert_eq(stats.delivered, 2L)
  assert_eq(stats.skipped_empty, 1L)
  assert_eq(client.calls.length(), 2)
  assert_eq(client.calls[0].url, "http://collector:4318/v1/metrics")
  assert_true(client.calls[0].body.contains("\"name\":\"svc\""))
  assert_true(client.calls[1].body.contains("\"name\":\"other\""))
  assert_eq(reader.last_error(), None)
  assert_true(
    reader.last_report() is Some({ outcome: { success: true, .. }, .. }),
  )
}

///|
async test "metric reader run exports on its interval and shutdown exports once more" {
  @async.with_timeout(2000, () => {
    let client = fake_client(ok_replies(16))
    let reader = @transport.periodic_metric_reader(
      @transport.transport(client, "http://collector:4318"),
      [test_meter()],
      interval_ms=10,
    )
    @async.with_task_group(group => {
      group.spawn_bg(() => reader.run())
      while client.calls.length() < 2 {
        @async.sleep(1)
      }
      assert_true(reader.stats().running)
      let before = client.calls.length()
      let stats = reader.shutdown()
      assert_true(stats.closed)
      assert_eq(client.calls.length(), before + 1)
    })
    assert_false(reader.stats().running)
    // Later shutdowns and flushes export nothing.
    let calls = client.calls.length()
    ignore(reader.shutdown())
    ignore(reader.flush())
    assert_eq(client.calls.length(), calls)
  })
}

///|
async test "metric reader shutdown wakes a long interval without waiting it out" {
  @async.with_timeout(1000, () => {
    let client = fake_client(ok_replies(1))
    let reader = @transport.periodic_metric_reader(
      @transport.transport(client, "http://collector:4318"),
      [test_meter()],
      interval_ms=60000,
    )
    @async.with_task_group(group => {
      group.spawn_bg(() => reader.run())
      @async.pause()
      let stats = reader.shutdown()
      assert_eq(stats.delivered, 1L)
    })
    assert_eq(client.calls.length(), 1)
  })
}

///|
async test "metric reader bounds each export with its timeout" {
  @async.with_timeout(1000, () => {
    let client = gated_managed_client()
    let reader = @transport.periodic_metric_reader(
      @transport.transport(client, "http://fixture"),
      [test_meter()],
      timeout_ms=20,
    )
    let stats = reader.flush()
    assert_eq(stats.exports, 1L)
    assert_eq(stats.failed, 1L)
    assert_eq(stats.timed_out, 1L)
    assert_eq(reader.last_error(), Some("metric export timed out after 20 ms"))
    assert_eq(reader.last_report(), None)
  })
}

///|
async test "metric reader records failed exports" {
  let client = fake_client([FakeResponse(response(400))])
  let reader = @transport.periodic_metric_reader(
    @transport.transport(client, "http://collector:4318", max_retries=0),
    [test_meter()],
  )
  let stats = @async.with_timeout(1000, () => reader.flush())
  assert_eq(stats.failed, 1L)
  assert_eq(stats.delivered, 0L)
  assert_true(reader.last_error() is Some(_))
}

///|
async test "metric reader from OTEL config honors interval, timeout, resource, and disabled" {
  let vars : Map[String, String] = {
    "OTEL_EXPORTER_OTLP_PROTOCOL": "http/json",
    "OTEL_METRIC_EXPORT_INTERVAL": "10",
    "OTEL_SERVICE_NAME": "metrics-svc",
  }
  let config = @otlp.parse_otel_config(name => vars.get(name))
  let client = fake_client(ok_replies(16))
  let reader = @transport.metric_reader_from_otel_config(
    @transport.transport_from_otel_config(client, config),
    [test_meter()],
    config,
  )
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => reader.run())
      while client.calls.is_empty() {
        @async.sleep(1)
      }
      ignore(reader.shutdown())
    })
  })
  assert_eq(client.calls[0].url, "http://localhost:4318/v1/metrics")
  assert_true(client.calls[0].body.contains("\"stringValue\":\"metrics-svc\""))

  vars.set("OTEL_SDK_DISABLED", "true")
  let disabled_config = @otlp.parse_otel_config(name => vars.get(name))
  let quiet = fake_client([])
  let disabled = @transport.metric_reader_from_otel_config(
    @transport.transport_from_otel_config(quiet, disabled_config),
    [test_meter()],
    disabled_config,
  )
  let stats = @async.with_timeout(1000, () => {
    ignore(disabled.flush())
    disabled.shutdown()
  })
  assert_eq(stats.exports, 0L)
  assert_true(stats.closed)
  assert_eq(quiet.calls.length(), 0)
}
