///|
pub(all) struct BytesCall {
  url : String
  body : Bytes
  headers : Map[String, String]
}

///|
/// A fake client that implements `post_bytes` and replies with fixed bodies.
pub(all) struct BytesClient {
  replies : Array[(Int32, Bytes)]
  calls : Array[BytesCall]
  mut next : Int32
}

///|
pub impl @transport.OtlpHttpClient for BytesClient with fn post(
  _self,
  _url,
  _body,
  _headers,
) {
  Err(@transport.Request("text post not expected"))
}

///|
pub impl @transport.OtlpHttpClient for BytesClient with fn post_bytes(
  self,
  url,
  body,
  headers,
) {
  self.calls.push({ url, body, headers: headers.copy(), })
  if self.next >= self.replies.length() {
    return Err(@transport.Request("fake client exhausted"))
  }
  let (status_code, reply) = self.replies[self.next]
  self.next = self.next + 1
  Ok({ status_code, body: reply, retry_after_ms: Some(0), })
}

///|
fn bytes_client(replies : Array[(Int32, Bytes)]) -> BytesClient {
  { replies, calls: [], next: 0, }
}

///|
/// Encode a protobuf `partial_success` response: field 1 holding a message
/// with the rejected count (field 1) and error message (field 2).
fn partial_response(rejected : Int32, message : String) -> Bytes {
  let text = @utf8.encode(message)
  let inner : Array[Byte] = [
    b'\x08',
    rejected.to_byte(),
    b'\x12',
    text.length().to_byte(),
  ]
  for byte in text {
    inner.push(byte)
  }
  let outer : Array[Byte] = [b'\x0a', inner.length().to_byte()]
  for byte in inner {
    outer.push(byte)
  }
  Bytes::from_array(outer[:])
}

///|
async fn gunzip(body : Bytes) -> Bytes {
  let reader = @io.MemoryReader(writer => writer.write(body))
  @gzip.Decoder(reader).read_all().binary()
}

///|
fn protobuf_transport(
  client : BytesClient,
  compression~ : @transport.OtlpCompression = NoCompression,
) -> @transport.OtlpHttpTransport {
  @transport.transport(
    client,
    "http://collector:4318",
    base_backoff_ms=0,
    encoder=ProtobufEncoder,
    compression~,
  )
}

///|
async test "protobuf export sends encoded bytes with the protobuf content type" {
  let client = bytes_client([(200, b"")])
  let tx = protobuf_transport(client)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => tx.export_spans([test_span("work")])),
  )
  assert_true(outcome.success)
  let expected = match
    @transport.protobuf_encoder().encode_spans([test_span("work")]) {
    Ok(payload) => payload.body
    Err(err) => abort(err.to_string())
  }
  assert_eq(client.calls[0].url, "http://collector:4318/v1/traces")
  assert_eq(client.calls[0].body, expected)
  assert_eq(
    client.calls[0].headers.get("Content-Type"),
    Some("application/x-protobuf"),
  )
  assert_eq(client.calls[0].headers.get("Content-Encoding"), None)
}

///|
async test "protobuf partial success is parsed per signal" {
  let client = bytes_client([
    (200, partial_response(2, "spans rejected")),
    (200, partial_response(3, "logs rejected")),
  ])
  let tx = protobuf_transport(client)
  let spans = match
    @async.with_timeout(1000, () => tx.export_spans_report([test_span("a")])) {
    Ok(report) => report
    Err(err) => abort("\{err}")
  }
  assert_false(spans.outcome.success)
  assert_eq(
    spans.partial_success,
    Some({
      rejected_spans: 2L,
      rejected_log_records: 0L,
      error_message: "spans rejected",
    }),
  )
  let logs = match
    @async.with_timeout(1000, () => {
      tx.export_logs_report([test_log_record("x")])
    }) {
    Ok(report) => report
    Err(err) => abort("\{err}")
  }
  assert_eq(
    logs.partial_success,
    Some({
      rejected_spans: 0L,
      rejected_log_records: 3L,
      error_message: "logs rejected",
    }),
  )
}

///|
async test "protobuf export retries retryable statuses" {
  let client = bytes_client([(503, b""), (200, b"")])
  let tx = protobuf_transport(client)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => tx.export_logs([test_log_record("x")])),
  )
  assert_true(outcome.success)
  assert_eq(outcome.attempts, 2)
  assert_eq(client.calls[0].body, client.calls[1].body)
}

