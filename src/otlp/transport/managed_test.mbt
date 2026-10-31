///|
fn managed_event(message : String) -> @moontrace.Event {
  {
    level: @moontrace.Info,
    message,
    fields: [],
    timestamp: 1700000000123UL,
    source: "managed-fixture",
    file: "",
    line: 0,
  }
}

///|
pub(all) struct GatedManagedClient {
  calls : Array[String]
  gate : @aqueue.Queue[Unit]
}

///|
pub impl @transport.OtlpHttpClient for GatedManagedClient with fn post(
  self,
  _url,
  body,
  _headers,
) {
  self.calls.push(body)
  ignore(self.gate.get())
  Ok({ status_code: 200, body: "{}", retry_after_ms: None, })
}

///|
fn gated_managed_client() -> GatedManagedClient {
  { calls: [], gate: @aqueue.Queue(kind=@aqueue.Blocking(8)), }
}

///|
fn release_managed(client : GatedManagedClient) -> Unit raise {
  assert_true(client.gate.try_put(()) catch { _ => false })
}

///|
async test "managed queue pressure drops newest batches without starting tasks" {
  let client = fake_client([
    FakeResponse(response(200)),
    FakeResponse(response(200)),
  ])
  let tx = test_transport(client)
  let managed = @transport.managed_json_exporter(
    tx,
    batch_size=1,
    queue_capacity=2,
  )
  let emit = managed.subscriber()
  for index in 0..<5 {
    emit(managed_event(index.to_string()))
  }
  assert_eq(client.calls.length(), 0)
  assert_eq(managed.stats().pending_batches, 2)
  assert_eq(managed.stats().dropped_batches, 3L)
  assert_eq(managed.stats().dropped_records, 3L)
  let stats = managed.flush()
  assert_eq(stats.delivered_batches, 2L)
  assert_eq(stats.pending_bytes, 0)
  assert_true(client.calls[0].body.contains("\"stringValue\":\"0\""))
  assert_true(client.calls[1].body.contains("\"stringValue\":\"1\""))
  ignore(managed.shutdown())
}

///|
async test "managed shutdown drains queue and both final partial batches at capacity one" {
  let client = fake_client([
    FakeResponse(response(200)),
    FakeResponse(response(200)),
    FakeResponse(response(200)),
  ])
  let tx = test_transport(client)
  let managed = @transport.managed_json_exporter(
    tx,
    batch_size=2,
    queue_capacity=1,
  )
  let emit = managed.subscriber()
  emit(managed_event("one"))
  emit(managed_event("two"))
  emit(managed_event("tail"))
  let span = @moontrace.span("final span")
  span.end_time = span.start_time + 1UL
  (managed.span_observer().on_closed)(span)
  let stats = managed.shutdown()
  assert_eq(stats.delivered_batches, 3L)
  assert_eq(stats.dropped_records, 0L)
  assert_eq(stats.buffered_logs, 0)
  assert_eq(stats.buffered_spans, 0)
  assert_eq(stats.pending_bytes, 0)
  assert_true(stats.closed)
  assert_true(tx.is_shut_down)
  assert_true(client.calls[1].body.contains("tail"))
  assert_true(client.calls[2].body.contains("resourceSpans"))
  emit(managed_event("after close"))
  assert_eq(managed.shutdown().dropped_records, 1L)
  assert_eq(client.calls.length(), 3)
}

///|
async test "managed timer sends partial batches and shutdown joins timer promptly" {
  @async.with_timeout(1000, () => {
    let client = fake_client([FakeResponse(response(200))])
    let managed = @transport.managed_json_exporter(
      test_transport(client),
      flush_interval_ms=10,
    )
    managed.subscriber()(managed_event("timer"))
    @async.with_task_group(group => {
      group.spawn_bg(() => managed.run())
      while client.calls.is_empty() {
        @async.sleep(1)
      }
      assert_eq(managed.stats().delivered_batches, 1L)
      let stats = managed.shutdown()
      assert_false(stats.worker_running)
    })
    let idle = @transport.managed_json_exporter(
      test_transport(fake_client([])),
      flush_interval_ms=60000,
    )
    @async.with_task_group(group => {
      group.spawn_bg(() => idle.run())
      @async.pause()
      ignore(idle.shutdown())
    })
  })
}

