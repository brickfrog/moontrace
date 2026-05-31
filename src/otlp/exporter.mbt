// Batching OTLP exporter that collects events and flushes as OTLP JSON

///|
pub(all) struct OtlpExporter {
  mut log_records : Array[OtlpLogRecord]
  mut spans : Array[OtlpSpan]
  log_output : (String) -> Unit
  span_output : (String) -> Unit
  capacity : Int
}

///|
pub fn exporter(
  log_output? : (String) -> Unit = fn(s) { println(s) },
  span_output? : (String) -> Unit = fn(s) { println(s) },
  capacity? : Int = 10,
) -> OtlpExporter {
  let cap = if capacity < 1 { 1 } else { capacity }
  { log_records: [], spans: [], log_output, span_output, capacity: cap }
}

///|
pub fn OtlpExporter::subscriber(
  self : OtlpExporter,
) -> (@moontrace.Event) -> Unit {
  fn(event) {
    let record = event_to_log_record(event)
    self.log_records.push(record)
    if self.log_records.length() >= self.capacity {
      self.flush_logs()
    }
  }
}

///|
pub fn OtlpExporter::span_observer(
  self : OtlpExporter,
) -> @moontrace.SpanLifecycleObserver {
  @moontrace.completed_span_observer(fn(span) {
    self.add_span(span_to_otlp(span))
  })
}

///|
pub fn OtlpExporter::add_span(self : OtlpExporter, span : OtlpSpan) -> Unit {
  self.spans.push(span)
  if self.spans.length() >= self.capacity {
    self.flush_spans()
  }
}

///|
pub fn OtlpExporter::flush_logs(self : OtlpExporter) -> Unit {
  if self.log_records.is_empty() {
    return
  }
  let to_flush = self.log_records
  self.log_records = []
  let json = wrap_log_records(to_flush)
  (self.log_output)(json.stringify())
}

///|
pub fn OtlpExporter::flush_spans(self : OtlpExporter) -> Unit {
  if self.spans.is_empty() {
    return
  }
  let to_flush = self.spans
  self.spans = []
  let json = wrap_spans(to_flush)
  (self.span_output)(json.stringify())
}

///|
pub fn OtlpExporter::flush(self : OtlpExporter) -> Unit {
  self.flush_logs()
  self.flush_spans()
}

// Helper: create an OtlpSpan from a completed moontrace Span

///|
pub fn span_to_otlp(span : @moontrace.Span) -> OtlpSpan {
  let status_code = match span.status {
    Unset => 0
    Ok => 1
    SpanError => 2
  }
  {
    trace_id: span.trace_id,
    span_id: span.span_id,
    parent_span_id: span.parent_span_id,
    flags: @moontrace.span_trace_flags(span).to_int(),
    name: span.name,
    kind: span.kind.to_int(),
    start_time_unix_nano: span.start_time,
    end_time_unix_nano: span.end_time,
    attributes: span.fields.map(fn(f) { field_to_attribute(f) }),
    status_code,
    status_message: span.status_message,
  }
}
