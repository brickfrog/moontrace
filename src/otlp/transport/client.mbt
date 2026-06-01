///|
pub(all) struct AsyncHttpClient {
  timeout_ms : Int
  mut is_shut_down : Bool
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
    let (response, data) = @http.post(url, content, headers~)
    Ok({
      status_code: response.code,
      body: data.text(),
      retry_after_ms: parse_retry_after_ms(response.headers),
    })
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
