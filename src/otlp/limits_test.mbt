///|
fn limited_span() -> @moontrace.Span {
  let span = @moontrace.span("op", fields=[
    @moontrace.field("a", "1234567890"),
    @moontrace.field("b", ["long-value", "x"]),
    @moontrace.field("c", 3),
  ])
  span.add_event("e1", fields=[
    @moontrace.field("k1", 1),
    @moontrace.field("k2", 2),
  ])
  span.add_event("e2")
  span.add_event("e3")
  let other = @moontrace.span("other")
  span.link(other, fields=[@moontrace.field("l1", 1), @moontrace.field("l2", 2)])
  span.follows_from(other)
  span
}

///|
test "default limits keep everything and report no drops" {
  let otlp = @otlp.span_to_otlp(limited_span())
  assert_eq(otlp.attributes.length(), 3)
  assert_eq(otlp.events.length(), 3)
  assert_eq(otlp.links.length(), 2)
  assert_eq(otlp.dropped_attributes_count, 0)
  assert_eq(otlp.dropped_events_count, 0)
  assert_eq(otlp.dropped_links_count, 0)
  let json = otlp.to_json().stringify()
  assert_false(json.contains("dropped"))
}

///|
test "span limits drop extra items, count them, and truncate strings" {
  let limits = @otlp.otlp_limits(
    attribute_count=1,
    attribute_value_length=4,
    event_count=1,
    link_count=1,
  )
  let otlp = @otlp.span_to_otlp(limited_span(), limits~)
  assert_eq(otlp.attributes.map(a => a.key), ["a"])
  assert_true(otlp.attributes[0].value is StringVal("1234"))
  assert_eq(otlp.dropped_attributes_count, 2)
  assert_eq(otlp.events.map(e => e.name), ["e1"])
  assert_eq(otlp.dropped_events_count, 2)
  assert_eq(otlp.events[0].attributes.length(), 1)
  assert_eq(otlp.events[0].dropped_attributes_count, 1)
  assert_eq(otlp.links.length(), 1)
  assert_eq(otlp.dropped_links_count, 1)
  assert_eq(otlp.links[0].dropped_attributes_count, 1)
  let json = otlp.to_json().stringify()
  assert_true(json.contains("\"droppedAttributesCount\":2"))
  assert_true(json.contains("\"droppedEventsCount\":2"))
  assert_true(json.contains("\"droppedLinksCount\":1"))
}

///|
test "value length limits truncate strings inside arrays" {
  let limits = @otlp.otlp_limits(attribute_value_length=4)
  let otlp = @otlp.span_to_otlp(limited_span(), limits~)
  match otlp.attributes[1].value {
    ArrayVal(items) => {
      assert_true(items[0] is StringVal("long"))
      assert_true(items[1] is StringVal("x"))
    }
    _ => fail("expected an array value")
  }
  assert_true(otlp.attributes[2].value is IntVal(3L))
}

///|
test "log record limits apply to attributes" {
  let event = @moontrace.Event::{
    level: @moontrace.Info,
    message: "m",
    fields: [@moontrace.field("x", "abcdef"), @moontrace.field("y", 1)],
    timestamp: 0UL,
    source: "",
    file: "src/app.mbt",
    line: 1,
  }
  let record = @otlp.event_to_log_record(
    event,
    limits=@otlp.otlp_limits(attribute_count=1, attribute_value_length=2),
  )
  assert_eq(record.attributes.map(a => a.key), ["x"])
  assert_true(record.attributes[0].value is StringVal("ab"))
  // y, code.file.path, and code.line.number were dropped.
  assert_eq(record.dropped_attributes_count, 3)
  assert_true(
    record.to_json().stringify().contains("\"droppedAttributesCount\":3"),
  )
  assert_eq(@otlp.otlp_limits(attribute_count=-5).attribute_count, 0)
}

///|
test "value length limits count characters, not UTF-16 code units" {
  let span = @moontrace.span("op", fields=[
    @moontrace.field("emoji", "😀😀"),
    @moontrace.field("mixed", "a😀b😀c"),
  ])
  let otlp = @otlp.span_to_otlp(
    span,
    limits=@otlp.otlp_limits(attribute_value_length=3),
  )
  assert_true(otlp.attributes[0].value is StringVal("😀😀"))
  assert_true(otlp.attributes[1].value is StringVal("a😀b"))
}
