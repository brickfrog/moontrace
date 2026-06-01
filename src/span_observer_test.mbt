///|
test "span lifecycle observer ordering" {
  let observed : Array[String] = []
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(
      on_created=fn(span) { observed.push("created:\{span.name}") },
      on_entered=fn(span) { observed.push("entered:\{span.name}") },
      on_recorded=fn(_span, field) { observed.push("recorded:\{field.key}") },
      on_exited=fn(span) { observed.push("exited:\{span.name}") },
      on_closed=fn(span) { observed.push("closed:\{span.name}") },
    ),
  )

  let s = @moontrace.span("work")
  s.enter()
  s.record("late", "field")
  s.exit()
  @moontrace.clear_span_observer()

  assert_eq(observed.length(), 5)
  assert_eq(observed[0], "created:work")
  assert_eq(observed[1], "entered:work")
  assert_eq(observed[2], "recorded:late")
  assert_eq(observed[3], "exited:work")
  assert_eq(observed[4], "closed:work")
}

///|
test "record after enter is visible to record and close observers only" {
  let entered_field_counts : Array[Int] = []
  let recorded_field_counts : Array[Int] = []
  let closed_field_counts : Array[Int] = []
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(
      on_entered=fn(span) { entered_field_counts.push(span.fields.length()) },
      on_recorded=fn(span, _field) {
        recorded_field_counts.push(span.fields.length())
      },
      on_closed=fn(span) { closed_field_counts.push(span.fields.length()) },
    ),
  )

  let s = @moontrace.span("snap")
  s.enter()
  s.record("late", "field")
  s.exit()
  @moontrace.clear_span_observer()

  assert_eq(entered_field_counts.length(), 1)
  assert_eq(recorded_field_counts.length(), 1)
  assert_eq(closed_field_counts.length(), 1)
  assert_eq(entered_field_counts[0], 0)
  assert_eq(recorded_field_counts[0], 1)
  assert_eq(closed_field_counts[0], 1)
}

///|
test "span observer enter exit and close hooks are single-use after close" {
  let observed : Array[String] = []
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(
      on_created=fn(_span) { observed.push("created") },
      on_entered=fn(_span) { observed.push("entered") },
      on_exited=fn(_span) { observed.push("exited") },
      on_closed=fn(_span) { observed.push("closed") },
    ),
  )

  let s = @moontrace.span("once")
  s.enter()
  s.enter()
  s.exit()
  s.enter()
  s.exit()
  s.exit()
  @moontrace.clear_span_observer()

  assert_eq(observed.length(), 4)
  assert_eq(observed[0], "created")
  assert_eq(observed[1], "entered")
  assert_eq(observed[2], "exited")
  assert_eq(observed[3], "closed")
}

///|
test "with_child_span emits child parent link observer event" {
  let source_names : Array[String] = []
  let link_kinds : Array[String] = []
  let target_span_ids : Array[String] = []
  let source_parent_ids : Array[String] = []
  let mut parent_span_id = ""
  let mut child_parent_id = ""
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(on_linked=fn(span, link) {
      source_names.push(span.name)
      link_kinds.push(link.kind.to_string())
      target_span_ids.push(link.span_id)
      source_parent_ids.push(span.parent_span_id)
    }),
  )

  @moontrace.with_span_ctx("parent", fn(parent) {
    parent_span_id = parent.span_id
    @moontrace.with_child_span(parent, "child", fn(child) {
      child_parent_id = child.parent_span_id
    })
  })
  @moontrace.clear_span_observer()

  assert_eq(source_names.length(), 1)
  assert_eq(source_names[0], "child")
  assert_eq(link_kinds[0], "CHILD_OF")
  assert_eq(target_span_ids[0], parent_span_id)
  assert_eq(source_parent_ids[0], parent_span_id)
  assert_eq(child_parent_id, parent_span_id)
}

///|
test "child_span creates linked child span without entering it" {
  let source_names : Array[String] = []
  let link_kinds : Array[String] = []
  let target_span_ids : Array[String] = []
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(on_linked=fn(span, link) {
      source_names.push(span.name)
      link_kinds.push(link.kind.to_string())
      target_span_ids.push(link.span_id)
    }),
  )

  let parent = @moontrace.span("parent")
  let child = @moontrace.child_span(parent, "child")
  @moontrace.clear_span_observer()

  assert_eq(child.trace_id, parent.trace_id)
  assert_eq(child.parent_span_id, parent.span_id)
  assert_eq(child.active, false)
  assert_eq(source_names.length(), 1)
  assert_eq(source_names[0], "child")
  assert_eq(link_kinds[0], "CHILD_OF")
  assert_eq(target_span_ids[0], parent.span_id)
}

