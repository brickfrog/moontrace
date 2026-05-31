///|
pub(all) enum SpanLifecycleKind {
  SpanCreated
  SpanEntered
  SpanRecorded
  SpanExited
  SpanClosed
  SpanLinked
} derive(Eq, Compare, Debug)

///|
pub struct SpanLifecycleEvent {
  index : Int
  kind : SpanLifecycleKind
  span : @moontrace.Span
  field : @moontrace.Field?
  link : @moontrace.SpanLink?
} derive(Debug)

///|
pub struct CapturedRecord {
  index : Int
  event : @moontrace.Event?
  lifecycle : SpanLifecycleEvent?
} derive(Debug)

///|
pub struct EventQuery {
  level : @moontrace.Level?
  message : String?
  source : String?
  field_key : String?
  field_value : Json?
  span_id : String?
  span_name : String?
} derive(Debug)

///|
pub struct LifecycleQuery {
  kind : SpanLifecycleKind?
  span_id : String?
  span_name : String?
  field_key : String?
} derive(Debug)

///|
pub struct TestSubscriber {
  events : Array[@moontrace.Event]
  lifecycle : Array[SpanLifecycleEvent]
  records : Array[CapturedRecord]
} derive(Debug)

///|
pub fn test_subscriber() -> TestSubscriber {
  { events: [], lifecycle: [], records: [] }
}

///|
pub fn event_query() -> EventQuery {
  {
    level: None,
    message: None,
    source: None,
    field_key: None,
    field_value: None,
    span_id: None,
    span_name: None,
  }
}

///|
pub fn event_with_level(level : @moontrace.Level) -> EventQuery {
  event_query().with_level(level)
}

///|
pub fn event_with_message(message : String) -> EventQuery {
  event_query().with_message(message)
}

///|
pub fn event_with_source(source : String) -> EventQuery {
  event_query().with_source(source)
}

///|
pub fn event_with_field(key : String) -> EventQuery {
  event_query().with_field(key)
}

///|
pub fn[V : ToJson] event_with_field_value(
  key : String,
  value : V,
) -> EventQuery {
  event_query().with_field_value(key, value)
}

///|
pub fn event_in_span(span : @moontrace.Span) -> EventQuery {
  event_query().with_span(span)
}

///|
pub fn event_in_span_named(span_name : String) -> EventQuery {
  event_query().with_span_name(span_name)
}

///|
pub fn EventQuery::with_level(
  self : EventQuery,
  level : @moontrace.Level,
) -> EventQuery {
  {
    level: Some(level),
    message: self.message,
    source: self.source,
    field_key: self.field_key,
    field_value: self.field_value,
    span_id: self.span_id,
    span_name: self.span_name,
  }
}

///|
pub fn EventQuery::with_message(
  self : EventQuery,
  message : String,
) -> EventQuery {
  {
    level: self.level,
    message: Some(message),
    source: self.source,
    field_key: self.field_key,
    field_value: self.field_value,
    span_id: self.span_id,
    span_name: self.span_name,
  }
}

///|
pub fn EventQuery::with_source(
  self : EventQuery,
  source : String,
) -> EventQuery {
  {
    level: self.level,
    message: self.message,
    source: Some(source),
    field_key: self.field_key,
    field_value: self.field_value,
    span_id: self.span_id,
    span_name: self.span_name,
  }
}

///|
pub fn EventQuery::with_field(self : EventQuery, key : String) -> EventQuery {
  {
    level: self.level,
    message: self.message,
    source: self.source,
    field_key: Some(key),
    field_value: self.field_value,
    span_id: self.span_id,
    span_name: self.span_name,
  }
}

///|
pub fn[V : ToJson] EventQuery::with_field_value(
  self : EventQuery,
  key : String,
  value : V,
) -> EventQuery {
  {
    level: self.level,
    message: self.message,
    source: self.source,
    field_key: Some(key),
    field_value: Some(value.to_json()),
    span_id: self.span_id,
    span_name: self.span_name,
  }
}

///|
pub fn EventQuery::with_span(
  self : EventQuery,
  span : @moontrace.Span,
) -> EventQuery {
  {
    level: self.level,
    message: self.message,
    source: self.source,
    field_key: self.field_key,
    field_value: self.field_value,
    span_id: Some(span.span_id),
    span_name: self.span_name,
  }
}

