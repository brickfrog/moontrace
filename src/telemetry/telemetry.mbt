///|
/// A named instrumentation event delivered to handlers. Each handler gets its
/// own copies of `measurements` and `metadata`.
pub(all) struct TelemetryEvent {
  name : String
  measurements : Map[String, Double]
  metadata : Map[String, Json]
}

///|
priv struct Handler {
  id : String
  names : Array[String]
  callback : (TelemetryEvent) -> Unit
}

///|
let handlers : Ref[Array[Handler]] = { val: [], }

///|
/// Attach `callback` to events named `name` under a unique `handler_id`.
/// Returns `false`, leaving existing handlers unchanged, if the id is taken.
pub fn attach(
  handler_id : String,
  name : String,
  callback : (TelemetryEvent) -> Unit,
) -> Bool {
  attach_many(handler_id, [name], callback)
}

///|
/// Attach `callback` to every event named in `names` under one `handler_id`.
/// Returns `false` if the id is already attached.
pub fn attach_many(
  handler_id : String,
  names : Array[String],
  callback : (TelemetryEvent) -> Unit,
) -> Bool {
  if handlers.val.iter().any(h => h.id == handler_id) {
    return false
  }
  handlers.val.push({ id: handler_id, names: names.copy(), callback, })
  true
}

///|
/// Detach the handler registered under `handler_id`. Returns whether one was
/// attached.
pub fn detach(handler_id : String) -> Bool {
  let before = handlers.val.length()
  handlers.val = handlers.val.filter(h => h.id != handler_id)
  handlers.val.length() < before
}

///|
/// The ids of attached handlers, in attachment order, optionally only those
/// listening to `name`.
pub fn handler_ids(name? : String) -> Array[String] {
  handlers.val
  .filter(h => {
    match name {
      Some(name) => h.names.contains(name)
      None => true
    }
  })
  .map(h => h.id)
}

///|
/// Run `f` with `callback` attached to `names` under `handler_id`, detaching it
/// afterwards even if `f` raises. Useful in tests.
pub fn[T] with_handler(
  handler_id : String,
  names : Array[String],
  callback : (TelemetryEvent) -> Unit,
  f : () -> T raise?,
) -> T raise? {
  let attached = attach_many(handler_id, names, callback)
  defer (if attached { ignore(detach(handler_id)) })
  f()
}

///|
/// Emit the event `name` to every handler attached to it, in attachment order.
/// With no handlers attached this does nothing beyond the lookup, so libraries
/// can instrument freely. Handlers attached or detached during delivery take
/// effect from the next event.
pub fn execute(
  name : String,
  measurements : Map[String, Double],
  metadata~ : Map[String, Json] = Map([]),
) -> Unit {
  let targets = handlers.val.filter(h => h.names.contains(name))
  for handler in targets {
    (handler.callback)({
      name,
      measurements: measurements.copy(),
      metadata: metadata.copy(),
    })
  }
}

///|
/// Describe an error raised by `throw_error`.
fn describe_raised(throw_error : () -> Unit raise) -> String {
  throw_error() catch {
    error => return "\{error}"
  }
  ""
}

///|
/// Instrument `f` as a unit of work: emit `<name>.start` with a
/// `monotonic_time_ms` measurement, then `<name>.stop` with `duration_ms`, or
/// `<name>.exception` with `duration_ms` and the error in `metadata["error"]`
/// before re-raising it unchanged. All three events carry `metadata`.
#warnings("-fragile_catch_all")
pub fn[T] span(
  name : String,
  metadata~ : Map[String, Json] = Map([]),
  f : () -> T raise?,
) -> T raise? {
  let started = @env.now()
  execute(
    name + ".start",
    { "monotonic_time_ms": started.to_double() },
    metadata~,
  )
  let elapsed = () => {
    let now = @env.now()
    (if now > started { now - started } else { 0UL }).to_double()
  }
  let result = f() catch {
    err => {
      let with_error = metadata.copy()
      with_error.set("error", Json(describe_raised(fn() raise { raise err })))
      execute(
        name + ".exception",
        { "duration_ms": elapsed() },
        metadata=with_error,
      )
      raise err
    }
  }
  execute(name + ".stop", { "duration_ms": elapsed() }, metadata~)
  result
}
