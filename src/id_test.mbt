///|
test "trace id is 32 hex chars" {
  let id = @moontrace.next_trace_id()
  assert_eq(id.length(), 32)
}

///|
test "span id is 16 hex chars" {
  let id = @moontrace.next_span_id()
  assert_eq(id.length(), 16)
}

///|
test "ids are unique" {
  let a = @moontrace.next_span_id()
  let b = @moontrace.next_span_id()
  assert_true(a != b)
}

///|
test "trace ids are unique" {
  let a = @moontrace.next_trace_id()
  let b = @moontrace.next_trace_id()
  let c = @moontrace.next_trace_id()
  assert_true(a != b)
  assert_true(a != c)
  assert_true(b != c)
}