///|
async test "managed flush barrier excludes later batches and includes in-flight work" {
  @async.with_timeout(1000, () => {
    let client = gated_managed_client()
    let managed = @transport.managed_json_exporter(
      @transport.transport(client, "http://fixture"),
      batch_size=1,
    )
    let emit = managed.subscriber()
    emit(managed_event("first"))
    @async.with_task_group(group => {
      group.spawn_bg(() => managed.run())
      while client.calls.is_empty() {
        @async.pause()
      }
      let flushed = Ref(false)
      let barrier = group.spawn(() => {
        ignore(managed.flush())
        flushed.val = true
      })
      @async.pause()
      assert_false(flushed.val)
      emit(managed_event("later"))
      release_managed(client)
      barrier.wait()
      assert_eq(managed.stats().delivered_batches, 1L)
      assert_eq(managed.stats().pending_batches, 1)
      release_managed(client)
      ignore(managed.shutdown())
      assert_eq(client.calls.length(), 2)
    })
  })
}

///|
async test "managed worker cancellation settles uncertain in-flight work and preserves unsent queue" {
  @async.with_timeout(1000, () => {
    let client = gated_managed_client()
    let managed = @transport.managed_json_exporter(
      @transport.transport(client, "http://fixture"),
      batch_size=1,
    )
    managed.subscriber()(managed_event("in flight"))
    managed.subscriber()(managed_event("still queued"))
    @async.with_task_group(group => {
      let worker = group.spawn(() => managed.run())
      while client.calls.is_empty() {
        @async.pause()
      }
      worker.cancel()
      let cancelled = Ref(false)
      worker.wait() catch {
        error => cancelled.val = @async.is_cancellation_error(error)
      }
      assert_true(cancelled.val)
      assert_eq(managed.stats().failed_batches, 1L)
      assert_eq(managed.stats().pending_batches, 1)
      assert_false(managed.stats().worker_running)
      assert_true(managed.last_error().unwrap().contains("unknown"))
      release_managed(client)
      let stats = managed.shutdown()
      assert_eq(stats.delivered_batches, 1L)
      assert_eq(stats.failed_batches, 1L)
      assert_eq(stats.pending_bytes, 0)
      assert_eq(client.calls.length(), 2)
      assert_true(client.calls[1].contains("still queued"))
    })
  })
}

///|
async test "managed cancelled shutdown can resume drain and rejects new intake" {
  @async.with_timeout(1000, () => {
    let client = gated_managed_client()
    let tx = @transport.transport(client, "http://fixture")
    let managed = @transport.managed_json_exporter(
      tx,
      batch_size=2,
      queue_capacity=1,
    )
    let emit = managed.subscriber()
    emit(managed_event("one"))
    emit(managed_event("two"))
    emit(managed_event("tail"))
    @async.with_task_group(group => {
      group.spawn_bg(() => managed.run())
      while client.calls.is_empty() {
        @async.pause()
      }
      let shutdown = group.spawn(() => managed.shutdown())
      @async.pause()
      shutdown.cancel()
      (shutdown.wait() |> ignore) catch {
        _ => ()
      }
      assert_true(managed.stats().closing)
      assert_false(tx.is_shut_down)
      let incomplete = Ref(false)
      (managed.flush() |> ignore) catch {
        _ => incomplete.val = true
      }
      assert_true(incomplete.val)
      emit(managed_event("closed intake"))
      release_managed(client)
      release_managed(client)
      let stats = managed.shutdown()
      assert_eq(stats.delivered_batches, 2L)
      assert_eq(stats.dropped_records, 1L)
      assert_eq(stats.failed_batches, 0L)
      assert_false(stats.worker_running)
    })
  })
}

