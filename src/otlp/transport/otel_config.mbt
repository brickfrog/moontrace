///|
/// Build a transport from `OTEL_*` settings. Traces and logs go to
/// `config.traces_endpoint` and `config.logs_endpoint` as full URLs, and
/// `config.headers` are added to the default headers. Create the client with
/// `async_http_client(timeout_ms=config.timeout_ms)` to honor
/// `OTEL_EXPORTER_OTLP_TIMEOUT`.
///
/// `config.protocol` selects the encoder for `export_spans` and `export_logs`
/// (`http/protobuf` by default, as the specification requires) and
/// `config.compression` selects gzip. The managed exporter always sends JSON
/// but uses the configured compression.
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
    encoder=if config.protocol == "http/json" {
      JsonEncoder
    } else {
      ProtobufEncoder
    },
    compression=if config.compression == "gzip" {
      GzipCompression
    } else {
      NoCompression
    },
  )
}

///|
/// Build a managed exporter from `OTEL_*` settings:
///
/// * `OTEL_BSP_MAX_QUEUE_SIZE` caps the records held in queued and in-flight
///   batches (`max_queue_records`).
/// * `OTEL_BSP_MAX_EXPORT_BATCH_SIZE` sets `batch_size`, limited to the queue
///   size as the specification requires.
/// * `OTEL_BSP_SCHEDULE_DELAY` sets `flush_interval_ms`.
/// * The resource is `config.resource(extra=resource)`.
/// * With `OTEL_SDK_DISABLED=true`, the exporter's subscriber and span observer
///   accept nothing, so nothing is exported.
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
  let queue_records = managed_positive(config.max_queue_size)
  let batch_size = managed_positive(config.max_export_batch_size)
  let batch_size = if batch_size > queue_records {
    queue_records
  } else {
    batch_size
  }
  let exporter = managed_json_exporter(
    transport,
    batch_size~,
    queue_capacity=queue_records,
    max_queue_records=queue_records,
    flush_interval_ms=config.batch_delay_ms,
    resource=config.resource(extra=resource),
    scope~,
    max_payload_bytes~,
    max_pending_bytes~,
  )
  { ..exporter, disabled: config.disabled, }
}
