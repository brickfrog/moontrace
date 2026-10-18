///|
fn partial(body : String) -> @transport.ExportPartialSuccess {
  match @transport.parse_export_response(body) {
    Ok(Some(details)) => details
    _ => abort("expected partial-success details")
  }
}

///|
test "response counts accept protobuf JSON strings and numbers" {
  for value in ["2", "\"2\"", "2e0", "\"2e0\"", "20e-1", "2.0", "\"2.0\""] {
    let details = partial("{\"partialSuccess\":{\"rejectedSpans\":\{value}}}")
    assert_eq(details.rejected_spans, 2L)
    assert_eq(details.rejected_log_records, 0L)
  }
  for value in ["\"9223372036854775807\"", "\"9.223372036854775807e18\""] {
    assert_eq(
      partial("{\"partialSuccess\":{\"rejectedLogRecords\":\{value}}}").rejected_log_records,
      9223372036854775807L,
    )
  }
  assert_eq(
    partial("{\"partialSuccess\":{\"rejectedSpans\":9007199254740993}}").rejected_spans,
    9007199254740992L,
  )
}

///|
test "response parser accepts empty success defaults nulls and unknown fields" {
  for
    body in [
      "", " \r\n\t", "{}", "{\"future\":true}", "{\"partialSuccess\":null}",
    ] {
    assert_true(@transport.parse_export_response(body) is Ok(None))
  }
  let details = partial(
    "{\"partialSuccess\":{\"rejectedSpans\":null,\"rejectedLogRecords\":null,\"errorMessage\":null,\"future\":true}}",
  )
  assert_eq(details.rejected_spans, 0L)
  assert_eq(details.rejected_log_records, 0L)
  assert_eq(details.error_message, "")
  assert_eq(
    partial("{\"partialSuccess\":{\"errorMessage\":\"warning\"}}").error_message,
    "warning",
  )
}

///|
test "response parser rejects malformed types negative fractional and overflowing counts" {
  for
    body in [
      "oops", "[]", "null", "true", "1", "{\"partialSuccess\":1}", "{\"partialSuccess\":{\"errorMessage\":7}}",
    ] {
    assert_true(
      @transport.parse_export_response(body) is Err(@transport.Request(_)),
    )
  }
  for
    value in [
      "-1", "1.5", "1e-1", "9223372036854775808", "\"9223372036854775808\"", "1e100",
      "true", "[]", "{}", "\"\"", "\" 2\"", "\"2x\"", "\"1e\"", "\".2\"", "\"2.\"",
    ] {
    assert_true(
      @transport.parse_export_response(
        "{\"partialSuccess\":{\"rejectedSpans\":\{value}}}",
      )
      is Err(@transport.Request(_)),
    )
  }
}

///|
test "quoted counts handle decimal boundaries and exponent extremes" {
  for value in ["0", "-0", "000", "0e999999999", "10e-1", "0001", "1.000"] {
    assert_true(
      @transport.parse_export_response(
        "{\"partialSuccess\":{\"rejectedSpans\":\"\{value}\"}}",
      )
      is Ok(Some(_)),
    )
  }
  for
    value in [
      "1e999999999", "1e-999999999", "1.00000000000000000001", "-0.00001", "922337203685477580.8e1",
    ] {
    assert_true(
      @transport.parse_export_response(
        "{\"partialSuccess\":{\"rejectedSpans\":\"\{value}\"}}",
      )
      is Err(_),
    )
  }
  assert_true(@transport.parse_export_response(" ".repeat(65537)) is Err(_))
}
