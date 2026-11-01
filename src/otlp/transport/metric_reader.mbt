///|
/// Counters are per-meter export attempts. A timed-out export also counts as
/// failed.
pub(all) struct MetricReaderStats {
  exports : Int64
  delivered : Int64
  failed : Int64
  timed_out : Int64
  skipped_empty : Int64
  closed : Bool
  running : Bool
} derive(Eq, Debug)

///|
priv struct MetricReaderState {
  mut exports : Int64
  mut delivered : Int64
  mut failed : Int64
  mut timed_out : Int64
  mut skipped_empty : Int64
  mut closing : Bool
  mut closed : Bool
  mut running : Bool
  mut last_report : ExportReport?
  mut last_error : String?
}

///|
/// Collects meters on a fixed interval and exports their cumulative metrics
/// through an `OtlpHttpTransport` (JSON or protobuf, per its encoder). Each
/// meter is one request with the meter as instrumentation scope; meters with
/// no data points are skipped. Exports never overlap. Run its timer with
/// `run` in the caller's task group.
///
/// The reader does not own the transport: `shutdown` leaves it open so it can
/// be shared with a `ManagedJsonExporter`.
pub struct PeriodicMetricReader {
  priv transport : OtlpHttpTransport
  priv meters : Array[@metrics.Meter]
  priv interval_ms : Int32
  priv timeout_ms : Int32
  priv resource : @otlp.Resource
  priv disabled : Bool
  priv export_lock : @aqueue.Queue[Unit]
  priv wake : @aqueue.Queue[Unit]
  priv state : MetricReaderState
}

///|
/// Build a reader for `meters`. `interval_ms` is clamped to at least one;
/// `timeout_ms` bounds each meter's export, and a nonpositive value disables
/// the bound. No tasks are started by construction.
pub fn periodic_metric_reader(
  transport : OtlpHttpTransport,
  meters : Array[@metrics.Meter],
  interval_ms~ : Int32 = 60000,
  timeout_ms~ : Int32 = 30000,
  resource~ : @otlp.Resource = @otlp.default_resource(),
) -> PeriodicMetricReader {
  let export_lock = @aqueue.Queue(kind=@aqueue.Blocking(1))
  ignore(export_lock.try_put(()) catch { _ => false })
  {
    transport,
    meters: meters.copy(),
    interval_ms: managed_positive(interval_ms),
    timeout_ms,
    resource,
    disabled: false,
    export_lock,
    wake: @aqueue.Queue(kind=@aqueue.Blocking(1)),
    state: {
      exports: 0L,
      delivered: 0L,
      failed: 0L,
      timed_out: 0L,
      skipped_empty: 0L,
      closing: false,
      closed: false,
      running: false,
      last_report: None,
      last_error: None,
    },
  }
}

///|
/// Build a reader from `OTEL_*` settings:
///
/// * `OTEL_METRIC_EXPORT_INTERVAL` sets `interval_ms`.
/// * `OTEL_METRIC_EXPORT_TIMEOUT` sets `timeout_ms`.
/// * The resource is `config.resource(extra=resource)`.
/// * With `OTEL_SDK_DISABLED=true`, nothing is exported.
pub fn metric_reader_from_otel_config(
  transport : OtlpHttpTransport,
  meters : Array[@metrics.Meter],
  config : @otlp.OtelConfig,
  resource~ : @otlp.Resource = { attributes: [], },
) -> PeriodicMetricReader {
  let reader = periodic_metric_reader(
    transport,
    meters,
    interval_ms=config.metric_export_interval_ms,
    timeout_ms=config.metric_export_timeout_ms,
    resource=config.resource(extra=resource),
  )
  { ..reader, disabled: config.disabled, }
}

///|
pub fn PeriodicMetricReader::stats(
  self : PeriodicMetricReader,
) -> MetricReaderStats {
  let state = self.state
  {
    exports: state.exports,
    delivered: state.delivered,
    failed: state.failed,
    timed_out: state.timed_out,
    skipped_empty: state.skipped_empty,
    closed: state.closed,
    running: state.running,
  }
}

///|
/// The most recent collector reply, if the last export got one.
pub fn PeriodicMetricReader::last_report(
  self : PeriodicMetricReader,
) -> ExportReport? {
  self.state.last_report
}

