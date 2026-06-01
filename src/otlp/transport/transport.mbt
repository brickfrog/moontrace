///|
pub(all) struct OtlpHttpTransport {
  client : &OtlpHttpClient
  endpoint : String
  traces_path : String
  logs_path : String
  headers : Map[String, String]
  max_retries : Int
  base_backoff_ms : Int
  mut is_shut_down : Bool
}

///|
pub fn transport(
  client : &OtlpHttpClient,
  endpoint : String,
  traces_path? : String = "/v1/traces",
  logs_path? : String = "/v1/logs",
  headers? : Map[String, String] = default_headers(),
  max_retries? : Int = 3,
  base_backoff_ms? : Int = 1000,
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
pub async fn OtlpHttpTransport::export_json(
  self : OtlpHttpTransport,
  url : String,
  payload : String,
) -> Result[ExportOutcome, TransportError] {
  if self.is_shut_down {
    return Err(Request("OTLP HTTP transport is shut down"))
  }
  let max_attempts = self.max_retries + 1
  for attempts = 1; attempts <= max_attempts; {
    let result = self.client.post(url, payload, copy_headers(self.headers))
    match result {
      Ok(response) => {
        let retry_class = classify_status(response.status_code)
        match retry_class {
          Success =>
            return Ok({
              success: true,
              attempts,
              status_code: Some(response.status_code),
              error: None,
              retry_class,
            })
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
              if delay > 0 {
                @async.sleep(delay)
              } else {
                @async.pause()
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
              if delay > 0 {
                @async.sleep(delay)
              } else {
                @async.pause()
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
  resource? : @otlp.Resource = @otlp.resource(),
  scope? : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[ExportOutcome, TransportError] {
  let payload = @otlp.wrap_spans(spans, resource~, scope~).stringify()
  self.export_json(join_url(self.endpoint, self.traces_path), payload)
}

///|
pub async fn OtlpHttpTransport::export_logs(
  self : OtlpHttpTransport,
  records : Array[@otlp.OtlpLogRecord],
  resource? : @otlp.Resource = @otlp.resource(),
  scope? : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Result[ExportOutcome, TransportError] {
  let payload = @otlp.wrap_log_records(records, resource~, scope~).stringify()
  self.export_json(join_url(self.endpoint, self.logs_path), payload)
}
