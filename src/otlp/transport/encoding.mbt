///|
pub(all) struct OtlpPayload {
  content_type : String
  body : Bytes
}

///|
pub(all) enum OtlpSignal {
  Traces
  Logs
  Metrics
} derive(Eq, Compare, Debug)

///|
pub fn OtlpSignal::to_string(self : OtlpSignal) -> String {
  match self {
    Traces => "traces"
    Logs => "logs"
    Metrics => "metrics"
  }
}

///|
pub(all) enum EncodingError {
  ProtobufNotImplemented(OtlpSignal)
  ProtobufEncodeFailed(OtlpSignal, String)
} derive(Eq, Compare, Debug)

///|
pub fn EncodingError::to_string(self : EncodingError) -> String {
  match self {
    ProtobufNotImplemented(signal) =>
      "protobuf OTLP " + signal.to_string() + " encoding is not implemented"
    ProtobufEncodeFailed(signal, message) =>
      "protobuf OTLP " + signal.to_string() + " encoding failed: " + message
  }
}

///|
pub impl Show for EncodingError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) enum OtlpEncoder {
  JsonEncoder
  ProtobufEncoder
} derive(Eq, Compare, Debug)

///|
pub fn json_encoder() -> OtlpEncoder {
  JsonEncoder
}

///|
pub fn protobuf_encoder() -> OtlpEncoder {
  ProtobufEncoder
}

///|
pub fn otlp_json_content_type() -> String {
  "application/json"
}

///|
pub fn otlp_protobuf_content_type() -> String {
  "application/x-protobuf"
}

///|
pub fn OtlpEncoder::content_type(self : OtlpEncoder) -> String {
  match self {
    JsonEncoder => otlp_json_content_type()
    ProtobufEncoder => otlp_protobuf_content_type()
  }
}

///|
fn json_payload(json : Json) -> OtlpPayload {
  {
    content_type: otlp_json_content_type(),
    body: @utf8.encode(json.stringify()),
  }
}

///|
priv suberror ProtobufWireError {
  InvalidHexId(String, String)
  InvalidUnsignedField(String, Int32)
}

///|
fn encode_protobuf_payload(
  signal : OtlpSignal,
  write_body : (&@protobuf.Writer) -> Unit raise,
) -> Result[OtlpPayload, EncodingError] {
  let body = Buffer()
  let writer : &@protobuf.Writer = body
  try {
    write_body(writer)
    Ok({ content_type: otlp_protobuf_content_type(), body: body.to_bytes(), })
  } catch {
    InvalidHexId(field, value) =>
      Err(
        ProtobufEncodeFailed(
          signal,
          "invalid hex bytes for " + field + ": " + value,
        ),
      )
    InvalidUnsignedField(field, value) =>
      Err(
        ProtobufEncodeFailed(
          signal,
          "negative value for unsigned " + field + ": " + value.to_string(),
        ),
      )
    err => Err(ProtobufEncodeFailed(signal, "\{err}"))
  }
}

///|
fn protobuf_message_field(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  write_body : (&@protobuf.Writer) -> Unit raise,
) -> Unit raise {
  let body = Buffer()
  let nested_writer : &@protobuf.Writer = body
  write_body(nested_writer)
  writer |> @protobuf.write_tag((field_number, 2))
  writer |> @protobuf.write_uint32(body.length().reinterpret_as_uint())
  writer.write(body.to_bytes())
}

///|
fn protobuf_string_field(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  value : String,
) -> Unit raise {
  if !value.is_empty() {
    writer |> @protobuf.write_tag((field_number, 2))
    writer |> @protobuf.write_string(value)
  }
}

///|
fn protobuf_bytes_field(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  value : Bytes,
) -> Unit raise {
  if value.length() > 0 {
    writer |> @protobuf.write_tag((field_number, 2))
    writer |> @protobuf.write_bytes(value)
  }
}

///|
fn protobuf_uint32_field(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  value : UInt32,
) -> Unit raise {
  if value != 0 {
    writer |> @protobuf.write_tag((field_number, 0))
    writer |> @protobuf.write_uint32(value)
  }
}