///|
/// The most recent export failure.
pub fn PeriodicMetricReader::last_error(self : PeriodicMetricReader) -> String? {
  self.state.last_error
}

///|
async fn PeriodicMetricReader::export_meter(
  self : PeriodicMetricReader,
  meter : @metrics.Meter,
) -> Unit {
  let state = self.state
  let data = meter.collect()
  if data.iter().all(metric => metric.points.is_empty()) {
    state.skipped_empty += 1L
    return
  }
  state.exports += 1L
  let mut settled = false
  defer (if !settled {
    state.failed += 1L
    state.last_report = None
    state.last_error = Some(
      "metric export cancelled or raised; delivery is unknown",
    )
  })
  let partial = Ref(None)
  let send = () => {
    self.transport.export_encoded(
      join_url(self.transport.endpoint, self.transport.metrics_path),
      Metrics,
      self.transport.encoder.encode_metrics(
        data,
        resource=self.resource,
        scope=meter.scope(),
      ),
      value => partial.val = Some(value),
    )
  }
  let result = if self.timeout_ms > 0 {
    @async.with_timeout_opt(self.timeout_ms, send)
  } else {
    Some(send())
  }
  match result {
    None => {
      state.failed += 1L
      state.timed_out += 1L
      state.last_report = None
      state.last_error = Some(
        "metric export timed out after \{self.timeout_ms} ms",
      )
    }
    Some(Ok(outcome)) => {
      let report = { outcome, partial_success: partial.val, }
      state.last_report = Some(report)
      if outcome.success {
        state.delivered += 1L
      } else {
        state.failed += 1L
        state.last_error = Some(
          match outcome.error {
            Some(error) => error.to_string()
            None =>
              match outcome.status_code {
                Some(code) => "OTLP HTTP metric export failed: status=\{code}"
                None => "OTLP HTTP metric export failed"
              }
          },
        )
      }
    }
    Some(Err(error)) => {
      state.failed += 1L
      state.last_report = None
      state.last_error = Some(error.to_string())
    }
  }
  settled = true
}

///|
/// Export every meter once, serialized with other exports.
async fn PeriodicMetricReader::export_all(self : PeriodicMetricReader) -> Unit {
  ignore(self.export_lock.get())
  defer self.unlock()
  if !self.state.closed {
    self.export_meters()
  }
}

///|
fn PeriodicMetricReader::unlock(self : PeriodicMetricReader) -> Unit {
  ignore(self.export_lock.try_put(()) catch { _ => false })
}

///|
async fn PeriodicMetricReader::export_meters(
  self : PeriodicMetricReader,
) -> Unit {
  if self.disabled {
    return
  }
  for meter in self.meters {
    self.export_meter(meter)
  }
}

///|
/// Export every `interval_ms` until `shutdown`. Cancellation propagates; an
/// export cut short counts as failed. Raises if another `run` is active.
pub async fn PeriodicMetricReader::run(self : PeriodicMetricReader) -> Unit {
  let state = self.state
  if state.running {
    raise Failure("metric reader is already running")
  }
  state.running = true
  defer {
    state.running = false
  }
  while !state.closing {
    // `shutdown` wakes the timer so it need not wait out the interval.
    ignore(@async.with_timeout_opt(self.interval_ms, () => self.wake.get()))
    if state.closing {
      break
    }
    self.export_all()
  }
}

///|
/// Collect and export every meter now, after any export in progress. Does not
/// promise delivery; inspect stats and `last_error`. A no-op after shutdown.
pub async fn PeriodicMetricReader::flush(
  self : PeriodicMetricReader,
) -> MetricReaderStats {
  self.export_all()
  self.stats()
}

///|
/// Stop the timer and export every meter a final time. Later calls return
/// the stats without exporting. If a shutdown is cancelled during its final
/// export, a later call retries it. The transport is left open.
pub async fn PeriodicMetricReader::shutdown(
  self : PeriodicMetricReader,
) -> MetricReaderStats {
  let state = self.state
  state.closing = true
  ignore(self.wake.try_put(()) catch { _ => false })
  ignore(self.export_lock.get())
  defer self.unlock()
  if !state.closed {
    self.export_meters()
    state.closed = true
  }
  self.stats()
}
