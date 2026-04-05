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
