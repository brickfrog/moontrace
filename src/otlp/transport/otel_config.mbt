///|
/// Build a transport from `OTEL_*` settings. Traces and logs go to
/// `config.traces_endpoint` and `config.logs_endpoint` as full URLs, and
/// `config.headers` are added to the default headers. Create the client with
/// `async_http_client(timeout_ms=config.timeout_ms)` to honor
/// `OTEL_EXPORTER_OTLP_TIMEOUT`.
///
/// The transport currently sends OTLP/HTTP JSON without compression whatever
/// `config.protocol` and `config.compression` say.
pub fn transport_from_otel_config(
  client : &OtlpHttpClient,
  config : @otlp.OtelConfig,
  max_retries~ : Int32 = 3,
  base_backoff_ms~ : Int32 = 1000,
) -> OtlpHttpTransport {
  let headers = default_headers()
  config.headers.each((key, value) => headers.set(key, value))
  transport(
    client,
    "",
    traces_path=config.traces_endpoint,
    logs_path=config.logs_endpoint,
    headers~,
    max_retries~,
    base_backoff_ms~,
  )
}

///|
/// Build a managed exporter from `OTEL_*` settings:
///
/// * `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` sets `batch_size`.
/// * `OTEL_BSP_MAX_QUEUE_SIZE` sets `queue_capacity` in batches (records
///   divided by batch size, rounded up).
/// * `OTEL_BSP_SCHEDULE_DELAY` sets `flush_interval_ms`.
/// * The resource is `config.resource(extra=resource)`.
///
/// Byte limits keep the `managed_json_exporter` defaults unless passed.
pub fn managed_exporter_from_otel_config(
  transport : OtlpHttpTransport,
  config : @otlp.OtelConfig,
  resource~ : @otlp.Resource = { attributes: [], },
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
  max_payload_bytes~ : Int32 = 262144,
  max_pending_bytes~ : Int32 = 1048576,
) -> ManagedJsonExporter {
  let batch_size = managed_positive(config.max_export_batch_size)
  let queue_records = managed_positive(config.max_queue_size)
  managed_json_exporter(
    transport,
    batch_size~,
    queue_capacity=(queue_records + batch_size - 1) / batch_size,
    flush_interval_ms=config.batch_delay_ms,
    resource=config.resource(extra=resource),
    scope~,
    max_payload_bytes~,
    max_pending_bytes~,
  )
}
