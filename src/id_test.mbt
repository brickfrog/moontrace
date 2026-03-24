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
test "trace id is lowercase hex" {
  let id = @moontrace.next_trace_id()
  let valid_chars = "0123456789abcdef"
  let mut is_valid = true
  for i = 0; i < id.length() && is_valid; i = i + 1 {
    if !valid_chars.contains(id[i]) {
      is_valid = false
    }
  }
  assert_true(is_valid)
}

///|
test "span id is lowercase hex" {
  let id = @moontrace.next_span_id()
  let valid_chars = "0123456789abcdef"
  let mut is_valid = true
  for i = 0; i < id.length() && is_valid; i = i + 1 {
    if !valid_chars.contains(id[i]) {
      is_valid = false
    }
  }
  assert_true(is_valid)
}

///|
test "ids are unique" {
  let a = @moontrace.next_span_id()
  let b = @moontrace.next_span_id()
  assert_true(a != b)
}

///|
test "trace ids are unique in small sample" {
  let a = @moontrace.next_trace_id()
  let b = @moontrace.next_trace_id()
  let c = @moontrace.next_trace_id()
  assert_true(a != b)
  assert_true(a != c)
  assert_true(b != c)
}
