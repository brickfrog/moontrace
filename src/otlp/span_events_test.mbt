///|
test "nested field values convert to OTLP array and kvlist values" {
  let attr = @otlp.field_to_attribute(
    @moontrace.field(
      "request",
      Json(
        Map([
          ("method", Json("GET")),
          ("ids", Json([Json(1), Json(2.5)])),
          ("none", Json::null()),
        ]),
      ),
    ),
  )
  assert_eq(
    attr.to_json().stringify(),
    (
      #|{"key":"request","value":{"kvlistValue":{"values":[
      #|{"key":"method","value":{"stringValue":"GET"}},
      #|{"key":"ids","value":{"arrayValue":{"values":[{"intValue":"1"},{"doubleValue":2.5}]}}},
      #|{"key":"none","value":{}}]}}}
    ).replace_all(old="\n", new=""),
  )
}

///|
test "span_to_otlp exports span events in nanoseconds" {
  let span = @moontrace.span("payment")
  span.enter()
  span.record_exception(Failure("declined"))
  span.exit()
  let otlp = @otlp.span_to_otlp(span)
  assert_eq(otlp.events.length(), 1)
  let event = otlp.events[0]
  assert_eq(event.name, "exception")
  assert_true(event.time_unix_nano == span.events[0].timestamp * 1_000_000UL)
  assert_eq(event.attributes.map(a => a.key), [
    "exception.type", "exception.message",
  ])
  let json = otlp.to_json().stringify()
  assert_true(json.contains("\"events\":[{\"timeUnixNano\":"))
  assert_true(json.contains("\"name\":\"exception\""))
}

///|
test "span JSON omits events when there are none" {
  let otlp = @otlp.span_to_otlp(@moontrace.span("quiet"))
  assert_eq(otlp.events.length(), 0)
  assert_true(!otlp.to_json().stringify().contains("\"events\""))
}
