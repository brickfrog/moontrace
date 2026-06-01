///|
fn assert_retry_class(
  actual : @transport.RetryClass,
  expected : @transport.RetryClass,
) -> Unit {
  if actual != expected {
    abort("unexpected retry class")
  }
}

///|
test "classify_status follows OTLP HTTP retry matrix" {
  for status = 0; status < 600; {
    let expected = if status >= 200 && status < 300 {
      @transport.Success
    } else {
      match status {
        429 | 502 | 503 | 504 => @transport.Retryable
        _ => @transport.NonRetryable
      }
    }
    assert_retry_class(@transport.classify_status(status), expected)
    continue status + 1
  }
}

///|
test "classify_error follows transport retry matrix" {
  assert_retry_class(
    @transport.classify_error(@transport.Network("dns")),
    @transport.Retryable,
  )
  assert_retry_class(
    @transport.classify_error(@transport.Timeout("slow")),
    @transport.Retryable,
  )
  assert_retry_class(
    @transport.classify_error(@transport.Request("bad url")),
    @transport.NonRetryable,
  )
}

///|
test "transport error has manual show text" {
  assert_eq(@transport.Network("reset").to_string(), "network error: reset")
  assert_eq("\{@transport.Timeout("slow")}", "timeout: slow")
  assert_eq("\{@transport.Request("bad")}", "request error: bad")
}

///|
pub(all) enum FakeReply {
  FakeResponse(@transport.HttpResponse)
  FakeError(@transport.TransportError)
}

///|
pub(all) struct FakeCall {
  url : String
  body : String
  headers : Map[String, String]
} derive(Debug)

///|
pub(all) struct FakeClient {
  replies : Array[FakeReply]
  calls : Array[FakeCall]
  mut next : Int
}

///|
fn fake_client(replies : Array[FakeReply]) -> FakeClient {
  { replies, calls: [], next: 0 }
}

///|
fn response(status_code : Int) -> @transport.HttpResponse {
  { status_code, body: "body-\{status_code}", retry_after_ms: None }
}

///|
fn response_retry_after(
  status_code : Int,
  retry_after_ms : Int,
) -> @transport.HttpResponse {
  {
    status_code,
    body: "body-\{status_code}",
    retry_after_ms: Some(retry_after_ms),
  }
}

///|
pub impl @transport.OtlpHttpClient for FakeClient with fn post(
  self,
  url,
  body,
  headers,
) {
  self.calls.push({ url, body, headers: headers.copy() })
  if self.next >= self.replies.length() {
    return Err(@transport.Request("fake client exhausted"))
  }
  let reply = self.replies[self.next]
  self.next = self.next + 1
  match reply {
    FakeResponse(resp) => Ok(resp)
    FakeError(err) => Err(err)
  }
}

///|
fn test_transport(
  client : FakeClient,
  max_retries? : Int = 3,
) -> @transport.OtlpHttpTransport {
  @transport.transport(
    client,
    "http://collector:4318",
    max_retries~,
    base_backoff_ms=0,
  )
}

///|
fn unwrap_outcome(
  result : Result[@transport.ExportOutcome, @transport.TransportError],
) -> @transport.ExportOutcome {
  match result {
    Ok(outcome) => outcome
    Err(err) => abort("expected outcome, got \{err}")
  }
}

///|
async test "export_json succeeds on first try" {
  let client = fake_client([FakeResponse(response(200))])
  let tx = test_transport(client)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => {
      tx.export_json("http://collector/v1/traces", "{\"ok\":true}")
    }),
  )
  assert_eq(outcome.success, true)
  assert_eq(outcome.attempts, 1)
  assert_eq(client.calls.length(), 1)
  assert_eq(client.calls[0].url, "http://collector/v1/traces")
  assert_eq(client.calls[0].body, "{\"ok\":true}")
  assert_true(
    client.calls[0].headers.get("Content-Type") == Some("application/json"),
  )
}

///|
async test "export_json retries 503 responses then succeeds" {
  let client = fake_client([
    FakeResponse(response(503)),
    FakeResponse(response(503)),
    FakeResponse(response(200)),
  ])
  let tx = test_transport(client, max_retries=3)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => {
      tx.export_json("http://collector/v1/traces", "{}")
    }),
  )
  assert_eq(outcome.success, true)
  assert_eq(outcome.attempts, 3)
  assert_eq(client.calls.length(), 3)
}

