///|
test "make seed prefers exact platform entropy" {
  let expected = Bytes::makei(32, i => i.to_byte())
  let clock_read : Ref[Bool] = Ref(false)
  let actual = make_seed(
    size => if size == 32 { Some(expected) } else { None },
    () => {
      clock_read.val = true
      0UL
    },
  )
  assert_eq(actual, expected)
  assert_true(!clock_read.val)
}

///|
test "make seed falls back deterministically without entropy" {
  let make = fn() { make_seed(fn(_) { None }, fn() { 42UL }) }
  let first = make()
  let second = make()
  assert_eq(first.length(), 32)
  assert_eq(first, second)
  assert_true(first != Bytes::make(32, b'\x00'))
}

///|
test "make seed rejects platform entropy with the wrong length" {
  let seed = make_seed(fn(_) { Some(b"too short") }, fn() { 7UL })
  assert_eq(seed.length(), 32)
  assert_true(seed != b"too short")
}
