///|
/// A decoded protobuf field: varint/fixed values as `UInt64`, length-delimited
/// values as bytes.
priv enum ProtoValue {
  Scalar(UInt64)
  Delimited(Bytes)
}

///|
fn read_varint(body : Bytes, pos : Int32) -> (UInt64, Int32) {
  let mut value = 0UL
  let mut shift = 0
  let mut i = pos
  while true {
    let byte = body[i].to_uint64()
    value = value | ((byte & 0x7FUL) << shift)
    i += 1
    if (byte & 0x80UL) == 0UL {
      break
    }
    shift += 7
  }
  (value, i)
}

///|
fn read_fixed64(body : Bytes, pos : Int32) -> UInt64 {
  let mut value = 0UL
  for k in 0..<8 {
    value = value | (body[pos + k].to_uint64() << (8 * k))
  }
  value
}

///|
/// Decode one message level into field number -> values, in order.
fn proto_fields(body : Bytes) -> Map[Int32, Array[ProtoValue]] {
  let fields : Map[Int32, Array[ProtoValue]] = Map([])
  let mut pos = 0
  while pos < body.length() {
    let (tag, next) = read_varint(body, pos)
    let field = (tag >> 3).to_int()
    let value = match (tag & 7UL).to_int() {
      0 => {
        let (v, after) = read_varint(body, next)
        pos = after
        Scalar(v)
      }
      1 => {
        pos = next + 8
        Scalar(read_fixed64(body, next))
      }
      2 => {
        let (len, start) = read_varint(body, next)
        pos = start + len.to_int()
        Delimited(body[start:pos].to_owned())
      }
      other => abort("unexpected wire type \{other}")
    }
    match fields.get(field) {
      Some(values) => values.push(value)
      None => fields.set(field, [value])
    }
  }
  fields
}

///|
fn delimited(
  fields : Map[Int32, Array[ProtoValue]],
  field : Int32,
) -> Array[Bytes] {
  fields
  .get(field)
  .unwrap_or([])
  .filter_map(value => {
    match value {
      Delimited(bytes) => Some(bytes)
      _ => None
    }
  })
}

///|
fn scalar(fields : Map[Int32, Array[ProtoValue]], field : Int32) -> UInt64? {
  match fields.get(field) {
    Some([Scalar(value), ..]) => Some(value)
    _ => None
  }
}

///|
fn test_meter() -> @metrics.Meter {
  let meter = @metrics.meter(name="svc", version="2", clock=() => 3UL)
  meter
  .counter("reqs", unit="1")
  .add(4.0, attributes=[@moontrace.field("route", "/a")])
  meter.histogram("lat", bounds=[10.0]).record(25.0)
  meter
}

///|
test "JSON metrics encoding matches metrics_to_otlp_json" {
  let meter = test_meter()
  let data = meter.collect()
  let payload = match
    @transport.json_encoder().encode_metrics(data, scope=meter.scope()) {
    Ok(payload) => payload
    Err(err) => abort(err.to_string())
  }
  assert_eq(payload.content_type, "application/json")
  assert_eq(
    @utf8.decode(payload.body),
    @metrics.metrics_to_otlp_json(data, scope=meter.scope()).stringify(),
  )
}

