///|
pub(all) struct AsyncHttpClient {
  timeout_ms : Int
  mut is_shut_down : Bool
}

///|
#cfg(any(target="native", target="js"))
const MAX_RESPONSE_BODY_BYTES : Int = 64 * 1024

///|
#cfg(any(target="native", target="js"))
const RESPONSE_READ_CHUNK_BYTES : Int = 8 * 1024

///|
#cfg(any(target="native", target="js"))
async fn read_bounded_response_body(
  client : @http.Client,
) -> Result[Bytes, TransportError] {
  let body : Array[Byte] = []
  while client.read_some(max_len=RESPONSE_READ_CHUNK_BYTES) is Some(chunk) {
    if body.length() + chunk.length() > MAX_RESPONSE_BODY_BYTES {
      return Err(Request("HTTP response body exceeds 65536 bytes"))
    }
    for byte in chunk.iter() {
      body.push(byte)
    }
  }
  Ok(Bytes::from_array(body[:]))
}

///|
pub fn async_http_client(timeout_ms? : Int = 5000) -> AsyncHttpClient {
  let timeout_ms = if timeout_ms < 1 { 1 } else { timeout_ms }
  { timeout_ms, is_shut_down: false }
}

///|
pub fn AsyncHttpClient::shutdown(self : AsyncHttpClient) -> Unit {
  self.is_shut_down = true
}

///|
#cfg(any(target="native", target="js"))
pub impl OtlpHttpClient for AsyncHttpClient with fn post(
  self,
  url,
  body,
  headers,
) {
  if self.is_shut_down {
    return Err(Request("HTTP client is shut down"))
  }
  @async.with_timeout(self.timeout_ms, () => {
    let content : &@io.Data = body
    let client = @http.post_stream(url, headers~)
    defer client.close()
    client.write(content)
    let response = client.end_request()
    match read_bounded_response_body(client) {
      Err(err) => Err(err)
      Ok(data) =>
        Ok({
          status_code: response.code,
          body: @utf8.decode(data),
          retry_after_ms: parse_retry_after_ms(response.headers),
        })
    }
  }) catch {
    @async.TimeoutError =>
      Err(Timeout("HTTP request timed out after \{self.timeout_ms}ms"))
    @http.InvalidFormat => Err(Request("invalid HTTP URL"))
    @http.UnsupportedProtocol(protocol) =>
      Err(Request("unsupported HTTP protocol: " + protocol))
    err => Err(Network("\{err}"))
  }
}

///|
#cfg(not(any(target="native", target="js")))
pub impl OtlpHttpClient for AsyncHttpClient with fn post(
  self,
  _url,
  _body,
  _headers,
) {
  if self.is_shut_down {
    Err(Request("HTTP client is shut down"))
  } else {
    Err(Request("moonbitlang/async/http is not available on this target"))
  }
}
