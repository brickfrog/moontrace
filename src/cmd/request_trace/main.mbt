///|
/// Synthetic only: no HTTP collector or request server is contacted.
struct CaptureClient {
  payloads : Array[(String, String)]
}

///|
impl @transport.OtlpHttpClient for CaptureClient with fn post(
  self,
  url,
  body,
  _headers,
) {
  @async.pause()
  self.payloads.push((url, body))
  Ok({ status_code: 200, body: "{}", retry_after_ms: None, })
}

///|
suberror RequestError {
  RequestFailure(String)
} derive(Debug)

///|
fn context(header : String, state : String) -> @moontrace.SpanContext {
  match @moontrace.parse_span_context(header, tracestate=state) {
    Ok(ctx) => ctx
    Err(error) => abort(error.to_string())
  }
}

///|
fn event_field(event : @moontrace.Event, key : String) -> String {
  for field in event.fields {
    if field.key == key {
      match field.value {
        String(value) => return value
        _ => ()
      }
    }
  }
  abort("missing string field: \{key}")
}

///|
async fn request(
  ctx : @moontrace.SpanContext,
  id : String,
  fail : Bool,
) -> String {
  @span_async.with_remote_span_async(
    ctx,
    "request",
    fields=[@moontrace.field("request_id", id)],
    server => {
      let log = @moontrace.logger(
        fields=[@moontrace.field("request_id", id)],
        span=server,
      )
      log.info("request started")
      @span_async.with_child_span_async(server, "child work", child => {
        let child_log = log.in_span(child)
        @async.pause()
        let outgoing = match @moontrace.span_context_from_span(child) {
          Ok(value) => value
          Err(error) => abort(error.to_string())
        }
        assert_eq(outgoing.trace_id.to_string(), ctx.trace_id.to_string())
        assert_eq(outgoing.trace_state.to_header(), ctx.trace_state.to_header())
        assert_eq(outgoing.is_sampled(), ctx.is_sampled())
        child_log.info("child work", fields=[
          @moontrace.field("outgoing_traceparent", outgoing.traceparent()),
          @moontrace.field(
            "outgoing_tracestate",
            outgoing.trace_state.to_header(),
          ),
        ])
        if fail {
          raise RequestFailure(id)
        }
        "ok"
      })
    },
  )
}

///|
#cfg(any(target="native", target="js"))
async fn main {
  let first = context(
    "00-11111111111111111111111111111111-1111111111111111-01", "vendor=one",
  )
  let second = context(
    "00-22222222222222222222222222222222-2222222222222222-00", "vendor=two",
  )
  let client = CaptureClient::{ payloads: [], }
  let exporter = @transport.managed_json_exporter(
    @transport.transport(client, "http://synthetic.invalid"),
  )
  let events : Array[@moontrace.Event] = []
  let spans : Array[@moontrace.Span] = []
  // This standalone process owns global subscriber setup; request context stays explicit.
  @moontrace.set_min_level(@moontrace.Info)
  @moontrace.set_subscriber(
    @moontrace.compose([exporter.subscriber(), event => events.push(event)]),
  )
  @moontrace.set_span_observer(
    @moontrace.compose_span_observers([
      exporter.span_observer(),
      @moontrace.completed_span_observer(span => spans.push(span)),
    ]),
  )
  defer {
    @moontrace.clear_subscriber()
    @moontrace.clear_span_observer()
  }
  @async.with_task_group(group => {
    group.spawn_bg(() => exporter.run())
    let success = group.spawn(() => request(first, "one", false))
    let saw_failure = Ref(false)
    ignore(request(second, "two", true)) catch {
      RequestFailure(id) => {
        assert_eq(id, "two")
        saw_failure.val = true
      }
      error => raise error
    }
    assert_true(saw_failure.val)
    assert_eq(success.wait(), "ok")
    let stats = exporter.shutdown()
    assert_eq(stats.delivered_batches, 2L)
    assert_eq(stats.failed_batches, 0L)
    assert_eq(stats.dropped_records, 0L)
    assert_eq(stats.pending_bytes, 0)
  })
  verify_exports(first, second, events, spans, client)
  println(
    "verified 2 interleaved requests, 4 correlated logs, 4 closed spans, and a handled failure",
  )
  println(
    "managed export: 2 delivered batches, 0 pending bytes; no real telemetry sent",
  )
}

///|
#cfg(not(any(target="native", target="js")))
fn main {
  println(
    "Run this synthetic request example with --target native or --target js",
  )
}