///|
test "protobuf metrics encoding follows metrics.proto" {
  let meter = test_meter()
  let payload = match
    @transport.protobuf_encoder().encode_metrics(
      meter.collect(),
      scope=meter.scope(),
    ) {
    Ok(payload) => payload
    Err(err) => abort(err.to_string())
  }
  let request = proto_fields(payload.body)
  let resource_metrics = proto_fields(delimited(request, 1)[0])
  let scope_metrics = proto_fields(delimited(resource_metrics, 2)[0])
  let scope = proto_fields(delimited(scope_metrics, 1)[0])
  assert_eq(@utf8.decode(delimited(scope, 1)[0]), "svc")
  let metrics = delimited(scope_metrics, 2).map(proto_fields)
  assert_eq(metrics.length(), 2)

  let counter = metrics[0]
  assert_eq(@utf8.decode(delimited(counter, 1)[0]), "reqs")
  assert_eq(@utf8.decode(delimited(counter, 3)[0]), "1")
  let sum = proto_fields(delimited(counter, 7)[0])
  assert_eq(scalar(sum, 2), Some(2UL))
  assert_eq(scalar(sum, 3), Some(1UL))
  let point = proto_fields(delimited(sum, 1)[0])
  assert_eq(scalar(point, 2), Some(3_000_000UL))
  assert_eq(scalar(point, 3), Some(3_000_000UL))
  assert_eq(scalar(point, 4).map(UInt64::reinterpret_as_double), Some(4.0))
  assert_eq(delimited(point, 7).length(), 1)

  let histogram = proto_fields(delimited(metrics[1], 9)[0])
  assert_eq(scalar(histogram, 2), Some(2UL))
  let hp = proto_fields(delimited(histogram, 1)[0])
  assert_eq(scalar(hp, 4), Some(1UL))
  assert_eq(scalar(hp, 5).map(UInt64::reinterpret_as_double), Some(25.0))
  let buckets = delimited(hp, 6)[0]
  assert_eq(buckets.length(), 16)
  assert_eq(read_fixed64(buckets, 0), 0UL)
  assert_eq(read_fixed64(buckets, 8), 1UL)
  let bounds = delimited(hp, 7)[0]
  assert_eq(read_fixed64(bounds, 0).reinterpret_as_double(), 10.0)
  assert_eq(scalar(hp, 11).map(UInt64::reinterpret_as_double), Some(25.0))
  assert_eq(scalar(hp, 12).map(UInt64::reinterpret_as_double), Some(25.0))
}

///|
async test "export_metrics sends protobuf to the metrics path and reports rejections" {
  let client = bytes_client([(200, partial_response(2, "too many points"))])
  let tx = protobuf_transport(client)
  let report = match
    @async.with_timeout(1000, () => tx.export_metrics_report(test_meter())) {
    Ok(report) => report
    Err(err) => abort("\{err}")
  }
  assert_eq(client.calls[0].url, "http://collector:4318/v1/metrics")
  assert_eq(
    client.calls[0].headers.get("Content-Type"),
    Some("application/x-protobuf"),
  )
  assert_false(report.outcome.success)
  match report.partial_success {
    Some(details) => {
      assert_eq(details.rejected_data_points, 2L)
      assert_eq(details.rejected_spans, 0L)
      assert_eq(details.error_message, "too many points")
    }
    None => fail("expected partial success details")
  }
}

///|
async test "export_metrics uses JSON and the configured metrics endpoint" {
  let client = fake_client([FakeResponse(response(200))])
  let config = @otlp.parse_otel_config(name => {
    let vars : Map[String, String] = {
      "OTEL_EXPORTER_OTLP_ENDPOINT": "http://collector:4318",
      "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT": "http://metrics.example/push",
      "OTEL_EXPORTER_OTLP_PROTOCOL": "http/json",
    }
    vars.get(name)
  })
  assert_eq(config.metrics_endpoint, "http://metrics.example/push")
  let tx = @transport.transport_from_otel_config(client, config)
  let outcome = unwrap_outcome(
    @async.with_timeout(1000, () => tx.export_metrics(test_meter())),
  )
  assert_true(outcome.success)
  assert_eq(client.calls[0].url, "http://metrics.example/push")
  assert_true(client.calls[0].body.contains("\"resourceMetrics\""))
}

///|
test "JSON responses report rejected data points" {
  assert_eq(
    @transport.parse_export_response(
      "{\"partialSuccess\":{\"rejectedDataPoints\":\"5\",\"errorMessage\":\"x\"}}",
    ),
    Ok(
      Some({
        rejected_spans: 0L,
        rejected_log_records: 0L,
        rejected_data_points: 5L,
        error_message: "x",
      }),
    ),
  )
}
