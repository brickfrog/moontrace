///|
test "global context injects fields into events" {
  @moontrace.set_global_field("request_id", "abc".to_json())
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("hello")
  @moontrace.clear_global_fields()
  @moontrace.clear_subscriber()
  let mut found = false
  captured[0].fields.each(fn(f) { if f.key == "request_id" { found = true } })
  assert_eq(found, true)
}

///|
test "explicit fields appear after context fields" {
  @moontrace.set_global_field("ctx", "global".to_json())
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("msg", fields=@moontrace.fields([("local", "val".to_json())]))
  @moontrace.clear_global_fields()
  @moontrace.clear_subscriber()
  let fields = captured[0].fields
  assert_eq(fields.length(), 2)
  assert_eq(fields[0].key, "ctx")
  assert_eq(fields[1].key, "local")
}

///|
test "explicit fields override context on collision" {
  @moontrace.set_global_field("key", "context".to_json())
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info(
    "msg",
    fields=@moontrace.fields([("key", "explicit".to_json())]),
  )
  @moontrace.clear_global_fields()
  @moontrace.clear_subscriber()
  // Should only have one "key" field with the explicit value
  let mut count = 0
  let mut seen_value = "".to_json()
  captured[0].fields.each(fn(f) {
    if f.key == "key" {
      count = count + 1
      seen_value = f.value
    }
  })
  assert_eq(count, 1)
  assert_eq(seen_value, "explicit".to_json())
}

///|
test "clear global fields removes all context" {
  @moontrace.set_global_field("a", "1".to_json())
  @moontrace.set_global_field("b", "2".to_json())
  @moontrace.clear_global_fields()
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("clean")
  @moontrace.clear_subscriber()
  assert_eq(captured[0].fields.length(), 0)
}

///|
test "remove global field" {
  @moontrace.set_global_field("keep", "yes".to_json())
  @moontrace.set_global_field("drop", "no".to_json())
  @moontrace.remove_global_field("drop")
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("test")
  @moontrace.clear_global_fields()
  @moontrace.clear_subscriber()
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
}

///|
test "get global field returns value" {
  @moontrace.set_global_field("key", "val".to_json())
  let v = @moontrace.get_global_field("key")
  @moontrace.clear_global_fields()
  match v {
    Some(val) => assert_eq(val, "val".to_json())
    None => abort("expected Some")
  }
}

///|
test "no context has zero overhead" {
  // No global fields set — fast path should use fields directly
  let captured = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("fast", fields=@moontrace.fields([("x", (1).to_json())]))
  @moontrace.clear_subscriber()
  assert_eq(captured[0].fields.length(), 1)
  assert_eq(captured[0].fields[0].key, "x")
}
