///|
pub(all) struct OtlpPayload {
  content_type : String
  body : Bytes
}

///|
pub(all) enum OtlpSignal {
  Traces
  Logs
} derive(Eq, Compare, Debug)

///|
pub fn OtlpSignal::to_string(self : OtlpSignal) -> String {
  match self {
    Traces => "traces"
    Logs => "logs"
  }
}

///|
pub(all) enum EncodingError {
  ProtobufNotImplemented(OtlpSignal)
} derive(Eq, Compare, Debug)

///|
pub fn EncodingError::to_string(self : EncodingError) -> String {
  match self {
    ProtobufNotImplemented(signal) =>
      "protobuf OTLP " + signal.to_string() + " encoding is not implemented"
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
pub fn OtlpEncoder::encode_spans(
  self : OtlpEncoder,
  spans : Array[@otlp.OtlpSpan],
  resource? : @otlp.Resource = @otlp.resource(),
  scope? : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[OtlpPayload, EncodingError] {
  match self {
    JsonEncoder => Ok(json_payload(@otlp.wrap_spans(spans, resource~, scope~)))
    ProtobufEncoder => Err(ProtobufNotImplemented(Traces))
  }
}

///|
pub fn OtlpEncoder::encode_logs(
  self : OtlpEncoder,
  records : Array[@otlp.OtlpLogRecord],
  resource? : @otlp.Resource = @otlp.resource(),
  scope? : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[OtlpPayload, EncodingError] {
  match self {
    JsonEncoder =>
      Ok(json_payload(@otlp.wrap_log_records(records, resource~, scope~)))
    ProtobufEncoder => Err(ProtobufNotImplemented(Logs))
  }
}