///|
fn protobuf_fixed32_field(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  value : UInt32,
) -> Unit raise {
  if value != 0 {
    writer |> @protobuf.write_tag((field_number, 5))
    writer |> @protobuf.write_fixed32(value)
  }
}

///|
fn protobuf_fixed64_field(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  value : UInt64,
) -> Unit raise {
  if value != 0UL {
    writer |> @protobuf.write_tag((field_number, 1))
    writer |> @protobuf.write_fixed64(value)
  }
}

///|
fn protobuf_bool_field(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  value : Bool,
) -> Unit raise {
  writer |> @protobuf.write_tag((field_number, 0))
  writer |> @protobuf.write_bool(value)
}

///|
fn protobuf_int64_field(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  value : Int64,
) -> Unit raise {
  writer |> @protobuf.write_tag((field_number, 0))
  writer |> @protobuf.write_int64(value)
}

///|
fn protobuf_double_field(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  value : Double,
) -> Unit raise {
  writer |> @protobuf.write_tag((field_number, 1))
  writer |> @protobuf.write_double(value)
}

///|
fn unsigned_int(field : String, value : Int32) -> UInt32 raise {
  if value < 0 {
    raise InvalidUnsignedField(field, value)
  }
  value.reinterpret_as_uint()
}

///|
fn hex_id_bytes(
  field : String,
  value : String,
  expected_bytes : Int32,
) -> Bytes raise {
  if value.length() != expected_bytes * 2 {
    raise InvalidHexId(field, value)
  }
  let bytes = Buffer(size_hint=expected_bytes)
  for index = 0; index < value.length(); {
    let pair = value[index:index + 2].to_owned()
    let byte = @string.parse_int(pair, base=16) catch {
      _ => raise InvalidHexId(field, value)
    }
    if byte < 0 || byte > 255 {
      raise InvalidHexId(field, value)
    }
    bytes.write_byte(byte.to_byte())
    continue index + 2
  }
  bytes.to_bytes()
}

///|
fn optional_hex_id_bytes(
  field : String,
  value : String,
  expected_bytes : Int32,
) -> Bytes raise {
  if value.is_empty() {
    b""
  } else {
    hex_id_bytes(field, value, expected_bytes)
  }
}

///|
fn write_any_value(
  writer : &@protobuf.Writer,
  value : @otlp.OtlpValue,
) -> Unit raise {
  match value {
    StringVal(value) => {
      writer |> @protobuf.write_tag((1, 2))
      writer |> @protobuf.write_string(value)
    }
    BoolVal(value) => protobuf_bool_field(writer, 2, value)
    IntVal(value) => protobuf_int64_field(writer, 3, value)
    DoubleVal(value) => protobuf_double_field(writer, 4, value)
    ArrayVal(values) =>
      protobuf_message_field(writer, 5, writer => {
        for value in values {
          protobuf_message_field(writer, 1, writer => {
            write_any_value(writer, value)
          })
        }
      })
    KvlistVal(entries) =>
      protobuf_message_field(writer, 6, writer => {
        write_key_values(writer, 1, entries)
      })
  }
}

///|
fn write_key_value(
  writer : &@protobuf.Writer,
  attribute : @otlp.OtlpAttribute,
) -> Unit raise {
  protobuf_string_field(writer, 1, attribute.key)
  protobuf_message_field(writer, 2, writer => {
    write_any_value(writer, attribute.value)
  })
}

///|
fn write_key_values(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  attributes : Array[@otlp.OtlpAttribute],
) -> Unit raise {
  for attribute in attributes {
    protobuf_message_field(writer, field_number, writer => {
      write_key_value(writer, attribute)
    })
  }
}

///|
fn write_resource(
  writer : &@protobuf.Writer,
  resource : @otlp.Resource,
) -> Unit raise {
  write_key_values(writer, 1, resource.attributes)
}

///|
fn write_instrumentation_scope(
  writer : &@protobuf.Writer,
  scope : @otlp.InstrumentationScope,
) -> Unit raise {
  protobuf_string_field(writer, 1, scope.name)
  protobuf_string_field(writer, 2, scope.version)
  write_key_values(writer, 3, scope.attributes)
}

