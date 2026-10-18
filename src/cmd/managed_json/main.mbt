///|
/// A synthetic client makes this example runnable without a collector/network.
struct DemoClient {
  mut requests : Int32
}

///|
impl @transport.OtlpHttpClient for DemoClient with fn post(
  self,
  _url,
  _body,
  _headers,
) {
  @async.sleep(5)
  self.requests += 1
  Ok({ status_code: 200, body: "{}", retry_after_ms: None, })
}

///|
#cfg(any(target="native", target="js"))
async fn main {
  let client = DemoClient::{ requests: 0, }
  let tx = @transport.transport(client, "http://synthetic.invalid")
  let exporter = @transport.managed_json_exporter(tx, flush_interval_ms=20)
  @async.with_task_group(group => {
    group.spawn_bg(() => exporter.run())
    // Scope synchronous instrumentation so global subscribers are restored.
    @moontrace.with_trace_state(() => {
      @moontrace.set_subscriber(exporter.subscriber())
      @moontrace.set_span_observer(exporter.span_observer())
      @moontrace.info("synthetic startup")
      @moontrace.with_span("synthetic request", () => {
        @moontrace.info("synthetic work")
      })
    })
    // A barrier waits for terminal outcomes, which may include failures/drops.
    let flushed = exporter.flush()
    println("delivered batches: \{flushed.delivered_batches}")
    let stopped = exporter.shutdown()
    println("pending bytes after shutdown: \{stopped.pending_bytes}")
  })
  println("synthetic HTTP calls: \{client.requests}")
}

///|
#cfg(not(any(target="native", target="js")))
fn main {
  println("Run the managed JSON example with --target native or --target js")
}