///|
pub fn EventQuery::with_span_name(
  self : EventQuery,
  name : String,
) -> EventQuery {
  {
    level: self.level,
    message: self.message,
    source: self.source,
    field_key: self.field_key,
    field_value: self.field_value,
    span_id: self.span_id,
    span_name: Some(name),
  }
}

///|
pub fn lifecycle_query() -> LifecycleQuery {
  { kind: None, span_id: None, span_name: None, field_key: None }
}

///|
pub fn lifecycle_kind(kind : SpanLifecycleKind) -> LifecycleQuery {
  lifecycle_query().with_kind(kind)
}

///|
pub fn LifecycleQuery::with_kind(
  self : LifecycleQuery,
  kind : SpanLifecycleKind,
) -> LifecycleQuery {
  {
    kind: Some(kind),
    span_id: self.span_id,
    span_name: self.span_name,
    field_key: self.field_key,
  }
}

///|
pub fn LifecycleQuery::with_span(
  self : LifecycleQuery,
  span : @moontrace.Span,
) -> LifecycleQuery {
  {
    kind: self.kind,
    span_id: Some(span.span_id),
    span_name: self.span_name,
    field_key: self.field_key,
  }
}

///|
pub fn LifecycleQuery::with_span_name(
  self : LifecycleQuery,
  name : String,
) -> LifecycleQuery {
  {
    kind: self.kind,
    span_id: self.span_id,
    span_name: Some(name),
    field_key: self.field_key,
  }
}

///|
pub fn LifecycleQuery::with_recorded_field(
  self : LifecycleQuery,
  key : String,
) -> LifecycleQuery {
  {
    kind: self.kind,
    span_id: self.span_id,
    span_name: self.span_name,
    field_key: Some(key),
  }
}

///|
fn event_snapshot(event : @moontrace.Event) -> @moontrace.Event {
  {
    level: event.level,
    message: event.message,
    fields: event.fields.copy(),
    timestamp: event.timestamp,
    source: event.source,
  }
}

///|
fn TestSubscriber::capture_event(
  self : TestSubscriber,
  event : @moontrace.Event,
) -> Unit {
  let snapshot = event_snapshot(event)
  let index = self.records.length()
  self.events.push(snapshot)
  self.records.push({ index, event: Some(snapshot), lifecycle: None })
}

///|
fn TestSubscriber::capture_lifecycle(
  self : TestSubscriber,
  kind : SpanLifecycleKind,
  span : @moontrace.Span,
  field : @moontrace.Field?,
  link : @moontrace.SpanLink?,
) -> Unit {
  let index = self.records.length()
  let lifecycle = { index, kind, span, field, link }
  self.lifecycle.push(lifecycle)
  self.records.push({ index, event: None, lifecycle: Some(lifecycle) })
}

///|
pub fn TestSubscriber::subscriber(
  self : TestSubscriber,
) -> (@moontrace.Event) -> Unit {
  fn(event) { self.capture_event(event) }
}

///|
pub fn TestSubscriber::observer(
  self : TestSubscriber,
) -> @moontrace.SpanLifecycleObserver {
  @moontrace.span_lifecycle_observer(
    on_created=fn(span) {
      self.capture_lifecycle(SpanCreated, span, None, None)
    },
    on_entered=fn(span) {
      self.capture_lifecycle(SpanEntered, span, None, None)
    },
    on_recorded=fn(span, field) {
      self.capture_lifecycle(SpanRecorded, span, Some(field), None)
    },
    on_exited=fn(span) { self.capture_lifecycle(SpanExited, span, None, None) },
    on_closed=fn(span) { self.capture_lifecycle(SpanClosed, span, None, None) },
    on_linked=fn(span, link) {
      self.capture_lifecycle(SpanLinked, span, None, Some(link))
    },
  )
}

///|
pub fn[T] TestSubscriber::with_install(
  self : TestSubscriber,
  f : () -> T raise?,
) -> T raise? {
  @moontrace.with_trace_state(() => {
    @moontrace.set_subscriber(self.subscriber())
    @moontrace.set_span_observer(self.observer())
    f()
  })
}

///|
pub fn[T] with_test_subscriber(
  capture : TestSubscriber,
  f : () -> T raise?,
) -> T raise? {
  capture.with_install(f)
}

