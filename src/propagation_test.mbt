///|
fn propagation_ctx(sampled : Bool) -> @moontrace.SpanContext {
  match
    @moontrace.parse_span_context(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-\{if sampled { "01" } else { "00" }}",
      tracestate="vendor=opaque",
    ) {
    Ok(ctx) => ctx
    Err(err) => abort("\{err}")
  }
}

///|
test "W3C inject and extract round trip with baggage" {
  let headers : Map[String, String] = { "TraceParent": "stale", "other": "x" }
  let baggage = @moontrace.Baggage::empty().set("user", "ann")
  @moontrace.inject_headers(headers, propagation_ctx(true), baggage~)
  assert_eq(headers.get("TraceParent"), None)
  assert_eq(
    headers.get("traceparent"),
    Some("00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"),
  )
  assert_eq(headers.get("tracestate"), Some("vendor=opaque"))
  assert_eq(headers.get("baggage"), Some("user=ann"))
  assert_eq(headers.get("other"), Some("x"))

  let (ctx, extracted) = @moontrace.extract_headers({
    "TRACEPARENT": headers.get("traceparent").unwrap(),
    "TraceState": "vendor=opaque",
    "Baggage": "user=ann",
  })
  guard ctx is Some(ctx) else { fail("expected context") }
  assert_eq(ctx.trace_id, "4bf92f3577b34da6a3ce929d0e0e4736")
  assert_true(ctx.is_sampled())
  assert_true(ctx.is_remote())
  assert_eq(ctx.trace_state.get("vendor"), Some("opaque"))
  assert_eq(extracted.get("user"), Some("ann"))
}

///|
test "extract returns no context for missing or invalid headers" {
  let (none, baggage) = @moontrace.extract_headers(Map([]))
  assert_true(none is None)
  assert_true(baggage.is_empty())
  let (bad, _) = @moontrace.extract_headers({ "traceparent": "garbage" })
  assert_true(bad is None)
  let (bad_b3, _) = @moontrace.extract_headers({ "b3": "zz-yy-1" })
  assert_true(bad_b3 is None)
}

///|
test "B3 single header inject and extract" {
  let headers : Map[String, String] = Map([])
  @moontrace.inject_headers(headers, propagation_ctx(true), format=B3Single)
  assert_eq(
    headers.get("b3"),
    Some("4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-1"),
  )
  assert_eq(headers.get("traceparent"), None)
  let (ctx, _) = @moontrace.extract_headers(headers)
  guard ctx is Some(ctx) else { fail("expected context") }
  assert_eq(ctx.span_id, "00f067aa0ba902b7")
  assert_true(ctx.is_sampled())

  let (short, _) = @moontrace.extract_headers({
    "b3": "A3CE929D0E0E4736-00F067AA0BA902B7-d-05e3ac9a4f6e3b90",
  })
  guard short is Some(short) else { fail("expected context") }
  assert_eq(short.trace_id, "0000000000000000a3ce929d0e0e4736")
  assert_true(short.is_sampled())
  let (deferred, _) = @moontrace.extract_headers({
    "b3": "a3ce929d0e0e4736-00f067aa0ba902b7",
  })
  guard deferred is Some(deferred) else { fail("expected context") }
  assert_false(deferred.is_sampled())
}

///|
test "B3 multi headers inject and extract" {
  let headers : Map[String, String] = Map([])
  @moontrace.inject_headers(headers, propagation_ctx(false), format=B3Multi)
  assert_eq(
    headers.get("X-B3-TraceId"),
    Some("4bf92f3577b34da6a3ce929d0e0e4736"),
  )
  assert_eq(headers.get("X-B3-SpanId"), Some("00f067aa0ba902b7"))
  assert_eq(headers.get("X-B3-Sampled"), Some("0"))
  let (ctx, _) = @moontrace.extract_headers(headers)
  guard ctx is Some(ctx) else { fail("expected context") }
  assert_false(ctx.is_sampled())
  let (debug, _) = @moontrace.extract_headers({
    "x-b3-traceid": "4bf92f3577b34da6a3ce929d0e0e4736",
    "x-b3-spanid": "00f067aa0ba902b7",
    "x-b3-flags": "1",
  })
  guard debug is Some(debug) else { fail("expected context") }
  assert_true(debug.is_sampled())
}

///|
test "W3C takes precedence over B3 on extract" {
  let (ctx, _) = @moontrace.extract_headers({
    "traceparent": "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    "b3": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-1",
  })
  guard ctx is Some(ctx) else { fail("expected context") }
  assert_eq(ctx.trace_id, "4bf92f3577b34da6a3ce929d0e0e4736")
}

///|
test "inject_span_headers propagates a local span" {
  let span = @moontrace.span("client")
  let headers : Map[String, String] = Map([])
  assert_true(@moontrace.inject_span_headers(headers, span))
  let (ctx, _) = @moontrace.extract_headers(headers)
  guard ctx is Some(ctx) else { fail("expected context") }
  assert_eq(ctx.trace_id, span.trace_id)
  assert_eq(ctx.span_id, span.span_id)
  let invalid = { ..span, trace_id: "nope", }
  let untouched : Map[String, String] = Map([])
  assert_false(@moontrace.inject_span_headers(untouched, invalid))
  assert_eq(untouched.length(), 0)
}
