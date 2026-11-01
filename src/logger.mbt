///|
/// Explicit bound logging context. Pass it to work that needs the same fields;
/// it does not install global or task-local context or manage span lifetimes.
pub struct Logger {
  priv bound_fields : Array[Field]
  priv associated_span : Span?
  priv min_level : Level?
}

///|
fn copy_logger_json(value : Json) -> Json {
  match value {
    Array(values) => Json(values.map(copy_logger_json))
    Object(values) => {
      let result : Map[String, Json] = Map([])
      values.each(fn(key, value) { result.set(key, copy_logger_json(value)) })
      Json(result)
    }
    _ => value
  }
}

///|
// Keep the first occurrence's position, but the last occurrence's value.
// Copy JSON containers as well as the field array to isolate bound state.
fn merge_logger_fields(
  base : Array[Field],
  overrides : Array[Field],
) -> Array[Field] {
  let result : Array[Field] = []
  let positions : Map[String, Int32] = Map([])
  for layer in [base, overrides] {
    for field in layer {
      let copied = Field::{
        key: field.key,
        value: copy_logger_json(field.value),
      }
      match positions.get(field.key) {
        Some(index) => result[index] = copied
        None => {
          positions.set(field.key, result.length())
          result.push(copied)
        }
      }
    }
  }
  result
}

///|
/// Bind a snapshot of fields, optionally associated with an existing span.
/// Duplicate keys use the last value. The span supplies correlation IDs only;
/// its fields and lifecycle are not inherited or changed. When `min_level` is
/// set, it replaces the global and module filters for this logger's events.
pub fn logger(
  fields~ : Array[Field] = [],
  span? : Span,
  min_level? : Level,
) -> Logger {
  {
    bound_fields: merge_logger_fields([], fields),
    associated_span: span,
    min_level,
  }
}

///|
/// Derive an independent child logger. Child fields override parent fields;
/// the associated span and minimum level are retained. Arrays and nested JSON
/// are copied.
pub fn Logger::bind(self : Logger, fields : Array[Field]) -> Logger {
  {
    bound_fields: merge_logger_fields(self.bound_fields, fields),
    associated_span: self.associated_span,
    min_level: self.min_level,
  }
}

///|
/// Derive a logger associated with span, preserving the bound fields and
/// minimum level. This does not enter or exit the span or change the original
/// logger.
pub fn Logger::in_span(self : Logger, span : Span) -> Logger {
  {
    bound_fields: merge_logger_fields([], self.bound_fields),
    associated_span: Some(span),
    min_level: self.min_level,
  }
}

///|
/// Derive a logger whose own minimum level replaces the global and module
/// filters for its events, either more verbose (debug one request) or stricter.
/// Bound fields and the associated span are preserved; the original is unchanged.
pub fn Logger::with_min_level(self : Logger, level : Level) -> Logger {
  {
    bound_fields: merge_logger_fields([], self.bound_fields),
    associated_span: self.associated_span,
    min_level: Some(level),
  }
}

///|
fn Logger::admits(self : Logger, level : Level, source : String) -> Bool {
  match self.min_level {
    Some(min) => level >= min
    None => should_log_module(source, level)
  }
}

///|
/// Report whether an event at `level` from this logger would reach the
/// installed subscriber, using the logger's own minimum level when set.
#callsite(autofill(loc))
pub fn Logger::enabled(self : Logger, level : Level, loc~ : SourceLoc) -> Bool {
  global_subscriber.val is Some(_) && self.admits(level, extract_package(loc))
}

///|
/// Emit through the current subscriber using the caller's package. A logger
/// minimum level replaces the global and module filters; otherwise they apply.
/// Precedence is global < bound < event fields (last duplicate wins).
/// An associated span's trace_id, span_id, and parent_span_id always win.
#callsite(autofill(loc))
pub fn Logger::event(
  self : Logger,
  level : Level,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  let source = extract_package(loc)
  if !self.admits(level, source) {
    return
  }
  let fields = merge_logger_fields(self.bound_fields, fields)
  match self.associated_span {
    Some(span) =>
      dispatch_in_span_from_source(span, level, msg, fields, source, loc)
    None => dispatch_from_source(level, msg, fields, source, loc)
  }
}

///|
#callsite(autofill(loc))
pub fn Logger::trace(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Trace, msg, fields~, loc~)
}

///|
#callsite(autofill(loc))
pub fn Logger::debug(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Debug, msg, fields~, loc~)
}

///|
#callsite(autofill(loc))
pub fn Logger::info(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Info, msg, fields~, loc~)
}

///|
#callsite(autofill(loc))
pub fn Logger::warn(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Warn, msg, fields~, loc~)
}

///|
#callsite(autofill(loc))
pub fn Logger::error(
  self : Logger,
  msg : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  self.event(Error_, msg, fields~, loc~)
}

///|
/// A running timer from `Logger::start_timer`.
pub struct LogTimer {
  priv logger : Logger
  priv started_ms : UInt64
}

///|
/// Start timing an operation. Call `done` on the result to log its duration,
/// in the style of winston's `startTimer`.
pub fn Logger::start_timer(self : Logger) -> LogTimer {
  { logger: self, started_ms: @env.now(), }
}

///|
/// Milliseconds since the timer started.
pub fn LogTimer::elapsed_ms(self : LogTimer) -> UInt64 {
  let now = @env.now()
  if now > self.started_ms {
    now - self.started_ms
  } else {
    0UL
  }
}

///|
/// Log `msg` through the timer's logger with a `duration_ms` field holding
/// the elapsed time. `duration_ms` follows `fields`, so it wins on a key
/// collision. The timer can be finished more than once; each call measures
/// from the start.
#callsite(autofill(loc))
pub fn LogTimer::done(
  self : LogTimer,
  msg : String,
  level~ : Level = Info,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  let all = fields.copy()
  all.push({ key: "duration_ms", value: Json(self.elapsed_ms().to_double()), })
  self.logger.event(level, msg, fields=all, loc~)
}
