///|
#cfg(target="native")
test "period stamps round-trip through the archive parser" {
  let start = 1774656000000UL + 14UL * 3600000UL
  assert_eq(period_stamp(Daily, start), "2026-03-28")
  assert_eq(period_stamp(Hourly, start), "2026-03-28T14")
  assert_eq(parse_period_stamp(Daily, "2026-03-28"), Some(1774656000000UL))
  assert_eq(parse_period_stamp(Hourly, "2026-03-28T14"), Some(start))
  assert_eq(parse_period_stamp(Daily, "2000-02-29"), Some(951782400000UL))
  for bad in ["2026-3-28", "2026-13-01", "2026-03-28T14", "abcd-ef-gh", ""] {
    assert_eq(parse_period_stamp(Daily, bad), None)
  }
  assert_eq(parse_period_stamp(Hourly, "2026-03-28T24"), None)
  let parsed = parse_dated_archive("app.log", Daily, "app.log.2026-03-28.3.gz")
  guard parsed is Some(archive) else { fail("expected archive") }
  assert_eq(archive.start_ms, 1774656000000UL)
  assert_eq(archive.sequence, 3L)
  for
    other in [
      "app.log", "app.log.1", "app.log.2026-03-28.x", "other.log.2026-03-28",
    ] {
    assert_true(parse_dated_archive("app.log", Daily, other) is None)
  }
}

///|
#cfg(target="native")
test "archive sequences that overflow Int64 are not archives" {
  let max = "app.log.2026-03-28.999999999999999999"
  guard parse_dated_archive("app.log", Daily, max) is Some(archive) else {
    fail("expected archive")
  }
  assert_eq(archive.sequence, 999999999999999999L)
  for
    name in [
      "app.log.2026-03-28.99999999999999999999", "app.log.2026-03-28.9223372036854775808.gz",
    ] {
    assert_true(parse_dated_archive("app.log", Daily, name) is None)
  }
}