///|
test "span link and follows_from notify observer with records" {
  let link_kinds : Array[String] = []
  let target_span_ids : Array[String] = []
  let field_keys : Array[String] = []
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(on_linked=fn(_span, link) {
      link_kinds.push(link.kind.to_string())
      target_span_ids.push(link.span_id)
      if !link.fields.is_empty() {
        field_keys.push(link.fields[0].key)
      }
    }),
  )

  let predecessor = @moontrace.span("predecessor")
  let current = @moontrace.span("current")
  current.link(predecessor, fields=[@moontrace.field("edge", "linked")])
  current.follows_from(predecessor, fields=[@moontrace.field("reason", "retry")])
  @moontrace.clear_span_observer()

  assert_eq(current.links.length(), 2)
  assert_eq(current.links[0].kind.to_string(), "LINK")
  assert_eq(current.links[1].kind.to_string(), "FOLLOWS_FROM")
  assert_eq(current.links[0].span_id, predecessor.span_id)
  assert_eq(current.links[1].span_id, predecessor.span_id)
  assert_eq(current.links[0].fields[0].key, "edge")
  assert_eq(current.links[1].fields[0].key, "reason")
  assert_eq(link_kinds.length(), 2)
  assert_eq(link_kinds[0], "LINK")
  assert_eq(link_kinds[1], "FOLLOWS_FROM")
  assert_eq(target_span_ids[0], predecessor.span_id)
  assert_eq(target_span_ids[1], predecessor.span_id)
  assert_eq(field_keys[0], "edge")
  assert_eq(field_keys[1], "reason")
}

///|
test "child parent edge is not retained as a span link" {
  let parent = @moontrace.span("parent")
  let explicit = @moontrace.span("explicit")
  let child = @moontrace.child_span(parent, "child")
  child.link(explicit, fields=[@moontrace.field("edge", "explicit")])

  assert_eq(child.parent_span_id, parent.span_id)
  assert_eq(child.links.length(), 1)
  assert_eq(child.links[0].kind.to_string(), "LINK")
  assert_eq(child.links[0].span_id, explicit.span_id)
  assert_eq(child.links[0].fields[0].key, "edge")
}

///|
fn observer_expect_context(
  result : Result[@moontrace.SpanContext, @moontrace.TraceContextError],
) -> @moontrace.SpanContext {
  match result {
    Ok(ctx) => ctx
    Err(err) => abort("expected SpanContext, got \{err}")
  }
}

///|
test "span link_context retains remote context identity and tracestate" {
  let remote = observer_expect_context(
    @moontrace.parse_span_context(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
      tracestate="rojo=00f067aa0ba902b7,congo=t61rcWkgMzE",
    ),
  )
  let link_kinds : Array[String] = []
  let trace_states : Array[String] = []
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(on_linked=fn(_span, link) {
      link_kinds.push(link.kind.to_string())
      trace_states.push(link.trace_state)
    }),
  )

  let current = @moontrace.span("current")
  current.link_context(remote, fields=[@moontrace.field("edge", "remote")])
  @moontrace.clear_span_observer()

  assert_eq(current.links.length(), 1)
  assert_eq(current.links[0].trace_id, remote.trace_id)
  assert_eq(current.links[0].span_id, remote.span_id)
  assert_eq(
    current.links[0].trace_state,
    "rojo=00f067aa0ba902b7,congo=t61rcWkgMzE",
  )
  assert_eq(current.links[0].fields[0].key, "edge")
  assert_eq(link_kinds.length(), 1)
  assert_eq(link_kinds[0], "LINK")
  assert_eq(trace_states[0], "rojo=00f067aa0ba902b7,congo=t61rcWkgMzE")
}

///|
test "completed span observer captures closed span without event subscriber" {
  let names : Array[String] = []
  let active_states : Array[Bool] = []
  let field_counts : Array[Int] = []
  @moontrace.set_span_observer(
    @moontrace.completed_span_observer(fn(span) {
      names.push(span.name)
      active_states.push(span.active)
      field_counts.push(span.fields.length())
    }),
  )

  let s = @moontrace.span("complete")
  s.enter()
  s.record("key", "value")
  s.exit()
  @moontrace.clear_span_observer()

  assert_eq(names.length(), 1)
  assert_eq(names[0], "complete")
  assert_eq(active_states[0], false)
  assert_eq(field_counts[0], 1)
}

///|
test "span observer coexists with event subscriber" {
  let observed : Array[String] = []
  let events : Array[String] = []
  @moontrace.set_span_observer(
    @moontrace.span_lifecycle_observer(
      on_created=fn(_span) { observed.push("created") },
      on_entered=fn(_span) { observed.push("entered") },
      on_exited=fn(_span) { observed.push("exited") },
      on_closed=fn(_span) { observed.push("closed") },
    ),
  )
  @moontrace.set_subscriber(fn(event) { events.push(event.message) })

  let s = @moontrace.span("coexist")
  s.enter()
  s.exit()
  @moontrace.clear_subscriber()
  @moontrace.clear_span_observer()

  assert_eq(observed.length(), 4)
  assert_eq(events.length(), 2)
  assert_eq(events[0], "span.enter coexist")
  assert_eq(events[1], "span.exit coexist")
}
