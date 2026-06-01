///|
pub(all) struct HttpResponse {
  status_code : Int
  body : String
  retry_after_ms : Int?
} derive(Eq, Compare, Debug)

///|
pub(all) enum TransportError {
  Network(String)
  Timeout(String)
  Request(String)
} derive(Eq, Compare, Debug)

///|
pub fn TransportError::to_string(self : TransportError) -> String {
  match self {
    Network(message) => "network error: " + message
    Timeout(message) => "timeout: " + message
    Request(message) => "request error: " + message
  }
}

///|
pub impl Show for TransportError with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) enum RetryClass {
  Success
  Retryable
  NonRetryable
} derive(Eq, Compare, Debug)

///|
pub fn classify_status(status_code : Int) -> RetryClass {
  if status_code >= 200 && status_code < 300 {
    Success
  } else {
    match status_code {
      429 | 502 | 503 | 504 => Retryable
      _ => NonRetryable
    }
  }
}

///|
pub fn classify_error(error : TransportError) -> RetryClass {
  match error {
    Network(_) | Timeout(_) => Retryable
    Request(_) => NonRetryable
  }
}

///|
pub(all) struct ExportOutcome {
  success : Bool
  attempts : Int
  status_code : Int?
  error : TransportError?
  retry_class : RetryClass
} derive(Eq, Compare, Debug)

///|
pub(open) trait OtlpHttpClient {
  async fn post(Self, String, String, Map[String, String]) -> Result[
    HttpResponse,
    TransportError,
  ]
}

///|
pub fn default_headers() -> Map[String, String] {
  { "Content-Type": "application/json" }
}

///|
pub fn parse_retry_after_ms(headers : Map[String, String]) -> Int? {
  match headers.get("retry-after") {
    Some(value) => parse_retry_after_value_ms(value)
    None =>
      match headers.get("Retry-After") {
        Some(value) => parse_retry_after_value_ms(value)
        None => None
      }
  }
}

///|
fn parse_retry_after_value_ms(value : String) -> Int? {
  let trimmed = value.trim()
  if trimmed.is_empty() {
    None
  } else {
    let seconds = @string.parse_int(trimmed, base=10) catch { _ => return None }
    if seconds < 0 {
      None
    } else {
      Some(seconds * 1000)
    }
  }
}

///|
fn copy_headers(headers : Map[String, String]) -> Map[String, String] {
  headers.copy()
}

///|
fn join_url(endpoint : String, path : String) -> String {
  if endpoint.has_suffix("/") && path.has_prefix("/") {
    endpoint + path[1:].to_owned()
  } else if endpoint.has_suffix("/") || path.has_prefix("/") {
    endpoint + path
  } else {
    endpoint + "/" + path
  }
}

///|
fn retry_delay_ms(
  response : HttpResponse?,
  base_backoff_ms : Int,
  attempts : Int,
) -> Int {
  match response {
    Some(resp) =>
      match resp.retry_after_ms {
        Some(delay) => if delay < 0 { 0 } else { delay }
        None => exponential_backoff_ms(base_backoff_ms, attempts)
      }
    None => exponential_backoff_ms(base_backoff_ms, attempts)
  }
}

///|
fn exponential_backoff_ms(base_backoff_ms : Int, attempts : Int) -> Int {
  if base_backoff_ms <= 0 {
    0
  } else {
    let mut delay = base_backoff_ms
    for _ in 1..<attempts {
      if delay > 1073741823 {
        return delay
      }
      delay = delay * 2
    }
    delay
  }
}
