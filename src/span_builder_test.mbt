///|
test "with_field returns span for chaining" {
  let s = @moontrace.span("chain").with_field("a", 1).with_field("b", 2)
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  s.enter()
  assert_eq(captured[0].fields.length(), 2)
  @moontrace.clear_subscriber()
}

///|
test "with_field fields appear in span events" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  let s = @moontrace.span("fluent").with_field("key", "val")
  s.enter()
  s.exit()
  let mut found = false
  captured[0].fields.each(fn(f) { if f.key == "key" { found = true } })
  assert_eq(found, true)
  @moontrace.clear_subscriber()
}
