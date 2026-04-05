///|
fn main {
  // One-liner console setup
  @console.initialize()

  // Structured events
  @moontrace.info("server started", fields=[
    @moontrace.field("port", 8080),
    @moontrace.field("env", "dev"),
  ])

  // Spans with duration tracking
  @moontrace.with_span_ctx("handle_request", fn(parent) {
    @moontrace.info("processing request", fields=[
      @moontrace.field("method", "GET"),
      @moontrace.field("path", "/api/users"),
    ])

    // Nested child span
    @moontrace.with_child_span(parent, "db_query", fn(s) {
      s.record("table", "users")
      @moontrace.debug("query executed", fields=[@moontrace.field("rows", 42)])
    })
  })

  @moontrace.warn("shutting down")
}
