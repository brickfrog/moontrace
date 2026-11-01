///|
pub(all) struct OtlpHttpTransport {
  client : &OtlpHttpClient
  endpoint : String
  traces_path : String
  logs_path : String
  metrics_path : String
  headers : Map[String, String]
  max_retries : Int32
  base_backoff_ms : Int32
  encoder : OtlpEncoder
  compression : OtlpCompression
  mut is_shut_down : Bool
}

///|
pub fn transport(
  client : &OtlpHttpClient,
  endpoint : String,
  traces_path~ : String = "/v1/traces",
  logs_path~ : String = "/v1/logs",
  metrics_path~ : String = "/v1/metrics",
  headers~ : Map[String, String] = default_headers(),
  max_retries~ : Int32 = 3,
  base_backoff_ms~ : Int32 = 1000,
  encoder~ : OtlpEncoder = JsonEncoder,
  compression~ : OtlpCompression = NoCompression,
) -> OtlpHttpTransport {
  {
    client,
    endpoint,
    traces_path,
    logs_path,
    metrics_path,
    headers: copy_headers(headers),
    max_retries: if max_retries < 0 {
      0
    } else {
      max_retries
    },
    base_backoff_ms: if base_backoff_ms < 0 {
      0
    } else {
      base_backoff_ms
    },
    encoder,
    compression,
    is_shut_down: false,
  }
}

///|
pub fn OtlpHttpTransport::shutdown(self : OtlpHttpTransport) -> Unit {
  self.is_shut_down = true
}

///|
fn shutdown_error() -> TransportError {
  Request("OTLP HTTP transport is shut down")
}

///|
fn OtlpHttpTransport::ensure_open(
  self : OtlpHttpTransport,
) -> Result[Unit, TransportError] {
  if self.is_shut_down {
    Err(shutdown_error())
  } else {
    Ok(())
  }
}

