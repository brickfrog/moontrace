///|
#callsite(autofill(loc))
fn here(loc~ : SourceLoc) -> SourceLoc {
  loc
}

///|
test "extract_file_line reads the start line of a SourceLoc" {
  let (file, line) = extract_file_line(here())
  assert_eq(file, "src/event_location_wbtest.mbt")
  assert_eq(line, 9)
}

///|
test "extract_file_line tolerates colons and dashes in paths" {
  assert_eq(
    parse_file_line_text("C:/work/my-app/src/main.mbt:12:3-12:9@me/app"),
    ("C:/work/my-app/src/main.mbt", 12),
  )
  assert_eq(parse_file_line_text("main.mbt:1:1-1:2"), ("main.mbt", 1))
  assert_eq(parse_file_line_text("garbage"), ("", 0))
  assert_eq(parse_file_line_text(":1:1-1:2@me/app"), ("", 0))
  assert_eq(parse_file_line_text("main.mbt:x:1-1:2@me/app"), ("", 0))
}
