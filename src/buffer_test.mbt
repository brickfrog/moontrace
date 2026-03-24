///|
test "buffer collects events" {
  let output : Array[String] = []
  let buf = @moontrace.buffer(fn(e : @moontrace.Event) {
    output.push(e.message)
  })
  @moontrace.set_subscriber(buf.subscriber())
  @moontrace.info("one")
  @moontrace.info("two")
  assert_eq(buf.len(), 2)
  assert_eq(output.length(), 0)
  @moontrace.clear_subscriber()
}

///|
test "buffer auto-flushes at capacity" {
  let output : Array[String] = []
  let buf = @moontrace.buffer(
    fn(e : @moontrace.Event) { output.push(e.message) },
    capacity=2,
  )
  @moontrace.set_subscriber(buf.subscriber())
  @moontrace.info("one")
  @moontrace.info("two")
  assert_eq(output.length(), 2)
  assert_eq(buf.len(), 0)
  @moontrace.clear_subscriber()
}

///|
test "buffer manual flush" {
  let output : Array[String] = []
  let buf = @moontrace.buffer(fn(e : @moontrace.Event) {
    output.push(e.message)
  })
  @moontrace.set_subscriber(buf.subscriber())
  @moontrace.info("hello")
  assert_eq(output.length(), 0)
  buf.flush()
  assert_eq(output.length(), 1)
  assert_eq(output[0], "hello")
  @moontrace.clear_subscriber()
}
