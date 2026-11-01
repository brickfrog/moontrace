///|
/// `http.request.method`, e.g. `GET`.
pub fn http_request_method(request_method : String) -> @moontrace.Field {
  @moontrace.field("http.request.method", request_method)
}

///|
/// `http.response.status_code`, e.g. `200`.
pub fn http_response_status_code(status : Int32) -> @moontrace.Field {
  @moontrace.field("http.response.status_code", status)
}

///|
/// `http.route`: the matched route template, e.g. `/users/{id}`.
pub fn http_route(route : String) -> @moontrace.Field {
  @moontrace.field("http.route", route)
}

///|
/// `url.path`, e.g. `/users/42`.
pub fn url_path(path : String) -> @moontrace.Field {
  @moontrace.field("url.path", path)
}

///|
/// `url.scheme`, e.g. `https`.
pub fn url_scheme(scheme : String) -> @moontrace.Field {
  @moontrace.field("url.scheme", scheme)
}

///|
/// `url.full`: the absolute request URL. Redact credentials before passing it.
pub fn url_full(url : String) -> @moontrace.Field {
  @moontrace.field("url.full", url)
}

///|
/// `server.address`: the server host name or address.
pub fn server_address(address : String) -> @moontrace.Field {
  @moontrace.field("server.address", address)
}

///|
/// `user_agent.original`: the raw `User-Agent` header value.
pub fn user_agent_original(user_agent : String) -> @moontrace.Field {
  @moontrace.field("user_agent.original", user_agent)
}

///|
/// The common server-side request fields: method, route (when known), and
/// path. Add `http_response_status_code` when the response is known.
pub fn http_server_request(
  request_method : String,
  path : String,
  route? : String,
) -> Array[@moontrace.Field] {
  let fields = [http_request_method(request_method)]
  if route is Some(route) {
    fields.push(http_route(route))
  }
  fields.push(url_path(path))
  fields
}
