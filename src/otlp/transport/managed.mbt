///|
/// Counters are batches except dropped_records and the buffer/payload gauges.
/// pending_* includes queued and in-flight batches. Partial rejection is a failed
/// batch; a zero-rejection collector warning is a delivered batch.
pub(all) struct ManagedExportStats {
  enqueued_batches : Int64
  delivered_batches : Int64
  failed_batches : Int64
  dropped_batches : Int64
  dropped_records : Int64
  pending_batches : Int32
  pending_bytes : Int32
  buffered_logs : Int32
  buffered_spans : Int32
  closing : Bool
  closed : Bool
  worker_running : Bool
} derive(Eq, Debug)

///|
priv struct ManagedBatch {
  logs : Bool
  payload : String
  bytes : Int32
}

///|
priv struct ManagedState {
  queue : @aqueue.Queue[ManagedBatch]
  capacity : Int32
  max_pending_bytes : Int32
  max_payload_bytes : Int32
  mut log_bytes : Int32
  mut span_bytes : Int32
  mut log_count : Int32
  mut span_count : Int32
  mut enqueued : Int64
  mut completed : Int64
  mut delivered : Int64
  mut failed : Int64
  mut dropped : Int64
  mut dropped_records : Int64
  mut pending_batches : Int32
  mut pending_bytes : Int32
  mut closing : Bool
  mut closed : Bool
  mut worker_running : Bool
  mut draining : Bool
  mut last_report : ExportReport?
  mut last_error : String?
}

///|
/// A single-event-loop JSON exporter. Run its worker in the caller's task group.
/// The transport is exclusively owned for lifecycle purposes; shutdown closes it
/// after draining, but the caller remains responsible for the HTTP client's lifetime.
pub struct ManagedJsonExporter {
  priv transport : OtlpHttpTransport
  priv batcher : @otlp.OtlpExporter
  priv state : ManagedState
  priv lifecycle_lock : @aqueue.Queue[Unit]
  priv interval_ms : Int32
  priv log_overhead : Int32
  priv span_overhead : Int32
}

///|
fn managed_positive(value : Int32) -> Int32 {
  if value < 1 {
    1
  } else {
    value
  }
}

///|
fn managed_bytes(value : String) -> Int32 {
  @utf8.encode(value).length()
}

