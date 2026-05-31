///|
fn expect_context(
  result : Result[@moontrace.SpanContext, @moontrace.TraceContextError],
) -> @moontrace.SpanContext {
  match result {
    Ok(ctx) => ctx
    Err(err) => abort("expected SpanContext, got \{err}")
  }
}

///|
fn expect_state(
  result : Result[@moontrace.TraceState, @moontrace.TraceContextError],
) -> @moontrace.TraceState {
  match result {
    Ok(state) => state
    Err(err) => abort("expected TraceState, got \{err}")
  }
}

///|
fn expect_header(
  result : Result[String, @moontrace.TraceContextError],
) -> String {
  match result {
    Ok(header) => header
    Err(err) => abort("expected header, got \{err}")
  }
}

///|
fn assert_context_err(
  result : Result[@moontrace.SpanContext, @moontrace.TraceContextError],
) -> Unit {
  match result {
    Ok(ctx) => abort("expected error, got \{ctx.traceparent()}")
    Err(_) => ()
  }
}

///|
fn assert_trace_id_err(
  result : Result[@moontrace.TraceId, @moontrace.TraceContextError],
) -> Unit {
  match result {
    Ok(id) => abort("expected trace id error, got \{id}")
    Err(_) => ()
  }
}

///|
fn assert_span_id_err(
  result : Result[@moontrace.SpanId, @moontrace.TraceContextError],
) -> Unit {
  match result {
    Ok(id) => abort("expected span id error, got \{id}")
    Err(_) => ()
  }
}

///|
fn assert_flags_err(
  result : Result[@moontrace.TraceFlags, @moontrace.TraceContextError],
) -> Unit {
  match result {
    Ok(flags) => abort("expected flags error, got \{flags}")
    Err(_) => ()
  }
}

///|
fn assert_state_err(
  result : Result[@moontrace.TraceState, @moontrace.TraceContextError],
) -> Unit {
  match result {
    Ok(state) => abort("expected tracestate error, got \{state.to_header()}")
    Err(_) => ()
  }
}

///|
fn make_tracestate_header(count : Int) -> String {
  let buf = StringBuilder()
  for i in 0..<count {
    if i > 0 {
      buf.write_string(",")
    }
    buf.write_string("k")
    buf.write_string(i.to_string())
    buf.write_string("=v")
    buf.write_string(i.to_string())
  }
  buf.to_string()
}

///|
test "traceparent parses and formats sampled context" {
  let header = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01"
  let ctx = expect_context(@moontrace.parse_traceparent(header))
  assert_eq(ctx.trace_id, "4bf92f3577b34da6a3ce929d0e0e4736")
  assert_eq(ctx.span_id, "00f067aa0ba902b7")
  assert_true(ctx.is_remote())
  assert_true(ctx.is_sampled())
  assert_eq(ctx.trace_flags_int(), 1)
  assert_eq(@moontrace.format_traceparent(ctx), header)

  let reparsed = expect_context(@moontrace.parse_traceparent(ctx.traceparent()))
  assert_eq(reparsed.trace_id, ctx.trace_id)
  assert_eq(reparsed.span_id, ctx.span_id)
  assert_eq(reparsed.trace_flags_int(), ctx.trace_flags_int())
}

///|
test "traceparent parses and formats unsampled context" {
  let header = "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00"
  let ctx = expect_context(@moontrace.parse_traceparent(header))
  assert_true(!ctx.is_sampled())
  assert_eq(ctx.trace_flags_int(), 0)
  assert_eq(@moontrace.format_traceparent(ctx), header)
}

///|
test "traceparent parses higher versions with extra fields" {
  let ctx = expect_context(
    @moontrace.parse_traceparent(
      "01-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-03-extra",
    ),
  )
  assert_eq(ctx.trace_id, "4bf92f3577b34da6a3ce929d0e0e4736")
  assert_eq(ctx.span_id, "00f067aa0ba902b7")
  assert_true(ctx.is_sampled())
  assert_eq(ctx.trace_flags_int(), 3)
  assert_eq(
    ctx.traceparent(),
    "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-03",
  )
}

