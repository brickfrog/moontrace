///|
test "a span below the minimum level is disabled but keeps its trace" {
  let capture = @test.test_subscriber()
  let closed : Array[String] = []
  capture.with_install(() => {
    @moontrace.set_min_level(@moontrace.Info)
    @moontrace.set_span_observer(
      @moontrace.completed_span_observer(span => closed.push(span.name)),
    )
    let quiet = @moontrace.span("quiet", level=@moontrace.Debug)
    quiet.enter()
    quiet.record("k", 1)
    quiet.exit()
    let loud = @moontrace.span("loud", level=@moontrace.Info)
    loud.enter()
    loud.exit()
    assert_false(quiet.is_enabled())
    assert_true(loud.is_enabled())
    assert_eq(quiet.level, Some(@moontrace.Debug))
    assert_eq(quiet.trace_id.length(), 32)
    assert_true(@moontrace.traceparent_from_span(quiet) is Ok(_))
  })
  assert_eq(closed, ["loud"])
  // With the global minimum at Trace and the package filtered to Info,
  // lifecycle events still flow, but only for the enabled span.
  let events = @test.test_subscriber()
  events.with_install(() => {
    @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Info)
    let quiet = @moontrace.span("quiet", level=@moontrace.Debug)
    quiet.enter()
    quiet.exit()
    let unleveled = @moontrace.span("unleveled")
    unleveled.enter()
    unleveled.exit()
  })
  assert_eq(events.captured_events().map(e => e.message), [
    "span.enter unleveled", "span.exit unleveled",
  ])
}

///|
test "spans without a level are always enabled" {
  @moontrace.with_min_level(@moontrace.Error_, () => {
    assert_true(@moontrace.span("plain").is_enabled())
    assert_true(@moontrace.span("plain").level is None)
  })
}

///|
test "module filters decide span levels for the caller's package" {
  @moontrace.with_module_filter("brickfrog/moontrace", @moontrace.Warn, () => {
    assert_false(@moontrace.span("s", level=@moontrace.Info).is_enabled())
    assert_true(@moontrace.span("s", level=@moontrace.Warn).is_enabled())
    let seen = @moontrace.with_span_ctx("wrapped", level=@moontrace.Info, s => {
      s.is_enabled()
    })
    assert_false(seen)
    let child_enabled = @moontrace.with_child_span(
      @moontrace.span("root"),
      "child",
      level=@moontrace.Debug,
      s => s.is_enabled(),
    )
    assert_false(child_enabled)
  })
}

///|
test "children of disabled spans are parented to the nearest enabled ancestor" {
  let links : Array[(String, String)] = []
  @moontrace.with_trace_state(() => {
    @moontrace.set_min_level(@moontrace.Info)
    @moontrace.set_span_observer(
      @moontrace.span_lifecycle_observer(on_linked=(span, link) => {
        links.push((span.name, link.span_id))
      }),
    )
    let root = @moontrace.span("root")
    let middle = @moontrace.child_span(root, "middle", level=@moontrace.Debug)
    let deeper = @moontrace.child_span(middle, "deeper", level=@moontrace.Trace)
    let leaf = @moontrace.child_span(deeper, "leaf")
    assert_eq(middle.parent_span_id, root.span_id)
    assert_eq(deeper.parent_span_id, root.span_id)
    assert_eq(leaf.parent_span_id, root.span_id)
    assert_eq(leaf.trace_id, root.trace_id)
    assert_eq(links, [("leaf", root.span_id)])

    let quiet_root = @moontrace.span("quiet-root", level=@moontrace.Debug)
    let orphan = @moontrace.child_span(quiet_root, "orphan")
    assert_eq(orphan.parent_span_id, "")
    assert_eq(orphan.trace_id, quiet_root.trace_id)
    assert_eq(links.length(), 1)
  })
}

///|
test "remote spans honor levels and keep propagating" {
  let ctx = match
    @moontrace.parse_traceparent(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
    ) {
    Ok(ctx) => ctx
    Err(err) => abort("\{err}")
  }
  @moontrace.with_min_level(@moontrace.Warn, () => {
    let server = @moontrace.span_from_remote_context(
      ctx,
      "server",
      level=@moontrace.Info,
    )
    assert_false(server.is_enabled())
    assert_true(server.is_sampled())
    assert_eq(server.trace_id, ctx.trace_id)
    let headers : Map[String, String] = Map([])
    assert_true(@moontrace.inject_span_headers(headers, server))
  })
}
