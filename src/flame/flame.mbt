///|
pub(all) struct FlameExporter {
  mut spans : Array[@moontrace.Span]
  output : (String) -> Unit
}

///|
pub fn flame_exporter(
  output? : (String) -> Unit = fn(s) { println(s) },
) -> FlameExporter {
  { spans: [], output }
}

///|
pub fn FlameExporter::span_observer(
  self : FlameExporter,
) -> @moontrace.SpanLifecycleObserver {
  @moontrace.completed_span_observer(fn(span) { self.spans.push(span) })
}

///|
pub fn FlameExporter::flush(self : FlameExporter) -> Unit {
  let folded = fold_spans(self.spans)
  self.spans = []
  (self.output)(folded)
}

///|
pub fn FlameExporter::reset(self : FlameExporter) -> Unit {
  self.spans = []
}

///|
pub fn fold_spans(spans : Array[@moontrace.Span]) -> String {
  let spans_by_id : Map[String, @moontrace.Span] = {}
  spans.each(fn(span) {
    spans_by_id.set(span_key(span.trace_id, span.span_id), span)
  })
  let direct_child_duration_by_parent : Map[String, UInt64] = {}
  spans.each(fn(span) {
    let parent = span_key(span.trace_id, span.parent_span_id)
    if valid_parent_edge(span, spans_by_id, spans.length()) {
      add_weight(direct_child_duration_by_parent, parent, span.duration())
    }
  })
  let folded_weights : Map[String, UInt64] = {}
  spans.each(fn(span) {
    let child_duration = direct_child_duration_by_parent.get_or_default(
      span_key(span.trace_id, span.span_id),
      (0 : UInt64),
    )
    let duration = span.duration()
    let self_time = if duration > child_duration {
      duration - child_duration
    } else {
      (0 : UInt64)
    }
    if self_time > (0 : UInt64) {
      add_weight(
        folded_weights,
        stack_string(span, spans_by_id, spans.length()),
        self_time,
      )
    }
  })
  let lines : Array[String] = []
  folded_weights.each(fn(stack, value) { lines.push("\{stack} \{value}") })
  lines.sort_by(fn(a, b) { a.lexical_compare(b) })
  lines.join("\n")
}

///|
fn add_weight(
  weights : Map[String, UInt64],
  key : String,
  value : UInt64,
) -> Unit {
  weights.set(key, weights.get_or_default(key, (0 : UInt64)) + value)
}

///|
fn stack_string(
  span : @moontrace.Span,
  spans_by_id : Map[String, @moontrace.Span],
  span_count : Int,
) -> String {
  let frames : Array[String] = []
  let mut current = Some(span)
  let mut remaining = span_count
  while remaining > 0 {
    match current {
      Some(s) => {
        frames.push(sanitize_frame_name(s.name))
        remaining = remaining - 1
        current = if s.parent_span_id.is_empty() {
          None
        } else if !valid_parent_edge(s, spans_by_id, span_count) {
          None
        } else {
          spans_by_id.get(span_key(s.trace_id, s.parent_span_id))
        }
      }
      None => remaining = 0
    }
  }
  frames.rev().join(";")
}

///|
fn span_key(trace_id : String, span_id : String) -> String {
  trace_id + "|" + span_id
}

///|
fn valid_parent_edge(
  span : @moontrace.Span,
  spans_by_id : Map[String, @moontrace.Span],
  span_count : Int,
) -> Bool {
  if span.parent_span_id.is_empty() {
    return false
  }
  let origin = span_key(span.trace_id, span.span_id)
  let parent = span_key(span.trace_id, span.parent_span_id)
  if parent == origin {
    return false
  }
  let mut current = match spans_by_id.get(parent) {
    Some(parent_span) => Some(parent_span)
    None => return false
  }
  let visited : Map[String, Bool] = {}
  let mut remaining = span_count
  while remaining > 0 {
    match current {
      Some(s) => {
        let key = span_key(s.trace_id, s.span_id)
        if key == origin {
          return false
        }
        if visited.contains(key) {
          return true
        }
        visited.set(key, true)
        remaining = remaining - 1
        if s.parent_span_id.is_empty() {
          return true
        }
        match spans_by_id.get(span_key(s.trace_id, s.parent_span_id)) {
          Some(parent_span) => current = Some(parent_span)
          None => return true
        }
      }
      None => return true
    }
  }
  true
}

///|
fn sanitize_frame_name(name : String) -> String {
  let buf = StringBuilder()
  name
  .iter()
  .each(fn(ch) {
    if ch == ';' || ch.is_ascii_whitespace() {
      buf.write_char('_')
    } else {
      buf.write_char(ch)
    }
  })
  buf.to_string()
}