///|
test "traceparent parses higher versions without extra fields" {
  let ctx = expect_context(
    @moontrace.parse_traceparent(
      "02-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
    ),
  )
  assert_eq(ctx.trace_id, "4bf92f3577b34da6a3ce929d0e0e4736")
  assert_eq(ctx.span_id, "00f067aa0ba902b7")
  assert_true(!ctx.is_sampled())
  assert_eq(ctx.trace_flags_int(), 0)
}

///|
test "invalid traceparent headers are structured errors" {
  assert_context_err(@moontrace.parse_traceparent("00-too-short"))
  assert_context_err(
    @moontrace.parse_traceparent(
      "00-00000000000000000000000000000000-00f067aa0ba902b7-01",
    ),
  )
  assert_context_err(
    @moontrace.parse_traceparent(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-0000000000000000-01",
    ),
  )
  assert_context_err(
    @moontrace.parse_traceparent(
      "00-4BF92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    ),
  )
  assert_context_err(
    @moontrace.parse_traceparent(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-zz",
    ),
  )
  assert_context_err(
    @moontrace.parse_traceparent(
      "ff-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    ),
  )
  assert_context_err(
    @moontrace.parse_traceparent(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01-extra",
    ),
  )
}

///|
test "id and flag constructors reject invalid values" {
  assert_trace_id_err(
    @moontrace.TraceId::parse("00000000000000000000000000000000"),
  )
  assert_trace_id_err(
    @moontrace.TraceId::parse("4BF92f3577b34da6a3ce929d0e0e4736"),
  )
  assert_trace_id_err(
    @moontrace.TraceId::parse("4bf92f3577b34da6a3ce929d0e0e47"),
  )
  assert_span_id_err(@moontrace.SpanId::parse("0000000000000000"))
  assert_span_id_err(@moontrace.SpanId::parse("00F067aa0ba902b7"))
  assert_span_id_err(@moontrace.SpanId::parse("00f067aa0ba902"))
  assert_flags_err(@moontrace.TraceFlags::from_int(-1))
  assert_flags_err(@moontrace.TraceFlags::from_int(256))
  assert_flags_err(@moontrace.TraceFlags::from_hex("0G"))
}

///|
test "tracestate parses whitespace and duplicate keys with last write winning" {
  let state = expect_state(
    @moontrace.parse_tracestate(
      " rojo=00f067aa0ba902b7,\tcongo=t61rcWkgMzE ,rojo=latest",
    ),
  )
  assert_eq(state.len(), 2)
  @debug.assert_eq(state.get("rojo"), Some("latest"))
  @debug.assert_eq(state.get("congo"), Some("t61rcWkgMzE"))
  assert_eq(state.to_header(), "congo=t61rcWkgMzE,rojo=latest")

  let reparsed = expect_state(@moontrace.parse_tracestate(state.to_header()))
  assert_eq(reparsed.to_header(), state.to_header())
}

///|
test "tracestate constructors preserve order and validate entries" {
  let state = expect_state(
    @moontrace.TraceState::from_entries([
      @moontrace.TraceStateEntry::{ key: "rojo", value: "first" },
      @moontrace.TraceStateEntry::{ key: "congo", value: "two" },
      @moontrace.TraceStateEntry::{ key: "rojo", value: "second" },
    ]),
  )
  assert_eq(state.to_header(), "congo=two,rojo=second")
  let updated = expect_state(state.set("tenant@sys", "opaque"))
  assert_eq(updated.to_header(), "congo=two,rojo=second,tenant@sys=opaque")
}

///|
test "invalid tracestate headers are structured errors" {
  assert_state_err(@moontrace.parse_tracestate(make_tracestate_header(33)))
  assert_state_err(@moontrace.parse_tracestate("Rojo=value"))
  assert_state_err(@moontrace.parse_tracestate("ro jo=value"))
  assert_state_err(@moontrace.parse_tracestate("rojo=value=bad"))
  assert_state_err(@moontrace.parse_tracestate("rojo=bad\tvalue"))
  assert_state_err(
    @moontrace.TraceState::from_entries([
      @moontrace.TraceStateEntry::{ key: "rojo", value: "" },
    ]),
  )
}

///|
test "empty and whitespace-only tracestate parse as empty" {
  assert_true(expect_state(@moontrace.parse_tracestate("")).is_empty())
  assert_true(expect_state(@moontrace.parse_tracestate("  \t , , ")).is_empty())
  assert_eq(@moontrace.format_tracestate(@moontrace.TraceState::empty()), "")
}

///|
test "remote context creates child span and preserves propagation data" {
  let remote = expect_context(
    @moontrace.parse_span_context(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
      tracestate="rojo=00f067aa0ba902b7,congo=t61rcWkgMzE",
    ),
  )
  let created_names : Array[String] = []
  let created_sampled : Array[Bool] = []
  let link_kinds : Array[String] = []
  let link_span_ids : Array[String] = []
  let source_parent_ids : Array[String] = []
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(
      on_created=fn(span) {
        created_names.push(span.name)
        match @moontrace.span_context_from_span(span) {
          Ok(ctx) => created_sampled.push(ctx.is_sampled())
          Err(_) => created_sampled.push(false)
        }
      },
      on_linked=fn(span, link) {
        link_kinds.push(link.kind.to_string())
        link_span_ids.push(link.span_id)
        source_parent_ids.push(span.parent_span_id)
      },
    ),
  )

  let child = @moontrace.span_from_remote_context(remote, "server")
  @moontrace.clear_span_observer()

  assert_eq(child.trace_id, remote.trace_id)
  assert_eq(child.parent_span_id, remote.span_id)
  assert_true(child.span_id != remote.span_id)
  assert_eq(child.active, false)
  @debug.assert_eq(created_names, ["server"])
  @debug.assert_eq(created_sampled, [true])
  @debug.assert_eq(link_kinds, ["CHILD_OF"])
  @debug.assert_eq(link_span_ids, [remote.span_id])
  @debug.assert_eq(source_parent_ids, [remote.span_id])

  let outbound = expect_context(@moontrace.span_context_from_span(child))
  assert_true(!outbound.is_remote())
  assert_true(outbound.is_sampled())
  assert_eq(outbound.trace_id, remote.trace_id)
  assert_eq(outbound.span_id, child.span_id)
  @debug.assert_eq(outbound.trace_state.get("rojo"), Some("00f067aa0ba902b7"))
  assert_eq(
    expect_header(@moontrace.traceparent_from_span(child)),
    "00-\{remote.trace_id}-\{child.span_id}-01",
  )
}

///|
test "sampled and unsampled remote propagation round trip" {
  let sampled = expect_context(
    @moontrace.parse_traceparent(
      "00-aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa-bbbbbbbbbbbbbbbb-01",
    ),
  )
  let unsampled = expect_context(
    @moontrace.parse_traceparent(
      "00-cccccccccccccccccccccccccccccccc-dddddddddddddddd-00",
    ),
  )

  let sampled_child = @moontrace.span_from_remote_context(sampled, "sampled")
  let unsampled_child = @moontrace.span_from_remote_context(
    unsampled, "unsampled",
  )
  let sampled_out = expect_context(
    @moontrace.parse_traceparent(
      expect_header(@moontrace.traceparent_from_span(sampled_child)),
    ),
  )
  let unsampled_out = expect_context(
    @moontrace.parse_traceparent(
      expect_header(@moontrace.traceparent_from_span(unsampled_child)),
    ),
  )

  assert_eq(sampled_out.trace_id, sampled.trace_id)
  assert_true(sampled_out.is_sampled())
  assert_eq(unsampled_out.trace_id, unsampled.trace_id)
  assert_true(!unsampled_out.is_sampled())
}

///|
test "span_with_trace remains backwards compatible" {
  let trace_id = "aabbccdd11223344aabbccdd11223344"
  let s = @moontrace.span_with_trace("custom", trace_id)
  assert_eq(s.trace_id, trace_id)
  assert_eq(s.span_id.length(), 16)
  assert_eq(s.parent_span_id, "")
  assert_eq(s.name, "custom")

  let ctx = expect_context(@moontrace.span_context_from_span(s))
  assert_eq(ctx.trace_id, trace_id)
  assert_eq(ctx.span_id, s.span_id)
  assert_true(!ctx.is_sampled())
  assert_eq(
    expect_header(@moontrace.traceparent_from_span(s)),
    ctx.traceparent(),
  )
}