///|
async fn OtlpHttpTransport::wait_before_retry(
  self : OtlpHttpTransport,
  delay_ms : Int32,
) -> Result[Unit, TransportError] {
  match self.ensure_open() {
    Err(err) => return Err(err)
    Ok(_) => ()
  }
  if delay_ms <= 0 {
    @async.pause()
    return self.ensure_open()
  }
  for remaining = delay_ms; remaining > 0; {
    let chunk = if remaining > 50 { 50 } else { remaining }
    @async.sleep(chunk)
    match self.ensure_open() {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    continue remaining - chunk
  } nobreak {
    Ok(())
  }
}

///|
/// How to read a successful response body for partial-success details.
priv enum ResponseFormat {
  JsonResponse
  ProtobufResponse(OtlpSignal)
}

///|
/// Set `name` to `value`, replacing any header with the same name in any case.
fn set_header_ci(
  headers : Map[String, String],
  name : String,
  value : String,
) -> Unit {
  let lower = name.to_lower()
  let existing = headers.keys().filter(key => key.to_lower() == lower).collect()
  existing.each(key => headers.remove(key))
  headers.set(name, value)
}

///|
/// Send `body` with retries. `content_type` replaces the configured
/// Content-Type when given, and the transport's compression is applied once
/// before the first attempt.
async fn OtlpHttpTransport::export_body_impl(
  self : OtlpHttpTransport,
  url : String,
  body : Bytes,
  content_type : String?,
  format : ResponseFormat,
  on_partial : (ExportPartialSuccess) -> Unit,
) -> Result[ExportOutcome, TransportError] {
  let headers = copy_headers(self.headers)
  if content_type is Some(value) {
    set_header_ci(headers, "Content-Type", value)
  }
  let body = match self.compression {
    NoCompression => body
    GzipCompression => {
      set_header_ci(headers, "Content-Encoding", "gzip")
      gzip_bytes(body) catch {
        err => return Err(Request("gzip compression failed: \{err}"))
      }
    }
  }
  let max_attempts = self.max_retries + 1
  for attempts = 1; attempts <= max_attempts; {
    match self.ensure_open() {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    let result = self.client.post_bytes(url, body, copy_headers(headers))
    match result {
      Ok(response) => {
        let retry_class = classify_status(response.status_code)
        match retry_class {
          Success => {
            let parsed = match format {
              JsonResponse =>
                parse_export_response(@utf8.decode_lossy(response.body))
              ProtobufResponse(signal) =>
                parse_protobuf_export_response(response.body, signal)
            }
            let partial = match parsed {
              Ok(value) => value
              Err(error) => return Err(error)
            }
            let rejected = match partial {
              None => false
              Some(details) => {
                on_partial(details)
                details.rejected_spans > 0L ||
                details.rejected_log_records > 0L ||
                details.rejected_data_points > 0L
              }
            }
            return Ok({
              success: !rejected,
              attempts,
              status_code: Some(response.status_code),
              error: if rejected {
                let details = partial.unwrap()
                Some(
                  Request(
                    "OTLP partial rejection: rejectedSpans=\{details.rejected_spans}, rejectedLogRecords=\{details.rejected_log_records}, rejectedDataPoints=\{details.rejected_data_points}: \{details.error_message}",
                  ),
                )
              } else {
                None
              },
              retry_class: if rejected {
                NonRetryable
              } else {
                Success
              },
            })
          }
          NonRetryable =>
            return Ok({
              success: false,
              attempts,
              status_code: Some(response.status_code),
              error: None,
              retry_class,
            })
          Retryable =>
            if attempts >= max_attempts {
              return Ok({
                success: false,
                attempts,
                status_code: Some(response.status_code),
                error: None,
                retry_class,
              })
            } else {
              let delay = retry_delay_ms(
                response.retry_after_ms,
                self.base_backoff_ms,
                attempts,
              )
              match self.wait_before_retry(delay) {
                Err(err) => return Err(err)
                Ok(_) => ()
              }
            }
        }
      }
      Err(error) => {
        let retry_class = classify_error(error)
        match retry_class {
          Success => abort("errors cannot classify as success")
          NonRetryable => return Err(error)
          Retryable =>
            if attempts >= max_attempts {
              return Ok({
                success: false,
                attempts,
                status_code: None,
                error: Some(error),
                retry_class,
              })
            } else {
              let delay = retry_delay_ms(None, self.base_backoff_ms, attempts)
              match self.wait_before_retry(delay) {
                Err(err) => return Err(err)
                Ok(_) => ()
              }
            }
        }
      }
    }
    continue attempts + 1
  } nobreak {
    Ok({
      success: false,
      attempts: max_attempts,
      status_code: None,
      error: Some(Request("retry loop exhausted without a final result")),
      retry_class: NonRetryable,
    })
  }
}

///|
/// Encode with the transport's encoder and export with partial details.
async fn OtlpHttpTransport::export_encoded(
  self : OtlpHttpTransport,
  url : String,
  signal : OtlpSignal,
  encoded : Result[OtlpPayload, EncodingError],
  on_partial : (ExportPartialSuccess) -> Unit,
) -> Result[ExportOutcome, TransportError] {
  let payload = match encoded {
    Ok(payload) => payload
    Err(err) => return Err(Request(err.to_string()))
  }
  let format = match self.encoder {
    JsonEncoder => JsonResponse
    ProtobufEncoder => ProtobufResponse(signal)
  }
  self.export_body_impl(
    url,
    payload.body,
    Some(payload.content_type),
    format,
    on_partial,
  )
}

///|
/// Export spans using the transport's encoder and compression.
pub async fn OtlpHttpTransport::export_spans(
  self : OtlpHttpTransport,
  spans : Array[@otlp.OtlpSpan],
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[ExportOutcome, TransportError] {
  self.export_encoded(
    join_url(self.endpoint, self.traces_path),
    Traces,
    self.encoder.encode_spans(spans, resource~, scope~),
    _ => (),
  )
}

///|
/// Export log records using the transport's encoder and compression.
pub async fn OtlpHttpTransport::export_logs(
  self : OtlpHttpTransport,
  records : Array[@otlp.OtlpLogRecord],
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[ExportOutcome, TransportError] {
  self.export_encoded(
    join_url(self.endpoint, self.logs_path),
    Logs,
    self.encoder.encode_logs(records, resource~, scope~),
    _ => (),
  )
}

///|
/// Export a pre-serialized OTLP JSON payload, treating partial rejection as a
/// non-retryable unsuccessful outcome. The transport's compression applies;
/// its encoder does not.
pub async fn OtlpHttpTransport::export_json(
  self : OtlpHttpTransport,
  url : String,
  payload : String,
) -> Result[ExportOutcome, TransportError] {
  self.export_body_impl(url, @utf8.encode(payload), None, JsonResponse, _ => ())
}

///|
/// Export JSON with structured collector partial-success details, including warnings.
pub async fn OtlpHttpTransport::export_json_report(
  self : OtlpHttpTransport,
  url : String,
  payload : String,
) -> Result[ExportReport, TransportError] {
  let partial = Ref(None)
  match
    self.export_body_impl(url, @utf8.encode(payload), None, JsonResponse, value => {
      partial.val = Some(value)
    }) {
    Ok(outcome) => Ok({ outcome, partial_success: partial.val, })
    Err(error) => Err(error)
  }
}

///|
pub async fn OtlpHttpTransport::export_spans_report(
  self : OtlpHttpTransport,
  spans : Array[@otlp.OtlpSpan],
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[ExportReport, TransportError] {
  let partial = Ref(None)
  match
    self.export_encoded(
      join_url(self.endpoint, self.traces_path),
      Traces,
      self.encoder.encode_spans(spans, resource~, scope~),
      value => partial.val = Some(value),
    ) {
    Ok(outcome) => Ok({ outcome, partial_success: partial.val, })
    Err(error) => Err(error)
  }
}

///|
pub async fn OtlpHttpTransport::export_logs_report(
  self : OtlpHttpTransport,
  records : Array[@otlp.OtlpLogRecord],
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[ExportReport, TransportError] {
  let partial = Ref(None)
  match
    self.export_encoded(
      join_url(self.endpoint, self.logs_path),
      Logs,
      self.encoder.encode_logs(records, resource~, scope~),
      value => partial.val = Some(value),
    ) {
    Ok(outcome) => Ok({ outcome, partial_success: partial.val, })
    Err(error) => Err(error)
  }
}

///|
/// Collect `meter` and export the cumulative metrics to `metrics_path` using
/// the transport's encoder and compression, with the meter as the
/// instrumentation scope. Call it periodically, e.g. from a timer task.
pub async fn OtlpHttpTransport::export_metrics(
  self : OtlpHttpTransport,
  meter : @metrics.Meter,
  resource~ : @otlp.Resource = @otlp.default_resource(),
) -> Result[ExportOutcome, TransportError] {
  self.export_encoded(
    join_url(self.endpoint, self.metrics_path),
    Metrics,
    self.encoder.encode_metrics(meter.collect(), resource~, scope=meter.scope()),
    _ => (),
  )
}

///|
/// Like `export_metrics`, with structured collector partial-success details.
pub async fn OtlpHttpTransport::export_metrics_report(
  self : OtlpHttpTransport,
  meter : @metrics.Meter,
  resource~ : @otlp.Resource = @otlp.default_resource(),
) -> Result[ExportReport, TransportError] {
  let partial = Ref(None)
  match
    self.export_encoded(
      join_url(self.endpoint, self.metrics_path),
      Metrics,
      self.encoder.encode_metrics(
        meter.collect(),
        resource~,
        scope=meter.scope(),
      ),
      value => partial.val = Some(value),
    ) {
    Ok(outcome) => Ok({ outcome, partial_success: partial.val, })
    Err(error) => Err(error)
  }
}
