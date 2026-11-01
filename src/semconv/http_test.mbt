///|
test "HTTP semantic-convention helpers use OpenTelemetry keys" {
  let fields = @semconv.http_server_request(
    "GET",
    "/users/42",
    route="/users/{id}",
  )
  fields.push(@semconv.http_response_status_code(200))
  fields.push(@semconv.url_scheme("https"))
  fields.push(@semconv.url_full("https://example.com/users/42"))
  fields.push(@semconv.server_address("example.com"))
  fields.push(@semconv.user_agent_original("curl/8"))
  assert_eq(
    @moontrace.fields_to_json(fields).stringify(),
    "{\"http.request.method\":\"GET\",\"http.route\":\"/users/{id}\",\"url.path\":\"/users/42\",\"http.response.status_code\":200,\"url.scheme\":\"https\",\"url.full\":\"https://example.com/users/42\",\"server.address\":\"example.com\",\"user_agent.original\":\"curl/8\"}",
  )
  assert_eq(@semconv.http_server_request("POST", "/login").map(f => f.key), [
    "http.request.method", "url.path",
  ])
}
