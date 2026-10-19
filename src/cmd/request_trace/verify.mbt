///|
// Executable consumer assertions, separate from the request-handling example.
fn verify_exports(
  first : @moontrace.SpanContext,
  second : @moontrace.SpanContext,
  events : Array[@moontrace.Event],
  spans : Array[@moontrace.Span],
  client : CaptureClient,
) -> Unit raise {
  assert_eq(spans.length(), 4)
  assert_eq(events.length(), 4)
  for event in events {
    let id = event_field(event, "request_id")
    let ctx = if id == "one" { first } else { second }
    assert_eq(event_field(event, "trace_id"), ctx.trace_id.to_string())
    let span_id = event_field(event, "span_id")
    assert_true(spans.any(span => span.span_id == span_id))
  }
  for span in spans {
    assert_false(span.active)
    assert_true(span.end_time >= span.start_time)
    let failing = span.trace_id == second.trace_id.to_string()
    assert_eq(
      span.status,
      if failing {
        @moontrace.SpanError
      } else {
        @moontrace.Unset
      },
    )
    if span.name == "request" {
      assert_eq(span.kind, @moontrace.Server)
      assert_eq(
        span.parent_span_id,
        if failing {
          second.span_id.to_string()
        } else {
          first.span_id.to_string()
        },
      )
    }
  }
  assert_eq(client.payloads.length(), 2)
  for (url, payload) in client.payloads {
    let json = @json.parse(payload)
    if url.has_suffix("/v1/traces") {
      let records = json_array(
        json_get(
          json_array(
            json_get(
              json_array(json_get(json, "resourceSpans"))[0],
              "scopeSpans",
            ),
          )[0],
          "spans",
        ),
      )
      assert_eq(records.length(), 4)
      for record in records {
        let id = json_string(json_get(record, "spanId"))
        let source = spans.filter(span => span.span_id == id)[0]
        assert_eq(json_string(json_get(record, "traceId")), source.trace_id)
        assert_eq(
          json_string(json_get(record, "parentSpanId")),
          source.parent_span_id,
        )
        if source.status == @moontrace.SpanError {
          assert_eq(json_get(json_get(record, "status"), "code"), Json(2))
        }
      }
    } else {
      let records = json_array(
        json_get(
          json_array(
            json_get(json_array(json_get(json, "resourceLogs"))[0], "scopeLogs"),
          )[0],
          "logRecords",
        ),
      )
      assert_eq(records.length(), 4)
      for record in records {
        let attrs = json_array(json_get(record, "attributes"))
        let field = fn(key) {
          let entry = attrs.filter(attr => {
              json_string(json_get(attr, "key")) == key
            })[0]
          json_string(json_get(json_get(entry, "value"), "stringValue"))
        }
        let request_id = field("request_id")
        assert_eq(
          field("trace_id"),
          if request_id == "one" {
            first.trace_id.to_string()
          } else {
            second.trace_id.to_string()
          },
        )
        assert_true(spans.any(span => span.span_id == field("span_id")))
      }
    }
  }
}

///|
fn json_get(value : Json, key : String) -> Json {
  match value {
    Object(fields) => fields.get(key).unwrap()
    _ => abort("expected JSON object")
  }
}

///|
fn json_array(value : Json) -> Array[Json] {
  match value {
    Array(values) => values
    _ => abort("expected JSON array")
  }
}

///|
fn json_string(value : Json) -> String {
  match value {
    String(value) => value
    _ => abort("expected JSON string")
  }
}
