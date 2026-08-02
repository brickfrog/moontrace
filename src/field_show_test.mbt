///|
test "field to_string formats as key=value" {
  let f = @moontrace.Field::{ key: "name", value: "test".to_json() }
  assert_eq(f.to_string(), "name=\"test\"")
}

///|
test "field show via interpolation" {
  let f = @moontrace.Field::{ key: "count", value: (42).to_json() }
  let shown = "\{f}"
  assert_eq(shown, "count=42")
}

///|
test "field show escapes control characters in keys" {
  let f = @moontrace.Field::{
    key: "na\b\u{000c}\n\r\t\u001b\u007f\u009fme",
    value: "printable 汉字 \\n".to_json(),
  }
  assert_eq(
    f.to_string(),
    "na\\b\\f\\n\\r\\t\\u{001b}\\u{007f}\\u{009f}me=\"printable 汉字 \\\\n\"",
  )
}

///|
test "field to_json wraps as object" {
  let f = @moontrace.Field::{ key: "key", value: "val".to_json() }
  let j = f.to_json()
  assert_eq(j.stringify(), "{\"key\":\"val\"}")
}