///|
pub fn TestSubscriber::captured_events(
  self : TestSubscriber,
) -> Array[@moontrace.Event] {
  self.events.copy()
}

///|
pub fn TestSubscriber::captured_lifecycle(
  self : TestSubscriber,
) -> Array[SpanLifecycleEvent] {
  self.lifecycle.copy()
}

///|
pub fn TestSubscriber::captured_records(
  self : TestSubscriber,
) -> Array[CapturedRecord] {
  self.records.copy()
}

///|
fn json_eq(left : Json, right : Json) -> Bool {
  left.stringify() == right.stringify()
}

///|
fn event_has_field(
  event : @moontrace.Event,
  key : String,
  value : Json?,
) -> Bool {
  let mut found = false
  event.fields.each(fn(field) {
    if field.key == key {
      match value {
        Some(expected) => if json_eq(field.value, expected) { found = true }
        None => found = true
      }
    }
  })
  found
}

///|
fn TestSubscriber::record_in_span(
  self : TestSubscriber,
  record_index : Int,
  span_id : String?,
  span_name : String?,
) -> Bool {
  if span_id == None && span_name == None {
    return true
  }
  let mut active_matches = 0
  self.lifecycle.each(fn(item) {
    let id_matches = match span_id {
      Some(id) => item.span.span_id == id
      None => true
    }
    let name_matches = match span_name {
      Some(name) => item.span.name == name
      None => true
    }
    if id_matches && name_matches {
      if item.kind == SpanEntered && item.index < record_index {
        active_matches = active_matches + 1
      }
      if item.kind == SpanExited && item.index <= record_index {
        if active_matches > 0 {
          active_matches = active_matches - 1
        }
      }
    }
  })
  active_matches > 0
}

///|
fn TestSubscriber::event_matches(
  self : TestSubscriber,
  query : EventQuery,
  event : @moontrace.Event,
  record_index : Int,
) -> Bool {
  let level_matches = match query.level {
    Some(level) => event.level == level
    None => true
  }
  let message_matches = match query.message {
    Some(message) => event.message == message
    None => true
  }
  let source_matches = match query.source {
    Some(source) => event.source == source
    None => true
  }
  let field_matches = match query.field_key {
    Some(key) => event_has_field(event, key, query.field_value)
    None => true
  }
  level_matches &&
  message_matches &&
  source_matches &&
  field_matches &&
  self.record_in_span(record_index, query.span_id, query.span_name)
}

///|
fn lifecycle_matches(
  query : LifecycleQuery,
  event : SpanLifecycleEvent,
) -> Bool {
  let kind_matches = match query.kind {
    Some(kind) => event.kind == kind
    None => true
  }
  let id_matches = match query.span_id {
    Some(id) => event.span.span_id == id
    None => true
  }
  let name_matches = match query.span_name {
    Some(name) => event.span.name == name
    None => true
  }
  let field_matches = match query.field_key {
    Some(key) =>
      match event.field {
        Some(field) => field.key == key
        None => false
      }
    None => true
  }
  kind_matches && id_matches && name_matches && field_matches
}

///|
pub fn TestSubscriber::events_matching(
  self : TestSubscriber,
  query : EventQuery,
) -> Array[@moontrace.Event] {
  let matched : Array[@moontrace.Event] = []
  self.records.each(fn(record) {
    match record.event {
      Some(event) =>
        if self.event_matches(query, event, record.index) {
          matched.push(event)
        }
      None => ()
    }
  })
  matched
}

///|
pub fn TestSubscriber::events_by_level(
  self : TestSubscriber,
  level : @moontrace.Level,
) -> Array[@moontrace.Event] {
  self.events_matching(event_with_level(level))
}

///|
pub fn TestSubscriber::events_by_message(
  self : TestSubscriber,
  message : String,
) -> Array[@moontrace.Event] {
  self.events_matching(event_with_message(message))
}

///|
pub fn TestSubscriber::events_by_source(
  self : TestSubscriber,
  source : String,
) -> Array[@moontrace.Event] {
  self.events_matching(event_with_source(source))
}

///|
pub fn TestSubscriber::events_by_field(
  self : TestSubscriber,
  key : String,
) -> Array[@moontrace.Event] {
  self.events_matching(event_with_field(key))
}

