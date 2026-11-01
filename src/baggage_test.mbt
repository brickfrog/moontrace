///|
test "baggage set, get, remove are immutable" {
  let empty = @moontrace.Baggage::empty()
  let one = empty.set("user", "ann")
  let two = one.set("tenant", "acme").set("user", "bob")
  assert_eq(empty.len(), 0)
  assert_eq(one.get("user"), Some("ann"))
  assert_eq(two.get("user"), Some("bob"))
  assert_eq(two.entries().map(e => e.key), ["user", "tenant"])
  let removed = two.remove("user")
  assert_eq(removed.get("user"), None)
  assert_eq(two.get("user"), Some("bob"))
  assert_eq(one.set("bad key", "x").len(), 1)
  assert_eq(one.set("", "x").len(), 1)
}

///|
test "baggage header round-trips percent-encoded values and properties" {
  let baggage = @moontrace.Baggage::empty()
    .set("user", "ann lee")
    .set("city", "Zürich")
    .set("expr", "a,b;c=d%e\"f\\g")
    .set("prop", "v", properties="ttl=30;secret")
  let header = baggage.to_header()
  assert_eq(
    header, "user=ann%20lee,city=Z%C3%BCrich,expr=a%2Cb%3Bc=d%25e%22f%5Cg,prop=v;ttl=30;secret",
  )
  let parsed = @moontrace.parse_baggage(header)
  assert_eq(parsed.get("user"), Some("ann lee"))
  assert_eq(parsed.get("city"), Some("Zürich"))
  assert_eq(parsed.get("expr"), Some("a,b;c=d%e\"f\\g"))
  assert_eq(parsed.entries()[3].properties, "ttl=30;secret")
  assert_eq(parsed.to_header(), header)
}

///|
test "parse_baggage skips malformed members and never fails" {
  let parsed = @moontrace.parse_baggage(
    " a = 1 , novalue, =x, bad key=2, quote=\"x\", b=%zz, c=%4, ok=yes ;p , a=3",
  )
  assert_eq(parsed.entries().map(e => e.key), ["a", "b", "c", "ok"])
  assert_eq(parsed.get("a"), Some("3"))
  // Undecodable values are kept as received.
  assert_eq(parsed.get("b"), Some("%zz"))
  assert_eq(parsed.get("c"), Some("%4"))
  assert_eq(parsed.entries()[3].properties, "p")
  assert_eq(@moontrace.parse_baggage("").len(), 0)
  assert_eq(@moontrace.parse_baggage(",,,").len(), 0)
}

///|
test "baggage enforces member and byte limits" {
  let mut many = @moontrace.Baggage::empty()
  for i in 0..<100 {
    many = many.set("k\{i}", "v")
  }
  assert_eq(many.len(), @moontrace.baggage_max_members)
  let header = Array::make(100, "").mapi((i, _) => "k\{i}=v").join(",")
  assert_eq(@moontrace.parse_baggage(header).len(), 64)

  let big = String::make(5000, 'x')
  let sized = @moontrace.Baggage::empty()
    .set("a", big)
    .set("b", big)
    .set("c", "small")
  let header = sized.to_header()
  assert_true(header.length() <= @moontrace.baggage_max_bytes)
  assert_true(header.has_prefix("a="))
  assert_true(header.has_suffix(",c=small"))
}
