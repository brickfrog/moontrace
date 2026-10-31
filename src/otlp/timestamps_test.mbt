///|
test "event timestamp converts milliseconds to nanoseconds once" {
  let event : @moontrace.Event = {
    level: @moontrace.Info,
    message: "fixture",
    fields: [],
    timestamp: 1700000000123UL,
    source: "fixture",
    file: "",
    line: 0,
  }
  let record = @otlp.event_to_log_record(event)
  assert_eq(record.time_unix_nano, 1700000000123000000UL)
  match record.to_json() {
    Object(fields) =>
      assert_eq(fields.get("timeUnixNano"), Some(Json("1700000000123000000")))
    _ => abort("expected OTLP object")
  }
}

///|
test "span timestamps convert milliseconds and preserve unset end" {
  let span = @moontrace.span("fixture")
  span.start_time = 1700000000123UL
  span.end_time = 0UL
  assert_eq(
    @otlp.span_to_otlp(span).start_time_unix_nano,
    1700000000123000000UL,
  )
  assert_eq(@otlp.span_to_otlp(span).end_time_unix_nano, 0UL)
  span.end_time = 1700000000456UL
  assert_eq(@otlp.span_to_otlp(span).end_time_unix_nano, 1700000000456000000UL)
}

///|
test "timestamp conversion saturates instead of wrapping" {
  for
    (ms, ns) in [
      (0UL, 0UL),
      (18446744073709UL, 18446744073709000000UL),
      (18446744073710UL, 18446744073709551615UL),
      (18446744073709551615UL, 18446744073709551615UL),
    ] {
    let event : @moontrace.Event = {
      level: @moontrace.Info,
      message: "fixture",
      fields: [],
      timestamp: ms,
      source: "fixture",
      file: "",
      line: 0,
    }
    assert_eq(@otlp.event_to_log_record(event).time_unix_nano, ns)
    let span = @moontrace.span("overflow fixture")
    span.start_time = ms
    span.end_time = ms
    let converted = @otlp.span_to_otlp(span)
    assert_eq(converted.start_time_unix_nano, ns)
    assert_eq(converted.end_time_unix_nano, ns)
  }
}
