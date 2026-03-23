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
test "Level to_json" {
  let j = @moontrace.Info.to_json()
  assert_eq(j, "INFO".to_json())
}

///|
test "from_string parses valid levels" {
  assert_eq(@moontrace.Level::from_string("INFO"), Some(@moontrace.Info))
  assert_eq(@moontrace.Level::from_string("TRACE"), Some(@moontrace.Trace))
  assert_eq(@moontrace.Level::from_string("DEBUG"), Some(@moontrace.Debug))
  assert_eq(@moontrace.Level::from_string("WARN"), Some(@moontrace.Warn))
  assert_eq(@moontrace.Level::from_string("ERROR"), Some(@moontrace.Error_))
}

///|
test "from_string is case flexible" {
  assert_eq(@moontrace.Level::from_string("info"), Some(@moontrace.Info))
  assert_eq(@moontrace.Level::from_string("Info"), Some(@moontrace.Info))
  assert_eq(@moontrace.Level::from_string("iNfO"), Some(@moontrace.Info))
}

///|
test "from_string returns None for unknown" {
  assert_eq(@moontrace.Level::from_string("UNKNOWN"), None)
  assert_eq(@moontrace.Level::from_string(""), None)
}