///|
async test "export_json exhausts retryable 503 responses" {
  let client = fake_client([
    FakeResponse(response(503)),
    FakeResponse(response(503)),
    FakeResponse(response(503)),
  ])
  let tx = test_transport(client, max_retries=2)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => {
      tx.export_json("http://collector/v1/traces", "{}")
    }),
  )
  assert_eq(outcome.success, false)
  assert_eq(outcome.attempts, 3)
  assert_true(outcome.status_code == Some(503))
  assert_retry_class(outcome.retry_class, @transport.Retryable)
  assert_eq(client.calls.length(), 3)
}

///|
async test "export_json does not retry non-retryable 400" {
  let client = fake_client([
    FakeResponse(response(400)),
    FakeResponse(response(200)),
  ])
  let tx = test_transport(client, max_retries=3)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => {
      tx.export_json("http://collector/v1/traces", "{}")
    }),
  )
  assert_eq(outcome.success, false)
  assert_eq(outcome.attempts, 1)
  assert_true(outcome.status_code == Some(400))
  assert_retry_class(outcome.retry_class, @transport.NonRetryable)
  assert_eq(client.calls.length(), 1)
}

///|
async test "export_json retries network error then succeeds" {
  let client = fake_client([
    FakeError(@transport.Network("connection reset")),
    FakeResponse(response(200)),
  ])
  let tx = test_transport(client, max_retries=3)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => {
      tx.export_json("http://collector/v1/traces", "{}")
    }),
  )
  assert_eq(outcome.success, true)
  assert_eq(outcome.attempts, 2)
  assert_eq(client.calls.length(), 2)
}

///|
async test "export_json honors zero retry-after without sleeping" {
  let client = fake_client([
    FakeResponse(response_retry_after(503, 0)),
    FakeResponse(response(200)),
  ])
  let tx = test_transport(client, max_retries=1)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => {
      tx.export_json("http://collector/v1/traces", "{}")
    }),
  )
  assert_eq(outcome.success, true)
  assert_eq(outcome.attempts, 2)
}

///|
async test "shutdown rejects later exports" {
  let client = fake_client([FakeResponse(response(200))])
  let tx = test_transport(client)
  tx.shutdown()
  match
    @async.with_timeout(1000, () => {
      tx.export_json("http://collector/v1/traces", "{}")
    }) {
    Ok(_) => abort("expected shutdown error")
    Err(err) =>
      assert_retry_class(
        @transport.classify_error(err),
        @transport.NonRetryable,
      )
  }
  assert_eq(client.calls.length(), 0)
}

///|
fn test_span(name : String) -> @otlp.OtlpSpan {
  @otlp.OtlpSpan::{
    trace_id: "0000000000000000000000000000000a",
    span_id: "000000000000000b",
    parent_span_id: "",
    flags: 0,
    name,
    kind: 1,
    start_time_unix_nano: (100 : UInt64),
    end_time_unix_nano: (200 : UInt64),
    attributes: [],
    status_code: 1,
    status_message: "",
  }
}

///|
fn test_log_record(body : String) -> @otlp.OtlpLogRecord {
  @otlp.OtlpLogRecord::{
    time_unix_nano: (100 : UInt64),
    severity_number: 9,
    severity_text: "INFO",
    body,
    attributes: [],
  }
}

///|
async test "export_spans builds traces URL and OTLP JSON envelope" {
  let client = fake_client([FakeResponse(response(200))])
  let tx = test_transport(client)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => tx.export_spans([test_span("work")])),
  )
  assert_eq(outcome.success, true)
  assert_eq(client.calls[0].url, "http://collector:4318/v1/traces")
  assert_true(client.calls[0].body.contains("\"resourceSpans\""))
  assert_true(client.calls[0].body.contains("\"name\":\"work\""))
}

///|
async test "export_logs builds logs URL and OTLP JSON envelope" {
  let client = fake_client([FakeResponse(response(200))])
  let tx = test_transport(client)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => tx.export_logs([test_log_record("hello")])),
  )
  assert_eq(outcome.success, true)
  assert_eq(client.calls[0].url, "http://collector:4318/v1/logs")
  assert_true(client.calls[0].body.contains("\"resourceLogs\""))
  assert_true(client.calls[0].body.contains("\"stringValue\":\"hello\""))
}
