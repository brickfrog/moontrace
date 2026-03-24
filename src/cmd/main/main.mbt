///|
fn main {
  // One-liner console setup
  @console.initialize()

  // Structured events
  @moontrace.info(
    "server started",
    fields=@moontrace.fields([
      ("port", (8080).to_json()),
      ("env", "dev".to_json()),
    ]),
  )

  // Spans with duration tracking
  @moontrace.with_span_ctx("handle_request", fn(parent) {
    @moontrace.info(
      "processing request",
      fields=@moontrace.fields([
        ("method", "GET".to_json()),
        ("path", "/api/users".to_json()),
      ]),
    )

    // Nested child span
    @moontrace.with_child_span(parent, "db_query", fn(s) {
      s.record("table", "users".to_json())
      @moontrace.debug(
        "query executed",
        fields=@moontrace.fields([("rows", (42).to_json())]),
      )
    })
  })

  @moontrace.warn("shutting down")
}
