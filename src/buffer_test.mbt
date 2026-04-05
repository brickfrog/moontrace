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
  assert_eq(output[0], "one")
  assert_eq(output[1], "two")
  assert_eq(buf.len(), 0)
  @moontrace.clear_subscriber()
}

///|
test "buffer clamps capacity below 1 to 1" {
  let output : Array[String] = []
  let buf = @moontrace.buffer(
    fn(e : @moontrace.Event) { output.push(e.message) },
    capacity=-5,
  )
  @moontrace.set_subscriber(buf.subscriber())
  assert_eq(buf.len(), 0)
  @moontrace.info("single")
  // capacity=1, so auto-flushes immediately
  assert_eq(output.length(), 1)
  assert_eq(output[0], "single")
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
