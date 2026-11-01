///|
pub(all) struct HttpResponse {
  status_code : Int32
  body : String
  retry_after_ms : Int32?
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
const MAX_RETRY_AFTER_MS : Int32 = 300000

///|
pub fn classify_status(status_code : Int32) -> RetryClass {
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
  attempts : Int32
  status_code : Int32?
  error : TransportError?
  retry_class : RetryClass
} derive(Eq, Compare, Debug)

///|
/// An HTTP response with the raw body, returned by `OtlpHttpClient::post_bytes`.
pub(all) struct HttpBytesResponse {
  status_code : Int32
  body : Bytes
  retry_after_ms : Int32?
}

///|
/// Request body compression applied by the transport.
pub(all) enum OtlpCompression {
  NoCompression
  /// gzip with `Content-Encoding: gzip`.
  GzipCompression
}

///|
/// HTTP client used by the transport. Implement `post` for text (JSON)
/// bodies. Implement `post_bytes` as well to support protobuf or gzip bodies;
/// the default `post_bytes` forwards UTF-8 bodies to `post` and rejects other
/// bodies with a non-retryable `Request` error.
pub(open) trait OtlpHttpClient {
  async fn post(Self, String, String, Map[String, String]) -> Result[
    HttpResponse,
    TransportError,
  ]
  async fn post_bytes(Self, String, Bytes, Map[String, String]) -> Result[
    HttpBytesResponse,
    TransportError,
  ] = _
}

///|
impl OtlpHttpClient with fn post_bytes(self, url, body, headers) {
  let text = @utf8.decode(body) catch {
    _ =>
      return Err(
        Request(
          "this OTLP HTTP client only sends text bodies; implement post_bytes for protobuf or gzip",
        ),
      )
  }
  match self.post(url, text, headers) {
    Ok(response) =>
      Ok({
        status_code: response.status_code,
        body: @utf8.encode(response.body),
        retry_after_ms: response.retry_after_ms,
      })
    Err(err) => Err(err)
  }
}

///|
pub fn default_headers() -> Map[String, String] {
  { "Content-Type": "application/json" }
}

///|
pub fn parse_retry_after_ms(headers : Map[String, String]) -> Int32? {
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
fn parse_retry_after_value_ms(value : String) -> Int32? {
  let trimmed = value.trim()
  if trimmed.is_empty() {
    None
  } else {
    // Only the delay-seconds Retry-After form is supported here. HTTP-date or
    // otherwise unparseable values safely fall back to exponential backoff.
    let seconds = @string.parse_int(trimmed, base=10) catch { _ => return None }
    if seconds < 0 {
      None
    } else if seconds > MAX_RETRY_AFTER_MS / 1000 {
      Some(MAX_RETRY_AFTER_MS)
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
/// An empty endpoint means `path` is already a full URL.
fn join_url(endpoint : String, path : String) -> String {
  if endpoint.is_empty() {
    path
  } else if endpoint.has_suffix("/") && path.has_prefix("/") {
    endpoint + path[1:].to_owned()
  } else if endpoint.has_suffix("/") || path.has_prefix("/") {
    endpoint + path
  } else {
    endpoint + "/" + path
  }
}

///|
fn retry_delay_ms(
  retry_after_ms : Int32?,
  base_backoff_ms : Int32,
  attempts : Int32,
) -> Int32 {
  match retry_after_ms {
    Some(delay) => clamp_retry_delay_ms(delay)
    None => exponential_backoff_ms(base_backoff_ms, attempts)
  }
}

///|
fn exponential_backoff_ms(base_backoff_ms : Int32, attempts : Int32) -> Int32 {
  if base_backoff_ms <= 0 {
    0
  } else {
    let mut delay = clamp_retry_delay_ms(base_backoff_ms)
    for _ in 1..<attempts {
      if delay >= MAX_RETRY_AFTER_MS / 2 {
        return MAX_RETRY_AFTER_MS
      }
      delay = delay * 2
    }
    clamp_retry_delay_ms(delay)
  }
}

///|
fn clamp_retry_delay_ms(delay_ms : Int32) -> Int32 {
  if delay_ms < 0 {
    0
  } else if delay_ms > MAX_RETRY_AFTER_MS {
    MAX_RETRY_AFTER_MS
  } else {
    delay_ms
  }
}