///|
async test "managed reports transport retry exhaustion partial rejection and malformed replies" {
  let client = fake_client([
    FakeResponse(response(503)),
    FakeResponse(response(200)),
    FakeResponse(response(503)),
    FakeResponse(response(503)),
    FakeResponse({
      status_code: 200,
      body: "{\"partialSuccess\":{\"rejectedLogRecords\":\"1\",\"errorMessage\":\"fixture\"}}",
      retry_after_ms: None,
    }),
    FakeResponse({ status_code: 200, body: "broken", retry_after_ms: None, }),
  ])
  let managed = @transport.managed_json_exporter(
    test_transport(client, max_retries=1),
    batch_size=1,
  )
  for _ in 0..<3 {
    managed.subscriber()(managed_event("fixture"))
  }
  let stats = managed.flush()
  assert_eq(stats.delivered_batches, 1L)
  assert_eq(stats.failed_batches, 2L)
  assert_eq(
    managed.last_report().unwrap().partial_success.unwrap().rejected_log_records,
    1L,
  )
  managed.subscriber()(managed_event("malformed"))
  assert_eq(managed.shutdown().failed_batches, 3L)
  assert_true(managed.last_report() is None)
  assert_true(managed.last_error().unwrap().contains("invalid OTLP"))
  assert_eq(client.calls.length(), 6)
}

///|
async test "managed payload and total byte budgets include UTF8 and in-flight batches" {
  let event = managed_event("🙂🙂🙂")
  let bytes = @utf8.encode(
    @otlp.wrap_log_records([@otlp.event_to_log_record(event)]).stringify(),
  ).length()
  let client = gated_managed_client()
  let managed = @transport.managed_json_exporter(
    @transport.transport(client, "http://fixture"),
    batch_size=50,
    queue_capacity=10,
    max_payload_bytes=bytes,
    max_pending_bytes=bytes,
  )
  let emit = managed.subscriber()
  emit(event)
  emit(event)
  assert_eq(managed.stats().pending_bytes, bytes)
  assert_eq(managed.stats().buffered_logs, 1)
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      group.spawn_bg(() => managed.run())
      while client.calls.is_empty() {
        @async.pause()
      }
      emit(event)
      assert_eq(managed.stats().pending_bytes, bytes)
      assert_eq(managed.stats().dropped_batches, 1L)
      emit(managed_event("x".repeat(bytes)))
      assert_eq(managed.stats().dropped_records, 2L)
      release_managed(client)
      release_managed(client)
      let stats = managed.shutdown()
      assert_eq(stats.delivered_batches, 2L)
      assert_eq(stats.pending_bytes, 0)
    })
  })
}

///|
async test "managed rejects a duplicate worker and tolerates idempotent lifecycle calls" {
  @async.with_timeout(1000, () => {
    let managed = @transport.managed_json_exporter(
      test_transport(fake_client([])),
    )
    @async.with_task_group(group => {
      group.spawn_bg(() => managed.run())
      @async.pause()
      let duplicate = Ref(false)
      managed.run() catch {
        _ => duplicate.val = true
      }
      assert_true(duplicate.val)
      ignore(managed.shutdown())
      ignore(managed.shutdown())
      ignore(managed.flush())
      managed.run()
      assert_eq(managed.stats().failed_batches, 0L)
    })
  })
}

///|
async test "managed idle worker cancellation preserves partial batches for restart" {
  @async.with_timeout(1000, () => {
    let client = fake_client([FakeResponse(response(200))])
    let managed = @transport.managed_json_exporter(
      test_transport(client),
      flush_interval_ms=20,
    )
    managed.subscriber()(managed_event("restart fixture"))
    @async.with_task_group(group => {
      let worker = group.spawn(() => managed.run())
      @async.pause()
      worker.cancel()
      worker.wait() catch {
        _ => ()
      }
      assert_eq(managed.stats().failed_batches, 0L)
      assert_eq(managed.stats().buffered_logs, 1)
      group.spawn_bg(() => managed.run())
      while client.calls.is_empty() {
        @async.sleep(1)
      }
      assert_eq(managed.shutdown().delivered_batches, 1L)
    })
  })
}

///|
test "managed nonpositive limits reject oversized records without queueing" {
  let managed = @transport.managed_json_exporter(
    test_transport(fake_client([])),
    batch_size=0,
    queue_capacity=0,
    max_payload_bytes=0,
    max_pending_bytes=0,
    flush_interval_ms=0,
  )
  managed.subscriber()(managed_event("oversized"))
  let span = @moontrace.span("oversized span")
  (managed.span_observer().on_closed)(span)
  let stats = managed.stats()
  assert_eq(stats.dropped_records, 2L)
  assert_eq(stats.dropped_batches, 0L)
  assert_eq(stats.pending_bytes, 0)
  assert_eq(stats.buffered_logs, 0)
  assert_eq(stats.buffered_spans, 0)
}
