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
pub fn span_to_otlp(
  span : @moontrace.Span,
  trace_id? : String = "",
  parent_span_id? : String = "",
  status_code? : Int = 1,
  status_message? : String = "",
) -> OtlpSpan {
  let tid = if trace_id.is_empty() { span.trace_id } else { trace_id }
  let sid = span.span_id
  let psid = if parent_span_id.is_empty() {
    span.parent_span_id
  } else {
    parent_span_id
  }
  {
    trace_id: tid,
    span_id: sid,
    parent_span_id: psid,
    name: span.name,
    kind: 1, // INTERNAL
    start_time_unix_nano: span.start_time,
    end_time_unix_nano: span.end_time,
    attributes: span.fields.map(fn(f) { field_to_attribute(f) }),
    status_code,
    status_message,
  }
}
