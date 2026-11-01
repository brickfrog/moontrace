///|
/// OpenTelemetry SDK settings read from `OTEL_*` environment variables by
/// `parse_otel_config`. Unset or invalid variables keep the specification's
/// defaults; invalid ones also add a message to `warnings`.
pub(all) struct OtelConfig {
  /// `OTEL_SDK_DISABLED=true`.
  disabled : Bool
  /// `OTEL_SERVICE_NAME`, which wins over `service.name` in
  /// `OTEL_RESOURCE_ATTRIBUTES`.
  service_name : String?
  /// Parsed `OTEL_RESOURCE_ATTRIBUTES` (`key=value,...`, percent-decoded).
  resource_attributes : Array[OtlpAttribute]
  /// Full traces URL: `OTEL_EXPORTER_OTLP_TRACES_ENDPOINT` as given, or
  /// `OTEL_EXPORTER_OTLP_ENDPOINT` plus `/v1/traces`.
  traces_endpoint : String
  /// Full logs URL, resolved like `traces_endpoint` with `/v1/logs`.
  logs_endpoint : String
  /// Full metrics URL, resolved like `traces_endpoint` with `/v1/metrics`.
  metrics_endpoint : String
  /// Parsed `OTEL_EXPORTER_OTLP_HEADERS` (`key=value,...`, percent-decoded).
  headers : Map[String, String]
  /// `OTEL_EXPORTER_OTLP_TIMEOUT` in milliseconds (default 10000).
  timeout_ms : Int32
  /// `OTEL_EXPORTER_OTLP_PROTOCOL` (default `http/protobuf`).
  protocol : String
  /// `OTEL_EXPORTER_OTLP_COMPRESSION` (default `none`).
  compression : String
  /// `OTEL_TRACES_SAMPLER` (default `parentbased_always_on`).
  sampler : String
  /// `OTEL_TRACES_SAMPLER_ARG` for ratio samplers (default 1.0).
  sampler_ratio : Double
  /// `OTEL_BSP_SCHEDULE_DELAY` in milliseconds (default 5000).
  batch_delay_ms : Int32
  /// `OTEL_BSP_MAX_QUEUE_SIZE` (default 2048).
  max_queue_size : Int32
  /// `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` (default 512).
  max_export_batch_size : Int32
  /// `OTEL_METRIC_EXPORT_INTERVAL` in milliseconds (default 60000).
  metric_export_interval_ms : Int32
  /// `OTEL_METRIC_EXPORT_TIMEOUT` in milliseconds (default 30000).
  metric_export_timeout_ms : Int32
  /// Messages for values that were ignored.
  warnings : Array[String]
}

///|
const DEFAULT_OTLP_ENDPOINT : String = "http://localhost:4318"

