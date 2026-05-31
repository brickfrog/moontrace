///|
pub(all) struct Span {
  name : String
  fields : Array[Field]
  trace_id : String
  span_id : String
  parent_span_id : String
  mut trace_flags : Int
  mut trace_state : TraceState
  mut kind : SpanKind
  mut start_time : UInt64
  mut end_time : UInt64
  mut active : Bool
  mut status : SpanStatus
  mut status_message : String
} derive(Debug)

///|
pub fn span(
  name : String,
  fields? : Array[Field] = [],
  kind? : SpanKind = Internal,
) -> Span {
  let s = {
    name,
    fields,
    trace_id: next_trace_id(),
    span_id: next_span_id(),
    parent_span_id: "",
    trace_flags: 0,
    trace_state: TraceState::empty(),
    kind,
    start_time: @env.now(),
    end_time: (0 : UInt64),
    active: false,
    status: Unset,
    status_message: "",
  }
  notify_span_created(s)
  s
}

///|
pub fn span_with_trace(
  name : String,
  trace_id : String,
  fields? : Array[Field] = [],
  kind? : SpanKind = Internal,
) -> Span {
  let s = {
    name,
    fields,
    trace_id,
    span_id: next_span_id(),
    parent_span_id: "",
    trace_flags: 0,
    trace_state: TraceState::empty(),
    kind,
    start_time: @env.now(),
    end_time: (0 : UInt64),
    active: false,
    status: Unset,
    status_message: "",
  }
  notify_span_created(s)
  s
}

///|
pub fn child_span(
  parent : Span,
  name : String,
  fields? : Array[Field] = [],
  kind? : SpanKind = Internal,
) -> Span {
  let s = span_with_ids(
    name,
    fields,
    parent.trace_id,
    parent.span_id,
    kind,
    trace_flags=parent.trace_flags,
    trace_state=parent.trace_state,
  )
  notify_span_linked(s, span_link(parent, kind=SpanChildOf))
  s
}

///|
fn span_with_ids(
  name : String,
  fields : Array[Field],
  trace_id : String,
  parent_span_id : String,
  kind : SpanKind,
  trace_flags? : Int = 0,
  trace_state? : TraceState = TraceState::empty(),
) -> Span {
  let s = span_with_ids_unnotified(
    name,
    fields,
    trace_id,
    parent_span_id,
    kind,
    trace_flags~,
    trace_state~,
  )
  notify_span_created(s)
  s
}

///|
fn span_with_ids_unnotified(
  name : String,
  fields : Array[Field],
  trace_id : String,
  parent_span_id : String,
  kind : SpanKind,
  trace_flags? : Int = 0,
  trace_state? : TraceState = TraceState::empty(),
) -> Span {
  {
    name,
    fields,
    trace_id,
    span_id: next_span_id(),
    parent_span_id,
    trace_flags,
    trace_state: copy_trace_state(trace_state),
    kind,
    start_time: @env.now(),
    end_time: (0 : UInt64),
    active: false,
    status: Unset,
    status_message: "",
  }
}

///|
fn Span::is_closed(self : Span) -> Bool {
  !self.active && self.end_time != (0 : UInt64)
}

///|
pub fn Span::enter(self : Span) -> Unit {
  if self.active || self.is_closed() {
    return
  }
  self.start_time = @env.now()
  self.end_time = (0 : UInt64)
  self.active = true
  notify_span_entered(self)
  let enter_fields = self.fields.copy()
  emit(Trace, "span.enter \{self.name}", enter_fields)
}

///|
pub fn Span::exit(self : Span) -> Unit {
  if !self.active {
    return
  }
  self.end_time = @env.now()
  self.active = false
  notify_span_exited(self)
  let duration = self.end_time - self.start_time
  let exit_fields = self.fields.copy()
  exit_fields.push({ key: "duration_ns", value: duration.to_json() })
  if self.status != Unset {
    exit_fields.push({ key: "status", value: self.status.to_json() })
    if !self.status_message.is_empty() {
      exit_fields.push({
        key: "status_message",
        value: self.status_message.to_json(),
      })
    }
  }
  emit(Trace, "span.exit \{self.name}", exit_fields)
  notify_span_closed(self)
}

///|
pub fn Span::set_status(
  self : Span,
  status : SpanStatus,
  message? : String? = None,
) -> Unit {
  self.status = status
  match message {
    Some(m) => self.status_message = m
    None => if status != SpanError { self.status_message = "" }
  }
}

///|
pub fn Span::record_error(self : Span, msg : String) -> Unit {
  self.status = SpanError
  self.status_message = msg
  let field : Field = { key: "error", value: msg.to_json() }
  self.fields.push(field)
  notify_span_recorded(self, field)
}

///|
pub fn Span::is_active(self : Span) -> Bool {
  self.active
}

///|
pub fn Span::duration(self : Span) -> UInt64 {
  if self.end_time > self.start_time {
    self.end_time - self.start_time
  } else {
    (0 : UInt64)
  }
}
