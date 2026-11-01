///|
/// A unit of work with timing, fields, status, and trace context.
///
/// `level` is the optional verbosity given at creation. `enabled` is false
/// when that level was filtered out for the creating package; a disabled span
/// keeps its IDs and propagation but emits no enter/exit events and is not
/// delivered to span observers.
pub(all) struct Span {
  name : String
  fields : Array[Field]
  links : Array[SpanLink]
  events : Array[SpanEvent]
  trace_id : String
  span_id : String
  parent_span_id : String
  mut trace_flags : Int32
  mut trace_state : TraceState
  mut kind : SpanKind
  mut start_time : UInt64
  mut end_time : UInt64
  mut active : Bool
  mut status : SpanStatus
  mut status_message : String
  level : Level?
  enabled : Bool
} derive(Debug)

///|
/// Whether a span at `level`, created from `loc`'s package, passes the global
/// and module filters. Spans without a level are always enabled.
fn span_level_enabled(level : Level?, loc : SourceLoc) -> Bool {
  match level {
    None => true
    Some(level) => should_log_module(extract_package(loc), level)
  }
}

///|
/// Create a root span. With `level`, the span is disabled when that level is
/// filtered out for the caller's package; see `Span`. Wrappers should forward
/// their own `loc`.
#callsite(autofill(loc))
pub fn span(
  name : String,
  fields~ : Array[Field] = [],
  kind~ : SpanKind = Internal,
  level? : Level,
  loc~ : SourceLoc,
) -> Span {
  let trace_id = next_trace_id()
  let s = {
    name,
    fields,
    links: [],
    events: [],
    trace_id,
    span_id: next_span_id(),
    parent_span_id: "",
    trace_flags: sampled_trace_flags(trace_id, name, kind, fields),
    trace_state: TraceState::empty(),
    kind,
    start_time: @env.now(),
    end_time: (0 : UInt64),
    active: false,
    status: Unset,
    status_message: "",
    level,
    enabled: span_level_enabled(level, loc),
  }
  notify_span_created(s)
  s
}

///|
/// Create a root span in an existing trace. `level` behaves as for `span`.
#callsite(autofill(loc))
pub fn span_with_trace(
  name : String,
  trace_id : String,
  fields~ : Array[Field] = [],
  kind~ : SpanKind = Internal,
  level? : Level,
  loc~ : SourceLoc,
) -> Span {
  let s = {
    name,
    fields,
    links: [],
    events: [],
    trace_id,
    span_id: next_span_id(),
    parent_span_id: "",
    trace_flags: sampled_trace_flags(trace_id, name, kind, fields),
    trace_state: TraceState::empty(),
    kind,
    start_time: @env.now(),
    end_time: (0 : UInt64),
    active: false,
    status: Unset,
    status_message: "",
    level,
    enabled: span_level_enabled(level, loc),
  }
  notify_span_created(s)
  s
}

///|
/// The span ID a child of `parent` records as its parent: `parent` itself when
/// enabled, otherwise its nearest enabled ancestor, or `""` when there is none.
fn effective_parent_id(parent : Span) -> String {
  if parent.enabled {
    parent.span_id
  } else {
    parent.parent_span_id
  }
}

///|
/// Create a child span in `parent`'s trace. The child follows `parent`'s
/// sampling decision under the default sampler. When `parent` is disabled by
/// its level, the child is parented to `parent`'s nearest enabled ancestor so
/// exported traces never reference a span that was not exported. `level`
/// behaves as for `span`.
#callsite(autofill(loc))
pub fn child_span(
  parent : Span,
  name : String,
  fields~ : Array[Field] = [],
  kind~ : SpanKind = Internal,
  level? : Level,
  loc~ : SourceLoc,
) -> Span {
  let parent_id = effective_parent_id(parent)
  let s = span_with_ids(
    name,
    fields,
    parent.trace_id,
    parent_id,
    kind,
    trace_flags=sampled_trace_flags(
      parent.trace_id,
      name,
      kind,
      fields,
      parent=Some(span_trace_flags(parent)),
    ),
    trace_state=parent.trace_state,
    level~,
    enabled=span_level_enabled(level, loc),
  )
  if !parent_id.is_empty() {
    notify_span_linked(s, {
      trace_id: parent.trace_id,
      span_id: parent_id,
      kind: SpanChildOf,
      fields: [],
      trace_state: "",
    })
  }
  s
}

///|
fn span_with_ids(
  name : String,
  fields : Array[Field],
  trace_id : String,
  parent_span_id : String,
  kind : SpanKind,
  trace_flags~ : Int32 = 0,
  trace_state~ : TraceState = TraceState::empty(),
  level~ : Level? = None,
  enabled~ : Bool = true,
) -> Span {
  let s = span_with_ids_unnotified(
    name,
    fields,
    trace_id,
    parent_span_id,
    kind,
    trace_flags~,
    trace_state~,
    level~,
    enabled~,
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
  trace_flags~ : Int32 = 0,
  trace_state~ : TraceState = TraceState::empty(),
  level~ : Level? = None,
  enabled~ : Bool = true,
) -> Span {
  {
    name,
    fields,
    links: [],
    events: [],
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
    level,
    enabled,
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
  if !self.enabled {
    return
  }
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
  if !self.enabled {
    notify_span_closed(self)
    return
  }
  let duration = self.end_time - self.start_time
  let exit_fields = self.fields.copy()
  exit_fields.push({ key: "duration_ns", value: Json(duration), })
  if self.status != Unset {
    exit_fields.push({ key: "status", value: self.status.to_json(), })
    if !self.status_message.is_empty() {
      exit_fields.push({
        key: "status_message",
        value: Json(self.status_message),
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
  message~ : String? = None,
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
  let field : Field = { key: "error", value: Json(msg), }
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

///|
/// Whether the span passed its level filter when created; see `Span`.
pub fn Span::is_enabled(self : Span) -> Bool {
  self.enabled
}
