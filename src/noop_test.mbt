///|
test "noop does not crash" {
  @moontrace.set_subscriber(@moontrace.noop())
  @moontrace.info("silent")
  @moontrace.clear_subscriber()
}

///|
test "tap runs side effect" {
  let tapped : Array[String] = []
  let output : Array[String] = []
  let inner = fn(e : @moontrace.Event) { output.push(e.message) }
  let side = fn(e : @moontrace.Event) { tapped.push(e.message) }
  @moontrace.set_subscriber(@moontrace.tap(inner, side))
  @moontrace.info("hello")
  assert_eq(tapped.length(), 1)
  assert_eq(output.length(), 1)
  assert_eq(tapped[0], "hello")
  assert_eq(output[0], "hello")
  @moontrace.clear_subscriber()
}
