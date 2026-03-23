///|
test "constructing a Field directly" {
  let f = @moontrace.Field::{ key: "name", value: "hello".to_json() }
  assert_eq(f.key, "name")
  assert_eq(f.value, "hello".to_json())
}

///|
test "fields() helper with mixed types" {
  let arr = @moontrace.fields([
    ("count", (42).to_json()),
    ("active", true.to_json()),
  ])
  assert_eq(arr.length(), 2)
  assert_eq(arr[0].key, "count")
  assert_eq(arr[0].value, (42).to_json())
  assert_eq(arr[1].key, "active")
  assert_eq(arr[1].value, true.to_json())
}
