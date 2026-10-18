///|
pub(all) struct OtlpHttpTransport {
  client : &OtlpHttpClient
  endpoint : String
  traces_path : String
  logs_path : String
  headers : Map[String, String]
  max_retries : Int32
  base_backoff_ms : Int32
  mut is_shut_down : Bool
}

///|
pub fn transport(
  client : &OtlpHttpClient,
  endpoint : String,
  traces_path~ : String = "/v1/traces",
  logs_path~ : String = "/v1/logs",
  headers~ : Map[String, String] = default_headers(),
  max_retries~ : Int32 = 3,
  base_backoff_ms~ : Int32 = 1000,
) -> OtlpHttpTransport {
  {
    client,
    endpoint,
    traces_path,
    logs_path,
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
async fn OtlpHttpTransport::export_json_impl(
  self : OtlpHttpTransport,
  url : String,
  payload : String,
  on_partial : (ExportPartialSuccess) -> Unit,
) -> Result[ExportOutcome, TransportError] {
  let max_attempts = self.max_retries + 1
  for attempts = 1; attempts <= max_attempts; {
    match self.ensure_open() {
      Err(err) => return Err(err)
      Ok(_) => ()
    }
    let result = self.client.post(url, payload, copy_headers(self.headers))
    match result {
      Ok(response) => {
        let retry_class = classify_status(response.status_code)
        match retry_class {
          Success => {
            let partial = match parse_export_response(response.body) {
              Ok(value) => value
              Err(error) => return Err(error)
            }
            let rejected = match partial {
              None => false
              Some(details) => {
                on_partial(details)
                details.rejected_spans > 0L || details.rejected_log_records > 0L
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
                    "OTLP partial rejection: rejectedSpans=\{details.rejected_spans}, rejectedLogRecords=\{details.rejected_log_records}: \{details.error_message}",
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
                Some(response),
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
pub async fn OtlpHttpTransport::export_spans(
  self : OtlpHttpTransport,
  spans : Array[@otlp.OtlpSpan],
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[ExportOutcome, TransportError] {
  let payload = @otlp.wrap_spans(spans, resource~, scope~).stringify()
  self.export_json(join_url(self.endpoint, self.traces_path), payload)
}

///|
pub async fn OtlpHttpTransport::export_logs(
  self : OtlpHttpTransport,
  records : Array[@otlp.OtlpLogRecord],
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[ExportOutcome, TransportError] {
  let payload = @otlp.wrap_log_records(records, resource~, scope~).stringify()
  self.export_json(join_url(self.endpoint, self.logs_path), payload)
}

///|
/// Export JSON, treating partial rejection as a non-retryable unsuccessful outcome.
pub async fn OtlpHttpTransport::export_json(
  self : OtlpHttpTransport,
  url : String,
  payload : String,
) -> Result[ExportOutcome, TransportError] {
  self.export_json_impl(url, payload, _ => ())
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
    self.export_json_impl(url, payload, value => partial.val = Some(value)) {
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
  self.export_json_report(
    join_url(self.endpoint, self.traces_path),
    @otlp.wrap_spans(spans, resource~, scope~).stringify(),
  )
}

///|
pub async fn OtlpHttpTransport::export_logs_report(
  self : OtlpHttpTransport,
  records : Array[@otlp.OtlpLogRecord],
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[ExportReport, TransportError] {
  self.export_json_report(
    join_url(self.endpoint, self.logs_path),
    @otlp.wrap_log_records(records, resource~, scope~).stringify(),
  )
}
