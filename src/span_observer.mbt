///|
pub(all) enum SpanLinkKind {
  SpanLinked
  SpanFollowsFrom
  SpanChildOf
} derive(Eq, Compare, Debug)

///|
pub(all) struct SpanLink {
  trace_id : String
  span_id : String
  kind : SpanLinkKind
  fields : Array[Field]
} derive(Debug)

///|
pub(all) struct SpanLifecycleObserver {
  on_created : (Span) -> Unit
  on_entered : (Span) -> Unit
  on_recorded : (Span, Field) -> Unit
  on_exited : (Span) -> Unit
  on_closed : (Span) -> Unit
  on_linked : (Span, SpanLink) -> Unit
}

///|
let global_span_observer : Ref[SpanLifecycleObserver?] = { val: None }

///|
fn span_snapshot(span : Span) -> Span {
  {
    name: span.name,
    fields: span.fields.copy(),
    trace_id: span.trace_id,
    span_id: span.span_id,
    parent_span_id: span.parent_span_id,
    kind: span.kind,
    start_time: span.start_time,
    end_time: span.end_time,
    active: span.active,
    status: span.status,
    status_message: span.status_message,
  }
}

///|
fn link_snapshot(link : SpanLink) -> SpanLink {
  {
    trace_id: link.trace_id,
    span_id: link.span_id,
    kind: link.kind,
    fields: link.fields.copy(),
  }
}

///|
pub fn span_lifecycle_observer(
  on_created? : (Span) -> Unit = fn(_span : Span) {  },
  on_entered? : (Span) -> Unit = fn(_span : Span) {  },
  on_recorded? : (Span, Field) -> Unit = fn(_span : Span, _field : Field) {  },
  on_exited? : (Span) -> Unit = fn(_span : Span) {  },
  on_closed? : (Span) -> Unit = fn(_span : Span) {  },
  on_linked? : (Span, SpanLink) -> Unit = fn(_span : Span, _link : SpanLink) {

  },
) -> SpanLifecycleObserver {
  { on_created, on_entered, on_recorded, on_exited, on_closed, on_linked }
}

///|
pub fn completed_span_observer(
  on_completed : (Span) -> Unit,
) -> SpanLifecycleObserver {
  span_lifecycle_observer(on_closed=on_completed)
}

///|
pub fn compose_span_observers(
  observers : Array[SpanLifecycleObserver],
) -> SpanLifecycleObserver {
  span_lifecycle_observer(
    on_created=fn(span) {
      observers.each(fn(observer) { (observer.on_created)(span_snapshot(span)) })
    },
    on_entered=fn(span) {
      observers.each(fn(observer) { (observer.on_entered)(span_snapshot(span)) })
    },
    on_recorded=fn(span, field) {
      observers.each(fn(observer) {
        (observer.on_recorded)(span_snapshot(span), field)
      })
    },
    on_exited=fn(span) {
      observers.each(fn(observer) { (observer.on_exited)(span_snapshot(span)) })
    },
    on_closed=fn(span) {
      observers.each(fn(observer) { (observer.on_closed)(span_snapshot(span)) })
    },
    on_linked=fn(span, link) {
      observers.each(fn(observer) {
        (observer.on_linked)(span_snapshot(span), link_snapshot(link))
      })
    },
  )
}

///|
pub fn set_span_observer(observer : SpanLifecycleObserver) -> Unit {
  global_span_observer.val = Some(observer)
}

///|
pub fn clear_span_observer() -> Unit {
  global_span_observer.val = None
}

///|
pub fn span_link(
  target : Span,
  kind? : SpanLinkKind = SpanLinked,
  fields? : Array[Field] = [],
) -> SpanLink {
  {
    trace_id: target.trace_id,
    span_id: target.span_id,
    kind,
    fields: fields.copy(),
  }
}

///|
pub fn Span::link(
  self : Span,
  target : Span,
  fields? : Array[Field] = [],
) -> Unit {
  notify_span_linked(self, span_link(target, fields~))
}

///|
pub fn Span::follows_from(
  self : Span,
  target : Span,
  fields? : Array[Field] = [],
) -> Unit {
  notify_span_linked(self, span_link(target, kind=SpanFollowsFrom, fields~))
}

///|
pub impl Show for SpanLinkKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub fn SpanLinkKind::to_string(self : SpanLinkKind) -> String {
  match self {
    SpanLinked => "LINK"
    SpanFollowsFrom => "FOLLOWS_FROM"
    SpanChildOf => "CHILD_OF"
  }
}

///|
pub fn SpanLinkKind::to_json(self : SpanLinkKind) -> Json {
  self.to_string().to_json()
}

///|
pub fn SpanLink::to_json(self : SpanLink) -> Json {
  let m : Map[String, Json] = {}
  m.set("trace_id", self.trace_id.to_json())
  m.set("span_id", self.span_id.to_json())
  m.set("kind", self.kind.to_json())
  m.set("fields", fields_to_json(self.fields))
  m.to_json()
}

///|
fn notify_span_created(span : Span) -> Unit {
  match global_span_observer.val {
    Some(observer) => (observer.on_created)(span_snapshot(span))
    None => ()
  }
}

///|
fn notify_span_entered(span : Span) -> Unit {
  match global_span_observer.val {
    Some(observer) => (observer.on_entered)(span_snapshot(span))
    None => ()
  }
}

///|
fn notify_span_recorded(span : Span, field : Field) -> Unit {
  match global_span_observer.val {
    Some(observer) => (observer.on_recorded)(span_snapshot(span), field)
    None => ()
  }
}

///|
fn notify_span_exited(span : Span) -> Unit {
  match global_span_observer.val {
    Some(observer) => (observer.on_exited)(span_snapshot(span))
    None => ()
  }
}

///|
fn notify_span_closed(span : Span) -> Unit {
  match global_span_observer.val {
    Some(observer) => (observer.on_closed)(span_snapshot(span))
    None => ()
  }
}

///|
fn notify_span_linked(span : Span, link : SpanLink) -> Unit {
  match global_span_observer.val {
    Some(observer) => (observer.on_linked)(span_snapshot(span), link)
    None => ()
  }
}