///|
pub fn[V : ToJson] TestSubscriber::events_by_field_value(
  self : TestSubscriber,
  key : String,
  value : V,
) -> Array[@moontrace.Event] {
  self.events_matching(event_with_field_value(key, value))
}

///|
pub fn TestSubscriber::events_in_span(
  self : TestSubscriber,
  span : @moontrace.Span,
) -> Array[@moontrace.Event] {
  self.events_matching(event_in_span(span))
}

///|
pub fn TestSubscriber::events_in_span_named(
  self : TestSubscriber,
  name : String,
) -> Array[@moontrace.Event] {
  self.events_matching(event_in_span_named(name))
}

///|
pub fn TestSubscriber::lifecycle_matching(
  self : TestSubscriber,
  query : LifecycleQuery,
) -> Array[SpanLifecycleEvent] {
  let matched : Array[SpanLifecycleEvent] = []
  self.lifecycle.each(fn(event) {
    if lifecycle_matches(query, event) {
      matched.push(event)
    }
  })
  matched
}

///|
pub fn SpanLifecycleKind::to_string(self : SpanLifecycleKind) -> String {
  match self {
    SpanCreated => "created"
    SpanEntered => "entered"
    SpanRecorded => "recorded"
    SpanExited => "exited"
    SpanClosed => "closed"
    SpanLinked => "linked"
  }
}

///|
pub impl Show for SpanLifecycleKind with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
fn describe_event_query(query : EventQuery) -> String {
  let mut parts = "event"
  match query.level {
    Some(level) => parts = parts + " level=" + level.to_string()
    None => ()
  }
  match query.message {
    Some(message) => parts = parts + " message=" + message
    None => ()
  }
  match query.source {
    Some(source) => parts = parts + " source=" + source
    None => ()
  }
  match query.field_key {
    Some(key) =>
      match query.field_value {
        Some(value) => parts = parts + " field=" + key + "=" + value.stringify()
        None => parts = parts + " field=" + key
      }
    None => ()
  }
  match query.span_id {
    Some(id) => parts = parts + " span_id=" + id
    None => ()
  }
  match query.span_name {
    Some(name) => parts = parts + " span_name=" + name
    None => ()
  }
  parts
}

///|
fn describe_lifecycle_query(query : LifecycleQuery) -> String {
  let mut parts = "lifecycle"
  match query.kind {
    Some(kind) => parts = parts + " kind=" + kind.to_string()
    None => ()
  }
  match query.span_id {
    Some(id) => parts = parts + " span_id=" + id
    None => ()
  }
  match query.span_name {
    Some(name) => parts = parts + " span_name=" + name
    None => ()
  }
  match query.field_key {
    Some(key) => parts = parts + " field=" + key
    None => ()
  }
  parts
}

///|
fn describe_event(event : @moontrace.Event) -> String {
  event.level.to_string() +
  " " +
  event.message +
  " source=" +
  event.source +
  " fields=" +
  @moontrace.fields_to_json(event.fields).stringify()
}

///|
fn describe_events(events : Array[@moontrace.Event]) -> String {
  if events.is_empty() {
    return "\n<none>"
  }
  let mut out = ""
  for i in 0..<events.length() {
    out = out + "\n[" + "\{i}" + "] " + describe_event(events[i])
  }
  out
}

///|
fn describe_lifecycle_event(event : SpanLifecycleEvent) -> String {
  let mut out = event.kind.to_string() + " " + event.span.name
  match event.field {
    Some(field) => out = out + " field=" + field.key
    None => ()
  }
  out
}

///|
fn describe_lifecycle_events(events : Array[SpanLifecycleEvent]) -> String {
  if events.is_empty() {
    return "\n<none>"
  }
  let mut out = ""
  for i in 0..<events.length() {
    out = out + "\n[" + "\{i}" + "] " + describe_lifecycle_event(events[i])
  }
  out
}

///|
pub fn TestSubscriber::check_event(
  self : TestSubscriber,
  query : EventQuery,
) -> String? {
  if self.events_matching(query).is_empty() {
    Some(
      "missing " +
      describe_event_query(query) +
      "\ncaptured events:" +
      describe_events(self.events),
    )
  } else {
    None
  }
}

