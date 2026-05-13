///|
test "constructing a Field directly" {
  let f = @moontrace.Field::{ key: "name", value: "hello".to_json() }
  assert_eq(f.key, "name")
  @debug.assert_eq(f.value, "hello".to_json())
}

///|
test "fields() helper with mixed types" {
  let arr = @moontrace.fields([
    ("count", (42).to_json()),
    ("active", true.to_json()),
  ])
  assert_eq(arr.length(), 2)
  assert_eq(arr[0].key, "count")
  @debug.assert_eq(arr[0].value, (42).to_json())
  assert_eq(arr[1].key, "active")
  @debug.assert_eq(arr[1].value, true.to_json())
}

///|
test "field() with string value" {
  let f = @moontrace.field("host", "localhost")
  assert_eq(f.key, "host")
  @debug.assert_eq(f.value, "localhost".to_json())
}

///|
test "field() with int value" {
  let f = @moontrace.field("port", 8080)
  assert_eq(f.key, "port")
  @debug.assert_eq(f.value, (8080).to_json())
}

///|
test "field() with bool value" {
  let f = @moontrace.field("active", true)
  assert_eq(f.key, "active")
  @debug.assert_eq(f.value, true.to_json())
}

///|
test "field() with double value" {
  let f = @moontrace.field("ratio", 0.75)
  assert_eq(f.key, "ratio")
  @debug.assert_eq(f.value, 0.75.to_json())
}

///|
test "field() in emit function" {
  let captured : Array[@moontrace.Event] = []
  @moontrace.set_subscriber(fn(e) { captured.push(e) })
  @moontrace.info("listening", fields=[
    @moontrace.field("port", 8080),
    @moontrace.field("host", "localhost"),
  ])
  @moontrace.clear_subscriber()
  assert_eq(captured[0].fields.length(), 2)
  assert_eq(captured[0].fields[0].key, "port")
  @debug.assert_eq(captured[0].fields[0].value, (8080).to_json())
  assert_eq(captured[0].fields[1].key, "host")
  @debug.assert_eq(captured[0].fields[1].value, "localhost".to_json())
}

///|
test "fields_to_json converts fields to object json" {
  let json = @moontrace.fields_to_json(
    @moontrace.fields([("tool", "fork".to_json()), ("count", (2).to_json())]),
  )
  let str = json.stringify()
  assert_true(str.contains("\"tool\":\"fork\""))
  assert_true(str.contains("\"count\":2"))
}