///|
async test "gzip compression applies to encoded and raw JSON payloads" {
  let client = bytes_client([(200, b""), (200, b"")])
  let tx = protobuf_transport(client, compression=GzipCompression)
  ignore(
    unwrap_outcome(
      @async.with_timeout(1000, () => tx.export_spans([test_span("zip")])),
    ),
  )
  let expected = match
    @transport.protobuf_encoder().encode_spans([test_span("zip")]) {
    Ok(payload) => payload.body
    Err(err) => abort(err.to_string())
  }
  assert_eq(client.calls[0].headers.get("Content-Encoding"), Some("gzip"))
  assert_eq(gunzip(client.calls[0].body), expected)

  ignore(
    unwrap_outcome(
      @async.with_timeout(1000, () => {
        tx.export_json("http://collector:4318/v1/logs", "{\"resourceLogs\":[]}")
      }),
    ),
  )
  assert_eq(
    client.calls[1].headers.get("Content-Type"),
    Some("application/json"),
  )
  assert_eq(@utf8.decode(gunzip(client.calls[1].body)), "{\"resourceLogs\":[]}")
}

///|
async test "text-only clients reject binary bodies without retrying" {
  let client = fake_client([FakeResponse(response(200))])
  let tx = @transport.transport(
    client,
    "http://collector:4318",
    encoder=ProtobufEncoder,
  )
  let result = @async.with_timeout(1000, () => tx.export_spans([test_span("a")]))
  assert_true(result is Err(Request(_)))
  assert_eq(client.calls.length(), 0)
  // JSON bodies still reach `post` through the default `post_bytes`.
  let json = @transport.transport(client, "http://collector:4318")
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => json.export_spans([test_span("a")])),
  )
  assert_true(outcome.success)
  assert_true(client.calls[0].body.contains("\"resourceSpans\""))
}

///|
test "parse_protobuf_export_response handles empty, unknown, and malformed bodies" {
  assert_eq(@transport.parse_protobuf_export_response(b"", Traces), Ok(None))
  // Unknown varint field 2 before partial_success, unknown field 3 inside it.
  let body : Bytes = b"\x10\x05\x0a\x06\x08\x01\x18\x07\x12\x00"
  assert_eq(
    @transport.parse_protobuf_export_response(body, Logs),
    Ok(
      Some({ rejected_spans: 0L, rejected_log_records: 1L, error_message: "", }),
    ),
  )
  for
    bad in [
      b"\x0a\x05\x08", b"\x0a", b"\x08\x80", b"\x0f", b"\x0a\x01\x12\x01", b"\x0a\x02\x12\x05",
      b"\x0a\x01\x08\x01", b"\x0a\x03\x1a\x05\x00",
    ] {
    assert_true(
      @transport.parse_protobuf_export_response(bad, Traces) is Err(_),
    )
  }
  // A negative int64 rejected count is invalid.
  let negative : Bytes = b"\x0a\x0b\x08\xff\xff\xff\xff\xff\xff\xff\xff\xff\x01"
  assert_true(
    @transport.parse_protobuf_export_response(negative, Traces) is Err(_),
  )
}

///|
#cfg(target="native")
async test "HTTP client sends gzip protobuf and parses a protobuf reply over localhost" {
  @async.with_timeout(3000, () => {
    @async.with_task_group(group => {
      let content_types : Array[String] = []
      let encodings : Array[String] = []
      let bodies : Array[Bytes] = []
      let server = @http.Server(@socket.Addr::parse("127.0.0.1:0"))
      group.add_defer(() => server.close())
      group.spawn_bg(no_wait=true, () => {
        server.run_forever((request, body, conn) => {
          content_types.push(request.headers.get("content-type").unwrap_or(""))
          encodings.push(request.headers.get("content-encoding").unwrap_or(""))
          let raw : Array[Byte] = []
          while body.read_some() is Some(chunk) {
            for byte in chunk {
              raw.push(byte)
            }
          }
          bodies.push(Bytes::from_array(raw[:]))
          conn.send_response(200, "OK", extra_headers={
            "Content-Type": "application/x-protobuf",
          })
          conn.write(partial_response(1, "synthetic rejection"))
        })
      })
      let client = @transport.async_http_client(timeout_ms=1000)
      defer client.shutdown()
      let tx = @transport.transport(
        client,
        "http://127.0.0.1:\{server.addr.port()}",
        encoder=ProtobufEncoder,
        compression=GzipCompression,
        base_backoff_ms=0,
      )
      let report = match tx.export_spans_report([test_span("wire")]) {
        Ok(report) => report
        Err(err) => abort("\{err}")
      }
      assert_false(report.outcome.success)
      assert_eq(
        report.partial_success,
        Some({
          rejected_spans: 1L,
          rejected_log_records: 0L,
          error_message: "synthetic rejection",
        }),
      )
      assert_eq(content_types, ["application/x-protobuf"])
      assert_eq(encodings, ["gzip"])
      let expected = match
        @transport.protobuf_encoder().encode_spans([test_span("wire")]) {
        Ok(payload) => payload.body
        Err(err) => abort(err.to_string())
      }
      assert_eq(gunzip(bodies[0]), expected)
    })
  })
}