///|
fn write_status(
  writer : &@protobuf.Writer,
  status_code : Int32,
  status_message : String,
) -> Unit raise {
  protobuf_string_field(writer, 2, status_message)
  protobuf_uint32_field(
    writer,
    3,
    unsigned_int("span.status.code", status_code),
  )
}

///|
fn write_span_link(
  writer : &@protobuf.Writer,
  link : @otlp.OtlpLink,
) -> Unit raise {
  protobuf_bytes_field(
    writer,
    1,
    hex_id_bytes("link.trace_id", link.trace_id, 16),
  )
  protobuf_bytes_field(writer, 2, hex_id_bytes("link.span_id", link.span_id, 8))
  protobuf_string_field(writer, 3, link.trace_state)
  write_key_values(writer, 4, link.attributes)
  protobuf_uint32_field(
    writer,
    5,
    unsigned_int("link.dropped_attributes_count", link.dropped_attributes_count),
  )
}

///|
fn write_span(writer : &@protobuf.Writer, span : @otlp.OtlpSpan) -> Unit raise {
  protobuf_bytes_field(
    writer,
    1,
    hex_id_bytes("span.trace_id", span.trace_id, 16),
  )
  protobuf_bytes_field(writer, 2, hex_id_bytes("span.span_id", span.span_id, 8))
  protobuf_bytes_field(
    writer,
    4,
    optional_hex_id_bytes("span.parent_span_id", span.parent_span_id, 8),
  )
  protobuf_string_field(writer, 5, span.name)
  protobuf_uint32_field(writer, 6, unsigned_int("span.kind", span.kind))
  protobuf_fixed64_field(writer, 7, span.start_time_unix_nano)
  protobuf_fixed64_field(writer, 8, span.end_time_unix_nano)
  write_key_values(writer, 9, span.attributes)
  protobuf_uint32_field(
    writer,
    10,
    unsigned_int("span.dropped_attributes_count", span.dropped_attributes_count),
  )
  for event in span.events {
    protobuf_message_field(writer, 11, writer => {
      protobuf_fixed64_field(writer, 1, event.time_unix_nano)
      protobuf_string_field(writer, 2, event.name)
      write_key_values(writer, 3, event.attributes)
      protobuf_uint32_field(
        writer,
        4,
        unsigned_int(
          "event.dropped_attributes_count",
          event.dropped_attributes_count,
        ),
      )
    })
  }
  protobuf_uint32_field(
    writer,
    12,
    unsigned_int("span.dropped_events_count", span.dropped_events_count),
  )
  for link in span.links {
    protobuf_message_field(writer, 13, writer => write_span_link(writer, link))
  }
  protobuf_uint32_field(
    writer,
    14,
    unsigned_int("span.dropped_links_count", span.dropped_links_count),
  )
  if span.status_code != 0 || !span.status_message.is_empty() {
    protobuf_message_field(writer, 15, writer => {
      write_status(writer, span.status_code, span.status_message)
    })
  }
  protobuf_fixed32_field(writer, 16, unsigned_int("span.flags", span.flags))
}

///|
fn write_scope_spans(
  writer : &@protobuf.Writer,
  spans : Array[@otlp.OtlpSpan],
  scope : @otlp.InstrumentationScope,
) -> Unit raise {
  protobuf_message_field(writer, 1, writer => {
    write_instrumentation_scope(writer, scope)
  })
  for span in spans {
    protobuf_message_field(writer, 2, writer => write_span(writer, span))
  }
}

///|
fn write_resource_spans(
  writer : &@protobuf.Writer,
  spans : Array[@otlp.OtlpSpan],
  resource : @otlp.Resource,
  scope : @otlp.InstrumentationScope,
) -> Unit raise {
  protobuf_message_field(writer, 1, writer => write_resource(writer, resource))
  protobuf_message_field(writer, 2, writer => {
    write_scope_spans(writer, spans, scope)
  })
}

///|
fn write_export_trace_service_request(
  writer : &@protobuf.Writer,
  spans : Array[@otlp.OtlpSpan],
  resource : @otlp.Resource,
  scope : @otlp.InstrumentationScope,
) -> Unit raise {
  protobuf_message_field(writer, 1, writer => {
    write_resource_spans(writer, spans, resource, scope)
  })
}

