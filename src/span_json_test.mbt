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
  assert_true(str.contains("\"k\":\"v\""))
  @moontrace.clear_subscriber()
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
  assert_true(after.contains("\"duration\""))
  @moontrace.clear_subscriber()
}
