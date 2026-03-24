test "trace id is 32 hex chars" {
  let id = next_trace_id()
  assert_eq(id.length(), 32)
}

///|
test "span id is 16 hex chars" {
  let id = next_span_id()
  assert_eq(id.length(), 16)
}

///|
test "ids are unique" {
  let a = next_span_id()
  let b = next_span_id()
  assert_true(a != b)
}

///|
test "trace ids are unique in small sample" {
  let a = next_trace_id()
  let b = next_trace_id()
  let c = next_trace_id()
  assert_true(a != b)
  assert_true(a != c)
  assert_true(b != c)
}
