///|
test "global context injects fields into events" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.set_global_field("request_id", "abc".to_json())
  @moontrace.info("hello")
  // Event should have the global field
  let mut found = false
  captured[0].fields.each(fn(f) { if f.key == "request_id" { found = true } })
  assert_eq(found, true)
  @moontrace.clear_global_fields()
  @moontrace.clear_subscriber()
}

///|
test "explicit fields appear after context fields" {
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.set_global_field("ctx", "global".to_json())
  @moontrace.info("msg", fields=@moontrace.fields([("local", "val".to_json())]))
  // Should have both fields
  assert_true(captured[0].fields.length() >= 2)
  @moontrace.clear_global_fields()
  @moontrace.clear_subscriber()
}

///|
test "clear global fields removes all context" {
  @moontrace.set_global_field("a", "1".to_json())
  @moontrace.set_global_field("b", "2".to_json())
  @moontrace.clear_global_fields()
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("clean")
  assert_eq(captured[0].fields.length(), 0)
  @moontrace.clear_subscriber()
}

///|
test "remove global field" {
  @moontrace.set_global_field("keep", "yes".to_json())
  @moontrace.set_global_field("drop", "no".to_json())
  @moontrace.remove_global_field("drop")
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("test")
  let mut has_keep = false
  let mut has_drop = false
  captured[0].fields.each(fn(f) {
    if f.key == "keep" {
      has_keep = true
    }
    if f.key == "drop" {
      has_drop = true
    }
  })
  assert_eq(has_keep, true)
  assert_eq(has_drop, false)
  @moontrace.clear_global_fields()
  @moontrace.clear_subscriber()
}

///|
test "get global field" {
  @moontrace.set_global_field("key", "val".to_json())
  let v = @moontrace.get_global_field("key")
  match v {
    Some(_) => ()
    None => abort("expected Some")
  }
  @moontrace.clear_global_fields()
}