///|
fn write_log_record(
  writer : &@protobuf.Writer,
  record : @otlp.OtlpLogRecord,
) -> Unit raise {
  protobuf_fixed64_field(writer, 1, record.time_unix_nano)
  protobuf_uint32_field(
    writer,
    2,
    unsigned_int("log_record.severity_number", record.severity_number),
  )
  protobuf_string_field(writer, 3, record.severity_text)
  protobuf_message_field(writer, 5, writer => {
    write_any_value(writer, StringVal(record.body))
  })
  write_key_values(writer, 6, record.attributes)
  protobuf_uint32_field(
    writer,
    7,
    unsigned_int(
      "log_record.dropped_attributes_count",
      record.dropped_attributes_count,
    ),
  )
  protobuf_bytes_field(
    writer,
    9,
    optional_hex_id_bytes("log_record.trace_id", record.trace_id, 16),
  )
  protobuf_bytes_field(
    writer,
    10,
    optional_hex_id_bytes("log_record.span_id", record.span_id, 8),
  )
}

///|
fn write_scope_logs(
  writer : &@protobuf.Writer,
  records : Array[@otlp.OtlpLogRecord],
  scope : @otlp.InstrumentationScope,
) -> Unit raise {
  protobuf_message_field(writer, 1, writer => {
    write_instrumentation_scope(writer, scope)
  })
  for record in records {
    protobuf_message_field(writer, 2, writer => write_log_record(writer, record))
  }
}

///|
fn write_resource_logs(
  writer : &@protobuf.Writer,
  records : Array[@otlp.OtlpLogRecord],
  resource : @otlp.Resource,
  scope : @otlp.InstrumentationScope,
) -> Unit raise {
  protobuf_message_field(writer, 1, writer => write_resource(writer, resource))
  protobuf_message_field(writer, 2, writer => {
    write_scope_logs(writer, records, scope)
  })
}

///|
fn write_export_logs_service_request(
  writer : &@protobuf.Writer,
  records : Array[@otlp.OtlpLogRecord],
  resource : @otlp.Resource,
  scope : @otlp.InstrumentationScope,
) -> Unit raise {
  protobuf_message_field(writer, 1, writer => {
    write_resource_logs(writer, records, resource, scope)
  })
}