///|
/// Parse `OTEL_*` settings using `lookup` to read each variable, so tests and
/// hosts without a process environment can supply values directly. Parsing
/// never fails: an invalid value is ignored, the default is kept, and a message
/// is added to `warnings`. Blank values count as unset.
pub fn parse_otel_config(lookup : (String) -> String?) -> OtelConfig {
  let warnings : Array[String] = []
  let read = name => {
    match lookup(name) {
      Some(value) => {
        let trimmed = value.trim().to_owned()
        if trimmed.is_empty() {
          None
        } else {
          Some(trimmed)
        }
      }
      None => None
    }
  }
  let disabled = match read("OTEL_SDK_DISABLED") {
    Some(value) =>
      match value.to_lower() {
        "true" => true
        "false" => false
        _ => {
          warnings.push("OTEL_SDK_DISABLED: expected true or false")
          false
        }
      }
    None => false
  }
  let resource_attributes = match read("OTEL_RESOURCE_ATTRIBUTES") {
    Some(value) =>
      match parse_key_value_list(value) {
        Some(pairs) =>
          pairs.map(pair => OtlpAttribute::{
            key: pair.0,
            value: StringVal(pair.1),
          })
        None => {
          warnings.push(
            "OTEL_RESOURCE_ATTRIBUTES: expected percent-encoded key=value pairs separated by commas",
          )
          []
        }
      }
    None => []
  }
  let headers : Map[String, String] = Map([])
  match read("OTEL_EXPORTER_OTLP_HEADERS") {
    Some(value) =>
      match parse_key_value_list(value) {
        Some(pairs) => pairs.each(pair => headers.set(pair.0, pair.1))
        None =>
          warnings.push(
            "OTEL_EXPORTER_OTLP_HEADERS: expected percent-encoded key=value pairs separated by commas",
          )
      }
    None => ()
  }
  let base_endpoint = read("OTEL_EXPORTER_OTLP_ENDPOINT").unwrap_or(
    DEFAULT_OTLP_ENDPOINT,
  )
  let signal_endpoint = (name, path) => {
    match read(name) {
      Some(url) => url
      None => append_signal_path(base_endpoint, path)
    }
  }
  let non_negative_int = (name, default) => {
    match read(name) {
      Some(value) =>
        match parse_non_negative_int(value) {
          Some(n) => n
          None => {
            warnings.push("\{name}: expected a non-negative integer")
            default
          }
        }
      None => default
    }
  }
  let protocol = match read("OTEL_EXPORTER_OTLP_PROTOCOL") {
    Some(value) =>
      match value {
        "http/json" | "http/protobuf" => value
        "grpc" => {
          warnings.push(
            "OTEL_EXPORTER_OTLP_PROTOCOL: grpc is not supported; using http/protobuf",
          )
          "http/protobuf"
        }
        _ => {
          warnings.push(
            "OTEL_EXPORTER_OTLP_PROTOCOL: expected http/json or http/protobuf",
          )
          "http/protobuf"
        }
      }
    None => "http/protobuf"
  }
  let compression = match read("OTEL_EXPORTER_OTLP_COMPRESSION") {
    Some(value) =>
      match value.to_lower() {
        "none" | "gzip" => value.to_lower()
        _ => {
          warnings.push("OTEL_EXPORTER_OTLP_COMPRESSION: expected none or gzip")
          "none"
        }
      }
    None => "none"
  }
  let sampler = match read("OTEL_TRACES_SAMPLER") {
    Some(value) =>
      match value {
        "always_on"
        | "always_off"
        | "traceidratio"
        | "parentbased_always_on"
        | "parentbased_always_off"
        | "parentbased_traceidratio" => value
        _ => {
          warnings.push(
            "OTEL_TRACES_SAMPLER: unsupported sampler \{value}; using parentbased_always_on",
          )
          "parentbased_always_on"
        }
      }
    None => "parentbased_always_on"
  }
  let sampler_ratio = match read("OTEL_TRACES_SAMPLER_ARG") {
    Some(value) =>
      match parse_ratio(value) {
        Some(ratio) => ratio
        None => {
          warnings.push(
            "OTEL_TRACES_SAMPLER_ARG: expected a number between 0 and 1",
          )
          1.0
        }
      }
    None => 1.0
  }
  {
    disabled,
    service_name: read("OTEL_SERVICE_NAME"),
    resource_attributes,
    traces_endpoint: signal_endpoint(
      "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT", "/v1/traces",
    ),
    logs_endpoint: signal_endpoint(
      "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT", "/v1/logs",
    ),
    metrics_endpoint: signal_endpoint(
      "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT", "/v1/metrics",
    ),
    headers,
    timeout_ms: non_negative_int("OTEL_EXPORTER_OTLP_TIMEOUT", 10000),
    protocol,
    compression,
    sampler,
    sampler_ratio,
    batch_delay_ms: non_negative_int("OTEL_BSP_SCHEDULE_DELAY", 5000),
    max_queue_size: non_negative_int("OTEL_BSP_MAX_QUEUE_SIZE", 2048),
    max_export_batch_size: non_negative_int(
      "OTEL_BSP_MAX_EXPORT_BATCH_SIZE", 512,
    ),
    metric_export_interval_ms: non_negative_int(
      "OTEL_METRIC_EXPORT_INTERVAL", 60000,
    ),
    metric_export_timeout_ms: non_negative_int(
      "OTEL_METRIC_EXPORT_TIMEOUT", 30000,
    ),
    warnings,
  }
}

///|
/// Parse `OTEL_*` settings from the process environment. On targets without
/// environment access every variable reads as unset, giving the defaults.
pub fn otel_config_from_env() -> OtelConfig {
  parse_otel_config(@env.get_env_var)
}