///|
/// Bounds cover serialized queued/in-flight payloads plus one partial batch per
/// signal, each capped by max_payload_bytes. Serialization uses transient memory.
/// Nonpositive settings clamp to one; max_payload_bytes also clamps to the total
/// pending-byte budget. No tasks are started by construction or logging.
pub fn managed_json_exporter(
  transport : OtlpHttpTransport,
  batch_size~ : Int32 = 64,
  queue_capacity~ : Int32 = 64,
  max_payload_bytes~ : Int32 = 262144,
  max_pending_bytes~ : Int32 = 1048576,
  flush_interval_ms~ : Int32 = 1000,
  resource~ : @otlp.Resource = @otlp.resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> ManagedJsonExporter {
  let capacity = managed_positive(queue_capacity)
  let budget = managed_positive(max_pending_bytes)
  let payload_limit = managed_positive(max_payload_bytes)
  let state : ManagedState = {
    queue: @aqueue.Queue(kind=@aqueue.Blocking(capacity)),
    capacity,
    max_pending_bytes: budget,
    max_payload_bytes: if payload_limit > budget {
      budget
    } else {
      payload_limit
    },
    log_bytes: 0,
    span_bytes: 0,
    log_count: 0,
    span_count: 0,
    enqueued: 0L,
    completed: 0L,
    delivered: 0L,
    failed: 0L,
    dropped: 0L,
    dropped_records: 0L,
    pending_batches: 0,
    pending_bytes: 0,
    closing: false,
    closed: false,
    worker_running: false,
    draining: false,
    last_report: None,
    last_error: None,
  }
  let batcher = @otlp.exporter(
    log_output=payload => state.offer(true, payload),
    span_output=payload => state.offer(false, payload),
    capacity=batch_size,
    resource~,
    scope~,
  )
  let lock : @aqueue.Queue[Unit] = @aqueue.Queue(kind=@aqueue.Blocking(1))
  ignore(lock.try_put(()) catch { _ => false })
  {
    transport,
    batcher,
    state,
    lifecycle_lock: lock,
    interval_ms: managed_positive(flush_interval_ms),
    log_overhead: managed_bytes(
      @otlp.wrap_log_records([], resource=batcher.resource, scope=batcher.scope).stringify(),
    ),
    span_overhead: managed_bytes(
      @otlp.wrap_spans([], resource=batcher.resource, scope=batcher.scope).stringify(),
    ),
  }
}

///|
fn ManagedState::offer(
  self : ManagedState,
  logs : Bool,
  payload : String,
) -> Unit {
  let records = if logs { self.log_count } else { self.span_count }
  if logs {
    self.log_count = 0
    self.log_bytes = 0
  } else {
    self.span_count = 0
    self.span_bytes = 0
  }
  let bytes = managed_bytes(payload)
  if self.closed ||
    self.pending_batches >= self.capacity ||
    bytes > self.max_payload_bytes ||
    bytes > self.max_pending_bytes - self.pending_bytes {
    self.dropped += 1L
    self.dropped_records += records.to_int64()
    return
  }
  let accepted = self.queue.try_put({ logs, payload, bytes, }) catch {
    _ => false
  }
  if accepted {
    self.enqueued += 1L
    self.pending_batches += 1
    self.pending_bytes += bytes
  } else {
    self.dropped += 1L
    self.dropped_records += records.to_int64()
  }
}

///|
pub fn ManagedJsonExporter::subscriber(
  self : ManagedJsonExporter,
) -> (@moontrace.Event) -> Unit {
  event => {
    let state = self.state
    if state.closing {
      state.dropped_records += 1L
      return
    }
    let record = @otlp.event_to_log_record(event)
    let size = managed_bytes(record.to_json().stringify())
    let room = state.max_payload_bytes - self.log_overhead
    if size > room {
      state.dropped_records += 1L
      return
    }
    let separator = if state.log_count == 0 { 0 } else { 1 }
    if state.log_bytes > room - size - separator {
      self.batcher.flush_logs()
    }
    state.log_bytes += size + (if state.log_count == 0 { 0 } else { 1 })
    state.log_count += 1
    self.batcher.log_records.push(record)
    if state.log_count >= self.batcher.capacity {
      self.batcher.flush_logs()
    }
  }
}

///|
pub fn ManagedJsonExporter::span_observer(
  self : ManagedJsonExporter,
) -> @moontrace.SpanLifecycleObserver {
  @moontrace.completed_span_observer(span => {
    let state = self.state
    if state.closing {
      state.dropped_records += 1L
      return
    }
    let converted = @otlp.span_to_otlp(span)
    let size = managed_bytes(converted.to_json().stringify())
    let room = state.max_payload_bytes - self.span_overhead
    if size > room {
      state.dropped_records += 1L
      return
    }
    let separator = if state.span_count == 0 { 0 } else { 1 }
    if state.span_bytes > room - size - separator {
      self.batcher.flush_spans()
    }
    state.span_bytes += size + (if state.span_count == 0 { 0 } else { 1 })
    state.span_count += 1
    self.batcher.add_span(converted)
  })
}

///|
pub fn ManagedJsonExporter::stats(
  self : ManagedJsonExporter,
) -> ManagedExportStats {
  let s = self.state
  {
    enqueued_batches: s.enqueued,
    delivered_batches: s.delivered,
    failed_batches: s.failed,
    dropped_batches: s.dropped,
    dropped_records: s.dropped_records,
    pending_batches: s.pending_batches,
    pending_bytes: s.pending_bytes,
    buffered_logs: s.log_count,
    buffered_spans: s.span_count,
    closing: s.closing,
    closed: s.closed,
    worker_running: s.worker_running,
  }
}

///|
/// Most recent completed transport report; failures/cancellation without a report clear it.
pub fn ManagedJsonExporter::last_report(
  self : ManagedJsonExporter,
) -> ExportReport? {
  self.state.last_report
}

///|
/// Most recent failed attempt at batch delivery, retained until another failure.
pub fn ManagedJsonExporter::last_error(self : ManagedJsonExporter) -> String? {
  self.state.last_error
}

///|
async fn ManagedJsonExporter::send(
  self : ManagedJsonExporter,
  batch : ManagedBatch,
) -> Unit {
  let state = self.state
  let mut settled = false
  defer {
    state.pending_batches -= 1
    state.pending_bytes -= batch.bytes
    state.completed += 1L
    if !settled {
      state.failed += 1L
      state.last_report = None
      state.last_error = Some(
        "export task cancelled or raised; in-flight delivery is unknown",
      )
    }
  }
  let path = if batch.logs {
    self.transport.logs_path
  } else {
    self.transport.traces_path
  }
  match
    self.transport.export_json_report(
      join_url(self.transport.endpoint, path),
      batch.payload,
    ) {
    Ok(report) => {
      state.last_report = Some(report)
      if report.outcome.success {
        state.delivered += 1L
      } else {
        state.failed += 1L
        state.last_error = Some(
          match report.outcome.error {
            Some(error) => error.to_string()
            None =>
              "OTLP HTTP export failed: status=\{report.outcome.status_code}"
          },
        )
      }
    }
    Err(error) => {
      state.failed += 1L
      state.last_report = None
      state.last_error = Some(error.to_string())
    }
  }
  settled = true
}

///|
/// Run one sender plus a timer scoped to this task. Cancellation propagates;
/// in-flight work is counted failed (delivery unknown) and is not replayed.
/// Unsent queues/buffers remain available to a later run, flush, or shutdown.
pub async fn ManagedJsonExporter::run(self : ManagedJsonExporter) -> Unit {
  let state = self.state
  // A flush/shutdown may begin driving before a just-spawned worker starts.
  // Wait for that sender to relinquish ownership rather than failing the group.
  while state.draining {
    @async.sleep(1)
  }
  if state.worker_running {
    raise Failure("managed exporter already has a sender")
  }
  if state.closed {
    return
  }
  state.worker_running = true
  defer {
    state.worker_running = false
  }
  @async.with_task_group(group => {
    group.spawn_bg(no_wait=true, () => {
      while !state.closing {
        @async.sleep(self.interval_ms)
        if !state.closing {
          self.batcher.flush()
        }
      }
    })
    while true {
      let batch = state.queue.get() catch {
        @aqueue.QueueAlreadyClosed => return
        error => raise error
      }
      self.send(batch)
      @async.pause()
    }
  })
}

///|
async fn ManagedJsonExporter::wait_until(
  self : ManagedJsonExporter,
  target : Int64,
) -> Unit {
  let state = self.state
  while state.completed < target {
    if state.worker_running || state.draining {
      @async.sleep(1)
    } else {
      state.draining = true
      defer {
        state.draining = false
      }
      while state.completed < target {
        let batch = state.queue.try_get() catch { error => raise error }
        match batch {
          Some(batch) => self.send(batch)
          None => raise Failure("managed exporter lost an accepted batch")
        }
        @async.pause()
      }
    }
  }
}

///|
fn ManagedJsonExporter::unlock(self : ManagedJsonExporter) -> Unit {
  ignore(self.lifecycle_lock.try_put(()) catch { _ => false })
}

///|
/// Flush partial batches with normal drop-new admission, then wait for all batches
/// accepted before this barrier to reach terminal outcomes. Does not promise
/// delivery; inspect stats/last_report. Without run(), the caller drives sending.
pub async fn ManagedJsonExporter::flush(
  self : ManagedJsonExporter,
) -> ManagedExportStats {
  ignore(self.lifecycle_lock.get())
  defer self.unlock()
  if self.state.closing && !self.state.closed {
    raise Failure(
      "managed exporter shutdown is incomplete; call shutdown to resume",
    )
  }
  if !self.state.closing {
    self.batcher.flush()
  }
  let target = self.state.enqueued
  self.wait_until(target)
  self.stats()
}

///|
/// Close intake, drain accepted work, then flush each final partial batch with
/// room reserved by draining first. Close the transport only after the worker
/// and its timer terminate. Cancellation leaves closing=true; call shutdown again
/// from an uncancelled task to finish. This never owns/shuts down the HTTP client.
pub async fn ManagedJsonExporter::shutdown(
  self : ManagedJsonExporter,
) -> ManagedExportStats {
  let state = self.state
  state.closing = true
  ignore(self.lifecycle_lock.get())
  defer self.unlock()
  if !state.closed {
    self.wait_until(state.enqueued)
    self.batcher.flush_logs()
    self.wait_until(state.enqueued)
    self.batcher.flush_spans()
    self.wait_until(state.enqueued)
    self.batcher.shutdown()
    state.queue.close()
  }
  while state.worker_running {
    @async.sleep(1)
  }
  self.transport.shutdown()
  state.closed = true
  self.stats()
}
