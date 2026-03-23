///|
test "Level equality" {
  assert_eq(@moontrace.Info, @moontrace.Info)
  assert_true(@moontrace.Info != @moontrace.Debug)
}

///|
test "Level ordering" {
  assert_true(@moontrace.Trace < @moontrace.Debug)
  assert_true(@moontrace.Debug < @moontrace.Info)
  assert_true(@moontrace.Info < @moontrace.Warn)
  assert_true(@moontrace.Warn < @moontrace.Error_)
}

///|
test "Level to_string" {
  assert_eq(@moontrace.Trace.to_string(), "TRACE")
  assert_eq(@moontrace.Debug.to_string(), "DEBUG")
  assert_eq(@moontrace.Info.to_string(), "INFO")
  assert_eq(@moontrace.Warn.to_string(), "WARN")
  assert_eq(@moontrace.Error_.to_string(), "ERROR")
}

///|
test "level to_json" {
  let j = @moontrace.Info.to_json()
  assert_eq(j, "INFO".to_json())
}
