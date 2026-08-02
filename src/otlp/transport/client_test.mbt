///|
#cfg(target="native")
async fn with_response_server(
  requests : Ref[Int],
  f : async (String) -> Unit,
) -> Unit {
  @async.with_task_group(group => {
    let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
    group.add_defer(() => server.close())
    group.spawn_bg(no_wait=true, () => {
      server.run_forever((request, request_body, conn) => {
        requests.val += 1
        while request_body.read_some() is Some(_) {

        }
        conn.send_response(200, "OK", extra_headers={ "Retry-After": "2" })
        match request.path {
          "/small" => conn.write("small response")
          "/exact" => conn.write("x".repeat(64 * 1024))
          "/oversized" => conn.write("x".repeat(64 * 1024 + 1))
          "/slow" => {
            conn.flush()
            @async.sleep(100)
            conn.write("too late")
          }
          _ => conn.write("unknown path")
        }
      })
    })
    f("http://127.0.0.1:\{server.addr.port()}")
  })
}

///|
#cfg(target="native")
fn expect_http_response(
  result : Result[@transport.HttpResponse, @transport.TransportError],
) -> @transport.HttpResponse {
  match result {
    Ok(response) => response
    Err(err) => abort("expected HTTP response, got \{err}")
  }
}

///|
#cfg(target="native")
async test "async HTTP client preserves bounded response bodies" {
  @async.with_timeout(2000, () => {
    let requests : Ref[Int] = Ref(0)
    with_response_server(requests, endpoint => {
      let client = @transport.async_http_client(timeout_ms=1000)
      let small = expect_http_response(
        client.post(endpoint + "/small", "{}", @transport.default_headers()),
      )
      assert_eq(small.status_code, 200)
      assert_eq(small.body, "small response")
      assert_true(small.retry_after_ms == Some(2000))
      let exact = expect_http_response(
        client.post(endpoint + "/exact", "{}", @transport.default_headers()),
      )
      assert_eq(exact.body.length(), 64 * 1024)
      assert_eq(requests.val, 2)
    })
  })
}

///|
#cfg(target="native")
async test "async HTTP client rejects oversized response and remains usable" {
  @async.with_timeout(2000, () => {
    let requests : Ref[Int] = Ref(0)
    with_response_server(requests, endpoint => {
      let client = @transport.async_http_client(timeout_ms=1000)
      match
        client.post(endpoint + "/oversized", "{}", @transport.default_headers()) {
        Err(@transport.Request(message)) =>
          assert_eq(message, "HTTP response body exceeds 65536 bytes")
        Err(err) => abort("unexpected transport error: \{err}")
        Ok(_) => abort("expected oversized response to fail")
      }
      let response = expect_http_response(
        client.post(endpoint + "/small", "{}", @transport.default_headers()),
      )
      assert_eq(response.body, "small response")
      assert_eq(requests.val, 2)
    })
  })
}

///|
#cfg(target="native")
async test "oversized OTLP response is non-retryable" {
  @async.with_timeout(2000, () => {
    let requests : Ref[Int] = Ref(0)
    with_response_server(requests, endpoint => {
      let client = @transport.async_http_client(timeout_ms=1000)
      let tx = @transport.transport(
        client,
        endpoint,
        traces_path="/oversized",
        max_retries=3,
        base_backoff_ms=0,
      )
      match tx.export_json(endpoint + "/oversized", "{}") {
        Err(@transport.Request(message)) =>
          assert_eq(message, "HTTP response body exceeds 65536 bytes")
        Err(err) => abort("unexpected transport error: \{err}")
        Ok(_) => abort("expected oversized response to fail")
      }
      assert_eq(requests.val, 1)
    })
  })
}

///|
#cfg(target="native")
async test "response body read obeys HTTP client timeout" {
  @async.with_timeout(2000, () => {
    let requests : Ref[Int] = Ref(0)
    with_response_server(requests, endpoint => {
      let client = @transport.async_http_client(timeout_ms=25)
      match
        client.post(endpoint + "/slow", "{}", @transport.default_headers()) {
        Err(@transport.Timeout(message)) =>
          assert_eq(message, "HTTP request timed out after 25ms")
        Err(err) => abort("unexpected transport error: \{err}")
        Ok(_) => abort("expected body read timeout")
      }
      assert_eq(requests.val, 1)
    })
  })
}