///|
pub fn TestSubscriber::assert_event(
  self : TestSubscriber,
  query : EventQuery,
) -> Unit {
  match self.check_event(query) {
    Some(message) => abort(message)
    None => ()
  }
}

///|
pub fn TestSubscriber::check_events_ordered(
  self : TestSubscriber,
  queries : Array[EventQuery],
) -> String? {
  let mut query_index = 0
  let mut record_start = 0
  while query_index < queries.length() {
    let query = queries[query_index]
    let mut record_index = record_start
    let mut matched = false
    while record_index < self.records.length() && !matched {
      let record = self.records[record_index]
      match record.event {
        Some(event) =>
          if self.event_matches(query, event, record.index) {
            matched = true
            record_start = record_index + 1
          }
        None => ()
      }
      record_index = record_index + 1
    }
    if !matched {
      return Some(
        "missing ordered event #" +
        "\{query_index}" +
        ": " +
        describe_event_query(query) +
        "\ncaptured events:" +
        describe_events(self.events),
      )
    }
    query_index = query_index + 1
  }
  None
}

///|
pub fn TestSubscriber::assert_events_ordered(
  self : TestSubscriber,
  queries : Array[EventQuery],
) -> Unit {
  match self.check_events_ordered(queries) {
    Some(message) => abort(message)
    None => ()
  }
}

///|
pub fn TestSubscriber::check_events_unordered(
  self : TestSubscriber,
  queries : Array[EventQuery],
) -> String? {
  let used = Array::make(self.records.length(), false)
  for query_index in 0..<queries.length() {
    let query = queries[query_index]
    let mut record_index = 0
    let mut matched = false
    while record_index < self.records.length() && !matched {
      let record = self.records[record_index]
      match record.event {
        Some(event) =>
          if !used[record_index] &&
            self.event_matches(query, event, record.index) {
            matched = true
            used[record_index] = true
          }
        None => ()
      }
      record_index = record_index + 1
    }
    if !matched {
      return Some(
        "missing unordered event #" +
        "\{query_index}" +
        ": " +
        describe_event_query(query) +
        "\ncaptured events:" +
        describe_events(self.events),
      )
    }
  }
  None
}

///|
pub fn TestSubscriber::assert_events_unordered(
  self : TestSubscriber,
  queries : Array[EventQuery],
) -> Unit {
  match self.check_events_unordered(queries) {
    Some(message) => abort(message)
    None => ()
  }
}

///|
pub fn TestSubscriber::check_lifecycle_ordered(
  self : TestSubscriber,
  queries : Array[LifecycleQuery],
) -> String? {
  let mut query_index = 0
  let mut lifecycle_start = 0
  while query_index < queries.length() {
    let query = queries[query_index]
    let mut lifecycle_index = lifecycle_start
    let mut matched = false
    while lifecycle_index < self.lifecycle.length() && !matched {
      let event = self.lifecycle[lifecycle_index]
      if lifecycle_matches(query, event) {
        matched = true
        lifecycle_start = lifecycle_index + 1
      }
      lifecycle_index = lifecycle_index + 1
    }
    if !matched {
      return Some(
        "missing ordered lifecycle #" +
        "\{query_index}" +
        ": " +
        describe_lifecycle_query(query) +
        "\ncaptured lifecycle:" +
        describe_lifecycle_events(self.lifecycle),
      )
    }
    query_index = query_index + 1
  }
  None
}

///|
pub fn TestSubscriber::assert_lifecycle_ordered(
  self : TestSubscriber,
  queries : Array[LifecycleQuery],
) -> Unit {
  match self.check_lifecycle_ordered(queries) {
    Some(message) => abort(message)
    None => ()
  }
}

///|
pub fn TestSubscriber::assert_span_lifecycle_ordered(
  self : TestSubscriber,
  span : @moontrace.Span,
  kinds : Array[SpanLifecycleKind],
) -> Unit {
  let queries = kinds.map(fn(kind) { lifecycle_kind(kind).with_span(span) })
  self.assert_lifecycle_ordered(queries)
}

///|
pub fn TestSubscriber::assert_created_entered_recorded_exited(
  self : TestSubscriber,
  span : @moontrace.Span,
) -> Unit {
  self.assert_span_lifecycle_ordered(span, [
    SpanCreated,
    SpanEntered,
    SpanRecorded,
    SpanExited,
  ])
}