///|
/// The configured resource: `default_resource()`, then
/// `OTEL_RESOURCE_ATTRIBUTES`, then `OTEL_SERVICE_NAME`, with later sources
/// winning. `extra` is merged last, so code can still override the
/// environment.
pub fn OtelConfig::resource(
  self : OtelConfig,
  extra~ : Resource = { attributes: [], },
) -> Resource {
  let configured = default_resource().merge({
    attributes: self.resource_attributes,
  })
  let named = match self.service_name {
    Some(name) =>
      configured.merge({
        attributes: [{ key: "service.name", value: StringVal(name), }],
      })
    None => configured
  }
  named.merge(extra)
}

///|
/// The span sampler named by `OTEL_TRACES_SAMPLER` and
/// `OTEL_TRACES_SAMPLER_ARG`, or `always_off_sampler()` when the SDK is
/// disabled.
pub fn OtelConfig::span_sampler(self : OtelConfig) -> @moontrace.SpanSampler {
  if self.disabled {
    return @moontrace.always_off_sampler()
  }
  match self.sampler {
    "always_on" => @moontrace.always_on_sampler()
    "always_off" => @moontrace.always_off_sampler()
    "traceidratio" => @moontrace.trace_id_ratio_sampler(self.sampler_ratio)
    "parentbased_always_off" =>
      @moontrace.parent_based_sampler(@moontrace.always_off_sampler())
    "parentbased_traceidratio" =>
      @moontrace.parent_based_sampler(
        @moontrace.trace_id_ratio_sampler(self.sampler_ratio),
      )
    _ => @moontrace.parent_based_sampler(@moontrace.always_on_sampler())
  }
}

///|
fn append_signal_path(endpoint : String, path : String) -> String {
  if endpoint.has_suffix("/") {
    endpoint + path[1:].to_owned()
  } else {
    endpoint + path
  }
}

///|
fn parse_non_negative_int(value : String) -> Int32? {
  if value.iter().any(ch => ch < '0' || ch > '9') {
    return None
  }
  Some(@string.parse_int(value)) catch {
    _ => None
  }
}

///|
fn parse_ratio(value : String) -> Double? {
  let ratio = @string.parse_double(value) catch { _ => return None }
  if ratio >= 0.0 && ratio <= 1.0 {
    Some(ratio)
  } else {
    None
  }
}

///|
/// Parse the W3C Baggage-style `key=value,key2=value2` list used by
/// `OTEL_RESOURCE_ATTRIBUTES` and `OTEL_EXPORTER_OTLP_HEADERS`. Whitespace
/// around entries is ignored and values are percent-decoded. Returns `None`
/// if any entry is malformed, so the whole variable is discarded.
fn parse_key_value_list(value : String) -> Array[(String, String)]? {
  let pairs : Array[(String, String)] = []
  for entry in value.split(",") {
    let entry = entry.trim()
    if entry.is_empty() {
      continue
    }
    match entry.split_once("=") {
      Some((key, raw)) => {
        let key = key.trim().to_owned()
        if key.is_empty() {
          return None
        }
        match percent_decode(raw.trim().to_owned()) {
          Some(decoded) => pairs.push((key, decoded))
          None => return None
        }
      }
      None => return None
    }
  }
  Some(pairs)
}

///|
fn hex_value(ch : Char) -> Int32? {
  match ch {
    '0'..<='9' => Some(ch.to_int() - '0'.to_int())
    'a'..<='f' => Some(ch.to_int() - 'a'.to_int() + 10)
    'A'..<='F' => Some(ch.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
/// Decode `%XX` escapes as UTF-8 bytes. Returns `None` for truncated or
/// non-hex escapes and for byte sequences that are not valid UTF-8.
fn percent_decode(value : String) -> String? {
  if !value.contains("%") {
    return Some(value)
  }
  let bytes : Array[Byte] = []
  let chars = value.to_array()
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '%' {
      if i + 2 >= chars.length() {
        return None
      }
      match (hex_value(chars[i + 1]), hex_value(chars[i + 2])) {
        (Some(high), Some(low)) => bytes.push((high * 16 + low).to_byte())
        _ => return None
      }
      i = i + 3
    } else {
      for byte in @utf8.encode(ch.to_string()) {
        bytes.push(byte)
      }
      i = i + 1
    }
  }
  Some(@utf8.decode(Bytes::from_array(bytes[:]))) catch {
    _ => None
  }
}
