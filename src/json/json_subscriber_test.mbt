///|
test "json subscriber outputs json" {
  let output : Array[String] = []
  @moontrace.set_subscriber(@json.subscriber(output=fn(s) { output.push(s) }))
  @moontrace.info("hello")
  assert_eq(output.length(), 1)
  // Verify JSON contains expected content
  assert_true(output[0].contains("INFO"))
  assert_true(output[0].contains("hello"))
  @moontrace.clear_subscriber()
}

///|
test "json subscriber includes fields" {
  let output : Array[String] = []
  @moontrace.set_subscriber(@json.subscriber(output=fn(s) { output.push(s) }))
  @moontrace.info("msg", fields=@moontrace.fields([("tool", "fork".to_json())]))
  assert_eq(output.length(), 1)
  // output[0] should contain "tool" and "fork"
  assert_true(output[0].contains("tool"))
  assert_true(output[0].contains("fork"))
  @moontrace.clear_subscriber()
}

///|
test "json subscriber filters by min_level" {
  let output : Array[String] = []
  @moontrace.set_subscriber(
    @json.subscriber(min_level=@moontrace.Warn, output=fn(s) { output.push(s) }),
  )
  @moontrace.info("skip")
  @moontrace.warn("keep")
  assert_eq(output.length(), 1)
  @moontrace.clear_subscriber()
}

///|
test "json initialize() convenience function" {
  let output : Array[String] = []
  @json.initialize(min_level=Warn, output=fn(s) { output.push(s) })
  @moontrace.info("skip")
  @moontrace.warn("keep")
  assert_eq(output.length(), 1)
  assert_true(output[0].contains("WARN"))
  @moontrace.clear_subscriber()
}
