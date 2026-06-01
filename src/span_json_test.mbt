///|
fn span_json_object(json : Json, label : String) -> Map[String, Json] {
  match json {
    Object(obj) => obj
    _ => abort("expected JSON object for \{label}")
  }
}

///|
fn span_json_field(obj : Map[String, Json], key : String) -> Json {
  match obj.get(key) {
    Some(value) => value
    None => abort("missing JSON field \{key}")
  }
}

///|
fn span_json_array(json : Json, label : String) -> Array[Json] {
  match json {
    Array(items) => items
    _ => abort("expected JSON array for \{label}")
  }
}

///|
fn assert_span_json_eq(actual : Json, expected : Json) -> Unit {
  if actual.stringify() != expected.stringify() {
    abort("expected \{expected.stringify()}, got \{actual.stringify()}")
  }
}

///|
fn assert_no_span_json_field(obj : Map[String, Json], key : String) -> Unit {
  match obj.get(key) {
    Some(_) => abort("unexpected JSON field \{key}")
    None => ()
  }
}

///|
test "span to_json has correct structure" {
  let s = @moontrace.span(
    "test",
    fields=@moontrace.fields([("k", "v".to_json())]),
  )
  let j = s.to_json()
  let str = j.stringify()
  assert_true(str.contains("\"name\":\"test\""))
  assert_true(str.contains("\"active\":false"))
  assert_true(str.contains("\"fields\":{\"k\":\"v\""))
  @moontrace.clear_subscriber()
}

///|
test "span to_json includes parent_span_id when set" {
  let parent = @moontrace.span("parent")
  let mut child_json = ""
  @moontrace.with_child_span(parent, "child", fn(child) {
    child_json = child.to_json().stringify()
  })
  assert_true(child_json.contains("\"parent_span_id\""))
  assert_true(child_json.contains(parent.span_id))
}

///|
test "span to_json omits parent_span_id when empty" {
  let s = @moontrace.span("solo")
  let j = s.to_json().stringify()
  assert_true(!j.contains("parent_span_id"))
}

///|
test "span to_json reflects state after enter and exit" {
  let s = @moontrace.span("lifecycle")
  s.enter()
  let during = s.to_json().stringify()
  assert_true(during.contains("\"active\":true"))
  s.exit()
  let after = s.to_json().stringify()
  assert_true(after.contains("\"active\":false"))
  assert_true(after.contains("\"duration_ns\""))
  @moontrace.clear_subscriber()
}

///|
test "span to_json includes links separate from parent_span_id" {
  let parent = @moontrace.span("parent")
  let predecessor = @moontrace.span("predecessor")
  let child = @moontrace.child_span(parent, "child")
  child.follows_from(predecessor, fields=[@moontrace.field("reason", "retry")])

  let span_obj = span_json_object(child.to_json(), "span")
  assert_span_json_eq(
    span_json_field(span_obj, "parent_span_id"),
    parent.span_id.to_json(),
  )
  let links = span_json_array(span_json_field(span_obj, "links"), "links")
  assert_eq(links.length(), 1)
  let link = span_json_object(links[0], "link")
  assert_span_json_eq(
    span_json_field(link, "trace_id"),
    predecessor.trace_id.to_json(),
  )
  assert_span_json_eq(
    span_json_field(link, "span_id"),
    predecessor.span_id.to_json(),
  )
  assert_span_json_eq(span_json_field(link, "kind"), "FOLLOWS_FROM".to_json())
  assert_no_span_json_field(link, "trace_state")
}

///|
test "span to_json includes remote link tracestate" {
  let remote = match
    @moontrace.parse_span_context(
      "00-4bf92f3577b34da6a3ce929d0e0e4736-00f067aa0ba902b7-01",
      tracestate="rojo=00f067aa0ba902b7",
    ) {
    Ok(ctx) => ctx
    Err(err) => abort("expected remote context, got \{err}")
  }
  let current = @moontrace.span("current")
  current.link_context(remote)

  let span_obj = span_json_object(current.to_json(), "span")
  let links = span_json_array(span_json_field(span_obj, "links"), "links")
  assert_eq(links.length(), 1)
  let link = span_json_object(links[0], "link")
  assert_span_json_eq(
    span_json_field(link, "trace_id"),
    "4bf92f3577b34da6a3ce929d0e0e4736".to_json(),
  )
  assert_span_json_eq(
    span_json_field(link, "span_id"),
    "00f067aa0ba902b7".to_json(),
  )
  assert_span_json_eq(
    span_json_field(link, "trace_state"),
    "rojo=00f067aa0ba902b7".to_json(),
  )
}
