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

///|
test "ids are non-zero" {
  let zero_trace = "00000000000000000000000000000000"
  let zero_span = "0000000000000000"
  for _ in 0..<100 {
    assert_true(@moontrace.next_trace_id() != zero_trace)
    assert_true(@moontrace.next_span_id() != zero_span)
  }
}

///|
test "bulk trace ids are unique" {
  let seen : Map[String, Bool] = {}
  for _ in 0..<1000 {
    let id = @moontrace.next_trace_id()
    assert_true(!seen.contains(id))
    seen.set(id, true)
  }
}

///|
test "bulk span ids are unique" {
  let seen : Map[String, Bool] = {}
  for _ in 0..<1000 {
    let id = @moontrace.next_span_id()
    assert_true(!seen.contains(id))
    seen.set(id, true)
  }
}
