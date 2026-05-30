///|
priv struct TraceStateSnapshot {
  subscriber : ((Event) -> Unit)?
  min_level : Level
  context : Map[String, Json]
  filters : Map[String, Level]
  span_observer : SpanLifecycleObserver?
}

///|
fn snapshot_trace_state() -> TraceStateSnapshot {
  {
    subscriber: global_subscriber.val,
    min_level: global_min_level.val,
    context: global_context.val.copy(),
    filters: module_filters.val.copy(),
    span_observer: global_span_observer.val,
  }
}

///|
fn restore_trace_state(snapshot : TraceStateSnapshot) -> Unit {
  global_subscriber.val = snapshot.subscriber
  global_min_level.val = snapshot.min_level
  global_context.val = snapshot.context
  module_filters.val = snapshot.filters
  global_span_observer.val = snapshot.span_observer
}

///|
/// Run `f` with the current tracing globals guarded by a synchronous scope.
///
/// The subscriber, global minimum level, global context fields, module filters,
/// and span lifecycle observer are snapshotted before `f` runs and restored
/// when `f` returns or raises. This is only a synchronous guard for the current
/// call stack; it is not task-local storage and does not propagate tracing state
/// across async tasks.
pub fn[T] with_trace_state(f : () -> T raise?) -> T raise? {
  let snapshot = snapshot_trace_state()
  try f() catch {
    err => {
      restore_trace_state(snapshot)
      raise err
    }
  } noraise {
    result => {
      restore_trace_state(snapshot)
      result
    }
  }
}

///|
/// Run `f` with `subscriber` installed, then restore the previous tracing
/// globals. This is a synchronous scope, not task-local async propagation.
pub fn[T] with_subscriber(
  subscriber : (Event) -> Unit,
  f : () -> T raise?,
) -> T raise? {
  with_trace_state(() => {
    set_subscriber(subscriber)
    f()
  })
}

///|
/// Run `f` with a scoped global minimum level, then restore the previous
/// tracing globals. This is a synchronous scope, not task-local async
/// propagation.
pub fn[T] with_min_level(level : Level, f : () -> T raise?) -> T raise? {
  with_trace_state(() => {
    set_min_level(level)
    f()
  })
}

///|
/// Run `f` with one scoped global context field, then restore the previous
/// tracing globals. This is a synchronous scope, not task-local async
/// propagation.
pub fn[V : ToJson, T] with_global_field(
  key : String,
  value : V,
  f : () -> T raise?,
) -> T raise? {
  with_trace_state(() => {
    set_global_field(key, value)
    f()
  })
}

///|
/// Run `f` with additional scoped global context fields, then restore the
/// previous tracing globals. Later fields with the same key overwrite earlier
/// scoped values. This is a synchronous scope, not task-local async
/// propagation.
pub fn[T] with_global_fields(
  fields : Array[Field],
  f : () -> T raise?,
) -> T raise? {
  with_trace_state(() => {
    fields.each(fn(field) { global_context.val.set(field.key, field.value) })
    f()
  })
}

///|
/// Run `f` with one scoped module filter, then restore the previous tracing
/// globals. This is a synchronous scope, not task-local async propagation.
pub fn[T] with_module_filter(
  module_name : String,
  level : Level,
  f : () -> T raise?,
) -> T raise? {
  with_trace_state(() => {
    set_module_filter(module_name, level)
    f()
  })
}
