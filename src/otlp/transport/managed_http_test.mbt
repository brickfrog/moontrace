///|
#cfg(target="native")
async test "managed HTTP shutdown drains through a slow retrying synthetic collector" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let requests : Array[String] = []
      let payloads : Array[String] = []
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      group.add_defer(() => server.close())
      group.spawn_bg(no_wait=true, () => {
        server.run_forever((request, body, conn) => {
          requests.push(request.path)
          let data = StringBuilder()
          while body.read_some() is Some(chunk) {
            data.write_string(@utf8.decode(chunk))
          }
          payloads.push(data.to_string())
          @async.sleep(20)
          if requests.length() == 1 {
            conn.send_response(503, "Unavailable", extra_headers={
              "Retry-After": "0",
            })
            conn.write("{}")
          } else {
            conn.send_response(200, "OK")
            conn.write(
              if request.path == "/v1/traces" {
                "{\"partialSuccess\":{\"rejectedSpans\":\"1\",\"errorMessage\":\"synthetic rejection\"}}"
              } else {
                "{}"
              },
            )
          }
        })
      })
      let client = @transport.async_http_client(timeout_ms=1000)
      defer client.shutdown()
      let tx = @transport.transport(
        client,
        "http://127.0.0.1:\{server.addr.port()}",
        max_retries=1,
        base_backoff_ms=0,
      )
      let managed = @transport.managed_json_exporter(
        tx,
        batch_size=2,
        queue_capacity=1,
      )
      let emit = managed.subscriber()
      emit(managed_event("one"))
      emit(managed_event("two"))
      emit(managed_event("final log"))
      let span = @moontrace.span("final span")
      span.end_time = span.start_time + 1UL
      (managed.span_observer().on_closed)(span)
      group.spawn_bg(() => managed.run())
      let stats = managed.shutdown()
      assert_eq(requests, ["/v1/logs", "/v1/logs", "/v1/logs", "/v1/traces"])
      assert_eq(payloads[0], payloads[1])
      assert_true(payloads[2].contains("final log"))
      assert_eq(stats.delivered_batches, 2L)
      assert_eq(stats.failed_batches, 1L)
      assert_eq(stats.dropped_records, 0L)
      assert_eq(stats.pending_bytes, 0)
      assert_false(stats.worker_running)
      assert_eq(
        managed.last_report().unwrap().partial_success.unwrap().rejected_spans,
        1L,
      )
    })
  })
}

///|
#cfg(target="native")
async test "managed cancellation interrupts a slow HTTP response without retry" {
  @async.with_timeout(2000, () => {
    @async.with_task_group(group => {
      let requests = Ref(0)
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      group.add_defer(() => server.close())
      group.spawn_bg(no_wait=true, () => {
        server.run_forever((_request, body, conn) => {
          requests.val += 1
          while body.read_some() is Some(_) {

          }
          conn.send_response(200, "OK")
          conn.flush()
          @async.sleep(1000)
          conn.write("{}")
        })
      })
      let client = @transport.async_http_client(timeout_ms=1500)
      defer client.shutdown()
      let managed = @transport.managed_json_exporter(
        @transport.transport(client, "http://127.0.0.1:\{server.addr.port()}"),
        batch_size=1,
      )
      managed.subscriber()(managed_event("cancelled fixture"))
      let worker = group.spawn(() => managed.run())
      while requests.val == 0 {
        @async.sleep(1)
      }
      worker.cancel()
      let cancelled = Ref(false)
      worker.wait() catch {
        error => cancelled.val = @async.is_cancellation_error(error)
      }
      assert_true(cancelled.val)
      let stats = managed.shutdown()
      assert_eq(stats.failed_batches, 1L)
      assert_eq(stats.pending_bytes, 0)
      assert_eq(requests.val, 1)
    })
  })
}
