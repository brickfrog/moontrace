///|
test "console subscriber formats output" {
  let output : Array[String] = []
  @moontrace.set_subscriber(
    @console.subscriber(color=false, output=fn(s) { output.push(s) }),
  )
  @moontrace.info("hello")
  assert_eq(output.length(), 1)
  // Output should contain INFO and hello
  assert_true(output[0].contains("INFO"))
  assert_true(output[0].contains("hello"))
  @moontrace.clear_subscriber()
}

///|
test "console subscriber includes fields" {
  let output : Array[String] = []
  @moontrace.set_subscriber(
    @console.subscriber(color=false, output=fn(s) { output.push(s) }),
  )
  @moontrace.info("msg", fields=@moontrace.fields([("key", "val".to_json())]))
  assert_eq(output.length(), 1)
  // Output should contain key=\"val\" or key="val"
  assert_true(output[0].contains("key=\"val\""))
  @moontrace.clear_subscriber()
}

///|
test "console subscriber min_level filtering" {
  let output : Array[String] = []
  @moontrace.set_subscriber(
    @console.subscriber(min_level=@moontrace.Warn, color=false, output=fn(s) {
      output.push(s)
    }),
  )
  @moontrace.info("skip")
  @moontrace.warn("keep")
  assert_eq(output.length(), 1)
  @moontrace.clear_subscriber()
}

///|
test "console subscriber no ansi when color false" {
  let output : Array[String] = []
  @moontrace.set_subscriber(
    @console.subscriber(color=false, output=fn(s) { output.push(s) }),
  )
  @moontrace.info("test")
  assert_eq(output.length(), 1)
  // Verify no ANSI escape codes in output
  // Check output[0] does NOT contain the escape character
  assert_false(output[0].contains("\u001b"))
  @moontrace.clear_subscriber()
}
