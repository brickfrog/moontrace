///|
fn assert_retry_class(
  actual : @transport.RetryClass,
  expected : @transport.RetryClass,
) -> Unit {
  if actual != expected {
    abort(
      "unexpected retry class: expected \{retry_class_name(expected)}, got \{retry_class_name(actual)}",
    )
  }
}

///|
fn retry_class_name(class : @transport.RetryClass) -> String {
  match class {
    @transport.Success => "Success"
    @transport.Retryable => "Retryable"
    @transport.NonRetryable => "NonRetryable"
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
test "retry-after seconds clamp before millisecond conversion" {
  assert_true(
    @transport.parse_retry_after_ms({ "Retry-After": "2" }) == Some(2000),
  )
  assert_true(
    @transport.parse_retry_after_ms({ "Retry-After": "2147484" }) ==
    Some(300000),
  )
  assert_true(
    @transport.parse_retry_after_ms({
      "Retry-After": "Wed, 21 Oct 2015 07:28:00 GMT",
    }) ==
    None,
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
  mut next : Int32
}

///|
pub(all) struct ShutdownAfterPostClient {
  replies : Array[FakeReply]
  calls : Array[FakeCall]
  mut next : Int32
  shutdown_on_call : Int32
  after_post : () -> Unit
}

///|
fn fake_client(replies : Array[FakeReply]) -> FakeClient {
  { replies, calls: [], next: 0, }
}

///|
fn response(status_code : Int32) -> @transport.HttpResponse {
  { status_code, body: "{}", retry_after_ms: None, }
}

///|
fn response_retry_after(
  status_code : Int32,
  retry_after_ms : Int32,
) -> @transport.HttpResponse {
  { status_code, body: "{}", retry_after_ms: Some(retry_after_ms), }
}

///|
pub impl @transport.OtlpHttpClient for FakeClient with fn post(
  self,
  url,
  body,
  headers,
) {
  self.calls.push({ url, body, headers: headers.copy(), })
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
pub impl @transport.OtlpHttpClient for ShutdownAfterPostClient with fn post(
  self,
  url,
  body,
  headers,
) {
  self.calls.push({ url, body, headers: headers.copy(), })
  if self.next >= self.replies.length() {
    return Err(@transport.Request("fake client exhausted"))
  }
  let reply = self.replies[self.next]
  self.next = self.next + 1
  if self.next == self.shutdown_on_call {
    (self.after_post)()
  }
  match reply {
    FakeResponse(resp) => Ok(resp)
    FakeError(err) => Err(err)
  }
}

///|
fn test_transport(
  client : FakeClient,
  max_retries~ : Int32 = 3,
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
async test "shutdown during retry stops before next attempt" {
  let mut tx_ref : @transport.OtlpHttpTransport? = None
  let client = ShutdownAfterPostClient::{
    replies: [
      FakeResponse(response(503)),
      FakeResponse(response(503)),
      FakeResponse(response(200)),
    ],
    calls: [],
    next: 0,
    shutdown_on_call: 2,
    after_post: fn() {
      match tx_ref {
        Some(tx) => tx.shutdown()
        None => abort("transport not installed")
      }
    },
  }
  let tx = @transport.transport(
    client,
    "http://collector:4318",
    max_retries=3,
    base_backoff_ms=0,
  )
  tx_ref = Some(tx)
  match
    @async.with_timeout(1000, () => {
      tx.export_json("http://collector/v1/traces", "{}")
    }) {
    Ok(_) => abort("expected shutdown error")
    Err(err) =>
      assert_eq(
        err.to_string(),
        "request error: OTLP HTTP transport is shut down",
      )
  }
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
    events: [],
    links: [],
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
    trace_id: "",
    span_id: "",
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

///|
async test "HTTP200 partial rejection is not full success or retried" {
  let client = fake_client([
    FakeResponse({
      status_code: 200,
      body: "{\"partialSuccess\":{\"rejectedSpans\":\"2\",\"errorMessage\":\"fixture rejection\"}}",
      retry_after_ms: None,
    }),
  ])
  let outcome = unwrap_outcome(
    test_transport(client).export_json("http://fixture/v1/traces", "{}"),
  )
  assert_false(outcome.success)
  assert_retry_class(outcome.retry_class, @transport.NonRetryable)
  assert_eq(client.calls.length(), 1)
  assert_true(outcome.error is Some(_))
}

///|
async test "report retains log rejections and warning-only responses without retry" {
  for (count, success) in [("3", false), ("0", true)] {
    let client = fake_client([
      FakeResponse({
        status_code: 200,
        body: "{\"partialSuccess\":{\"rejectedLogRecords\":\"\{count}\",\"errorMessage\":\"collector message\"}}",
        retry_after_ms: None,
      }),
    ])
    let report = match test_transport(client).export_logs_report([]) {
      Ok(report) => report
      Err(error) => abort(error.to_string())
    }
    assert_eq(report.outcome.success, success)
    assert_eq(report.outcome.attempts, 1)
    assert_eq(client.calls.length(), 1)
    let details = report.partial_success.unwrap()
    assert_eq(details.error_message, "collector message")
    assert_eq(details.rejected_log_records.to_string(), count)
  }
}

///|
async test "empty success and malformed success responses are terminal" {
  for body in ["", "{}", " \n", "broken", "[]"] {
    let client = fake_client([
      FakeResponse({ status_code: 200, body, retry_after_ms: None, }),
    ])
    let result = test_transport(client).export_spans_report([])
    if body == "broken" || body == "[]" {
      assert_true(result is Err(@transport.Request(_)))
    } else {
      match result {
        Ok(report) => {
          assert_true(report.outcome.success)
          assert_true(report.partial_success is None)
        }
        Err(error) => abort(error.to_string())
      }
    }
    assert_eq(client.calls.length(), 1)
  }
}
