///|
fn sampler_test_context(traceparent : String) -> @moontrace.SpanContext {
  match @moontrace.parse_traceparent(traceparent) {
    Ok(ctx) => ctx
    Err(err) => abort("invalid traceparent: \{err}")
  }
}

///|
fn sampler_test_traceparent(span : @moontrace.Span) -> String {
  match @moontrace.traceparent_from_span(span) {
    Ok(header) => header
    Err(err) => abort("invalid span context: \{err}")
  }
}

///|
test "always-off sampler keeps ids and propagation but skips observers" {
  @moontrace.with_trace_state(() => {
    let observed : Array[String] = []
    @moontrace.set_span_observer(
      @moontrace.span_lifecycle_observer(
        on_created=span => observed.push("created \{span.name}"),
        on_entered=span => observed.push("entered \{span.name}"),
        on_recorded=(span, _) => observed.push("recorded \{span.name}"),
        on_exited=span => observed.push("exited \{span.name}"),
        on_closed=span => observed.push("closed \{span.name}"),
        on_linked=(span, _) => observed.push("linked \{span.name}"),
      ),
    )
    @moontrace.set_span_sampler(@moontrace.always_off_sampler())
    let root = @moontrace.span("root")
    let child = @moontrace.child_span(root, "child")
    child.enter()
    child.record("k", 1)
    child.add_event("evt")
    child.exit()
    root.enter()
    root.exit()

    assert_false(root.is_sampled())
    assert_false(child.is_sampled())
    assert_eq(root.trace_id.length(), 32)
    assert_eq(child.trace_id, root.trace_id)
    assert_eq(child.parent_span_id, root.span_id)
    assert_true(sampler_test_traceparent(child).has_suffix("-00"))
    assert_eq(observed, [])
  })
}

///|
test "sampled spans still reach observers" {
  @moontrace.with_trace_state(() => {
    let closed : Array[String] = []
    @moontrace.set_span_observer(
      @moontrace.completed_span_observer(span => closed.push(span.name)),
    )
    let root = @moontrace.span("root")
    root.enter()
    root.exit()
    assert_true(root.is_sampled())
    assert_eq(closed, ["root"])
  })
}

///|
test "parent-based sampler honors local and remote parents" {
  @moontrace.with_span_sampler(
    @moontrace.parent_based_sampler(@moontrace.always_off_sampler()),
    () => {
      let root = @moontrace.span("root")
      assert_false(root.is_sampled())
      assert_false(@moontrace.child_span(root, "child").is_sampled())

      let sampled_remote = @moontrace.span_from_remote_context(
        sampler_test_context(
          "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
        ),
        "server",
      )
      assert_true(sampled_remote.is_sampled())
      assert_true(@moontrace.child_span(sampled_remote, "child").is_sampled())

      let unsampled_remote = @moontrace.span_from_remote_context(
        sampler_test_context(
          "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
        ),
        "server",
      )
      assert_false(unsampled_remote.is_sampled())
    },
  )
}

///|
test "non-parent-based sampler can override the parent decision" {
  @moontrace.with_span_sampler(@moontrace.always_on_sampler(), () => {
    let remote = @moontrace.span_from_remote_context(
      sampler_test_context(
        "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
      ),
      "server",
    )
    assert_true(remote.is_sampled())
  })
}

///|
test "trace-id ratio sampler agrees with the event trace sampler" {
  let ids = [
    "00000000000000000000000000000001", "0af7651916cd43dd8448eb211c80319c", "4bf92f3577b34da6a3ce929d0e0e4736",
    "aabbccdd11223344aabbccdd11223344", "ffffffffffffffffffffffffffffffff", "0123456789abcdef0123456789abcdef",
    "fedcba9876543210fedcba9876543210", "11111111111111111111111111111111", "22222222222222222222222222222222",
    "33333333333333333333333333333333", "44444444444444444444444444444444", "55555555555555555555555555555555",
  ]
  @moontrace.with_span_sampler(@moontrace.trace_id_ratio_sampler(0.5), () => {
    let decisions = ids.map(id => {
      @moontrace.span_with_trace("op", id).is_sampled()
    })
    for i, id in ids {
      assert_eq(decisions[i], @moontrace.should_sample_trace(id, 0.5))
      assert_eq(
        @moontrace.span_with_trace("again", id).is_sampled(),
        decisions[i],
      )
    }
    assert_true(decisions.contains(true))
    assert_true(decisions.contains(false))
  })
  @moontrace.with_span_sampler(@moontrace.trace_id_ratio_sampler(0.0), () => {
    assert_false(@moontrace.span("none").is_sampled())
  })
  @moontrace.with_span_sampler(@moontrace.trace_id_ratio_sampler(1.0), () => {
    assert_true(@moontrace.span("all").is_sampled())
  })
}

///|
test "custom sampler receives span creation input" {
  let inputs : Array[@moontrace.SamplingInput] = []
  @moontrace.with_span_sampler(
    @moontrace.span_sampler(input => {
      inputs.push(input)
      input.name != "drop"
    }),
    () => {
      let root = @moontrace.span(
        "root",
        fields=[@moontrace.field("route", "/x")],
        kind=@moontrace.Server,
      )
      let dropped = @moontrace.child_span(root, "drop", kind=@moontrace.Client)
      let _ = @moontrace.span_from_remote_context(
        sampler_test_context(
          "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-00",
        ),
        "remote",
      )
      assert_true(root.is_sampled())
      assert_false(dropped.is_sampled())
    },
  )
  assert_eq(inputs.length(), 3)
  assert_eq(inputs[0].name, "root")
  assert_eq(inputs[0].kind, @moontrace.Server)
  assert_eq(inputs[0].fields.length(), 1)
  assert_true(inputs[0].parent is None)
  assert_false(inputs[0].parent_is_remote)
  assert_eq(inputs[1].kind, @moontrace.Client)
  assert_eq(inputs[1].trace_id, inputs[0].trace_id)
  assert_true(inputs[1].parent is Some(flags) && flags.is_sampled())
  assert_false(inputs[1].parent_is_remote)
  assert_eq(inputs[2].trace_id, "4bf92f3577b34da6a3ce929d0e0e4736")
  assert_true(inputs[2].parent is Some(flags) && !flags.is_sampled())
  assert_true(inputs[2].parent_is_remote)
}

///|
test "span sampler is restored by scoped helpers" {
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_sampler(@moontrace.always_off_sampler())
    assert_false(@moontrace.span("inside").is_sampled())
  })
  assert_true(@moontrace.span("after").is_sampled())
  @moontrace.with_span_sampler(@moontrace.always_off_sampler(), () => {
    @moontrace.reset_span_sampler()
    assert_true(@moontrace.span("reset").is_sampled())
  })
}