///|
pub fn OtlpEncoder::encode_spans(
  self : OtlpEncoder,
  spans : Array[@otlp.OtlpSpan],
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[OtlpPayload, EncodingError] {
  match self {
    JsonEncoder => Ok(json_payload(@otlp.wrap_spans(spans, resource~, scope~)))
    ProtobufEncoder =>
      encode_protobuf_payload(Traces, writer => {
        write_export_trace_service_request(writer, spans, resource, scope)
      })
  }
}

///|
pub fn OtlpEncoder::encode_logs(
  self : OtlpEncoder,
  records : Array[@otlp.OtlpLogRecord],
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[OtlpPayload, EncodingError] {
  match self {
    JsonEncoder =>
      Ok(json_payload(@otlp.wrap_log_records(records, resource~, scope~)))
    ProtobufEncoder =>
      encode_protobuf_payload(Logs, writer => {
        write_export_logs_service_request(writer, records, resource, scope)
      })
  }
}

///|
fn write_number_data_point(
  writer : &@protobuf.Writer,
  metric : @metrics.MetricData,
  point : @metrics.MetricPoint,
) -> Unit raise {
  protobuf_fixed64_field(writer, 2, milliseconds_to_nanos(metric.start_time_ms))
  protobuf_fixed64_field(writer, 3, milliseconds_to_nanos(metric.time_ms))
  protobuf_double_field(writer, 4, point.value)
  write_key_values(
    writer,
    7,
    point.attributes.map(field => @otlp.field_to_attribute(field)),
  )
}

///|
/// Write a packed repeated fixed64 or double field from raw 8-byte values.
fn write_packed_fixed64s(
  writer : &@protobuf.Writer,
  field_number : UInt32,
  write_values : (&@protobuf.Writer) -> Unit raise,
) -> Unit raise {
  protobuf_message_field(writer, field_number, write_values)
}

///|
fn write_histogram_data_point(
  writer : &@protobuf.Writer,
  metric : @metrics.MetricData,
  point : @metrics.MetricPoint,
) -> Unit raise {
  protobuf_fixed64_field(writer, 2, milliseconds_to_nanos(metric.start_time_ms))
  protobuf_fixed64_field(writer, 3, milliseconds_to_nanos(metric.time_ms))
  protobuf_fixed64_field(writer, 4, point.count.reinterpret_as_uint64())
  protobuf_double_field(writer, 5, point.value)
  write_packed_fixed64s(writer, 6, writer => {
    for count in point.bucket_counts {
      writer |> @protobuf.write_fixed64(count.reinterpret_as_uint64())
    }
  })
  if !metric.bucket_bounds.is_empty() {
    write_packed_fixed64s(writer, 7, writer => {
      for bound in metric.bucket_bounds {
        writer |> @protobuf.write_double(bound)
      }
    })
  }
  write_key_values(
    writer,
    9,
    point.attributes.map(field => @otlp.field_to_attribute(field)),
  )
  if point.count > 0L {
    protobuf_double_field(writer, 11, point.min)
    protobuf_double_field(writer, 12, point.max)
  }
}

///|
/// AGGREGATION_TEMPORALITY_CUMULATIVE
const CUMULATIVE_TEMPORALITY : UInt32 = 2

///|
fn write_metric(
  writer : &@protobuf.Writer,
  metric : @metrics.MetricData,
) -> Unit raise {
  protobuf_string_field(writer, 1, metric.name)
  protobuf_string_field(writer, 2, metric.description)
  protobuf_string_field(writer, 3, metric.unit)
  match metric.kind {
    MonotonicSum | NonMonotonicSum =>
      protobuf_message_field(writer, 7, writer => {
        for point in metric.points {
          protobuf_message_field(writer, 1, writer => {
            write_number_data_point(writer, metric, point)
          })
        }
        protobuf_uint32_field(writer, 2, CUMULATIVE_TEMPORALITY)
        if metric.kind is MonotonicSum {
          protobuf_bool_field(writer, 3, true)
        }
      })
    ExplicitHistogram =>
      protobuf_message_field(writer, 9, writer => {
        for point in metric.points {
          protobuf_message_field(writer, 1, writer => {
            write_histogram_data_point(writer, metric, point)
          })
        }
        protobuf_uint32_field(writer, 2, CUMULATIVE_TEMPORALITY)
      })
  }
}

///|
fn write_export_metrics_service_request(
  writer : &@protobuf.Writer,
  metrics : Array[@metrics.MetricData],
  resource : @otlp.Resource,
  scope : @otlp.InstrumentationScope,
) -> Unit raise {
  protobuf_message_field(writer, 1, writer => {
    protobuf_message_field(writer, 1, writer => write_resource(writer, resource))
    protobuf_message_field(writer, 2, writer => {
      protobuf_message_field(writer, 1, writer => {
        write_instrumentation_scope(writer, scope)
      })
      for metric in metrics {
        protobuf_message_field(writer, 2, writer => write_metric(writer, metric))
      }
    })
  })
}

///|
/// Milliseconds to nanoseconds, saturating at `UInt64` maximum.
fn milliseconds_to_nanos(ms : UInt64) -> UInt64 {
  if ms > 18446744073709UL {
    18446744073709551615UL
  } else {
    ms * 1_000_000UL
  }
}

///|
/// Encode collected metrics as an `ExportMetricsServiceRequest` in this
/// encoder's format.
pub fn OtlpEncoder::encode_metrics(
  self : OtlpEncoder,
  metrics : Array[@metrics.MetricData],
  resource~ : @otlp.Resource = @otlp.default_resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[OtlpPayload, EncodingError] {
  match self {
    JsonEncoder =>
      Ok(
        json_payload(@metrics.metrics_to_otlp_json(metrics, resource~, scope~)),
      )
    ProtobufEncoder =>
      encode_protobuf_payload(Metrics, writer => {
        write_export_metrics_service_request(writer, metrics, resource, scope)
      })
  }
}
