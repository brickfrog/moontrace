///|
test "span kind to_string" {
  assert_eq(@moontrace.Internal.to_string(), "INTERNAL")
  assert_eq(@moontrace.Server.to_string(), "SERVER")
  assert_eq(@moontrace.Client.to_string(), "CLIENT")
}

///|
test "span kind to_int matches otlp" {
  assert_eq(@moontrace.Internal.to_int(), 1)
  assert_eq(@moontrace.Server.to_int(), 2)
  assert_eq(@moontrace.Consumer.to_int(), 5)
}

///|
test "span status to_string" {
  assert_eq(@moontrace.Unset.to_string(), "UNSET")
  assert_eq(@moontrace.Ok.to_string(), "OK")
  assert_eq(@moontrace.SpanError.to_string(), "ERROR")
}

///|
test "span status to_int matches otlp" {
  assert_eq(@moontrace.Unset.to_int(), 0)
  assert_eq(@moontrace.Ok.to_int(), 1)
  assert_eq(@moontrace.SpanError.to_int(), 2)
}

///|
test "span kind show" {
  let shown = "\{@moontrace.Internal}"
  assert_eq(shown, "INTERNAL")
}
