///|
/// How `event_json` renders the event timestamp.
pub(all) enum TimestampFormat {
  /// Milliseconds since the Unix epoch, the `Event::to_json` default.
  EpochMillis
  /// RFC 3339 UTC with millisecond precision, e.g. `2026-03-28T14:31:43.903Z`.
  Rfc3339
}

///|
/// Top-level key names used by `event_json`.
pub(all) struct JsonKeys {
  level : String
  message : String
  timestamp : String
  source : String
  file : String
  line : String
  fields : String
  trace_id : String
  span_id : String
}

///|
/// Build `JsonKeys`, overriding only the names you pass. For example, ECS-style
/// output can use `json_keys(timestamp="@timestamp", level="log.level")`.
pub fn json_keys(
  level~ : String = "level",
  message~ : String = "message",
  timestamp~ : String = "timestamp",
  source~ : String = "source",
  file~ : String = "file",
  line~ : String = "line",
  fields~ : String = "fields",
  trace_id~ : String = "trace_id",
  span_id~ : String = "span_id",
) -> JsonKeys {
  { level, message, timestamp, source, file, line, fields, trace_id, span_id, }
}

///|
/// Build the JSON record for `event`. With default options the result equals
/// `event.to_json()`.
///
/// * `timestamp` selects epoch milliseconds or RFC 3339.
/// * `flatten` writes fields as top-level keys instead of a nested object. A
///   field whose key matches a top-level key is written as `fields.<key>`.
/// * `trace_ids` moves the span-correlated `trace_id` and `span_id` fields to
///   top-level keys (the last value wins, as span correlation appends them).
/// * `keys` renames the top-level keys.
pub fn event_json(
  event : @moontrace.Event,
  timestamp~ : TimestampFormat = EpochMillis,
  flatten~ : Bool = false,
  trace_ids~ : Bool = false,
  keys~ : JsonKeys = json_keys(),
) -> Json {
  let record : Map[String, Json] = Map([])
  record.set(keys.level, event.level.to_json())
  record.set(keys.message, Json(event.message))
  record.set(
    keys.timestamp,
    match timestamp {
      EpochMillis => Json(event.timestamp)
      Rfc3339 => Json(@moontrace.format_timestamp_rfc3339(event.timestamp))
    },
  )
  record.set(keys.source, Json(event.source))
  if !event.file.is_empty() {
    record.set(keys.file, Json(event.file))
    record.set(keys.line, Json(event.line))
  }
  let fields = if trace_ids {
    promote_trace_ids(event.fields, record, keys)
  } else {
    event.fields
  }
  if flatten {
    let reserved = record.copy()
    for field in fields {
      let key = if reserved.contains(field.key) {
        "fields." + field.key
      } else {
        field.key
      }
      record.set(key, field.value)
    }
  } else {
    record.set(keys.fields, @moontrace.fields_to_json(fields))
  }
  Json(record)
}

///|
/// Set top-level trace and span IDs from string fields and return the fields
/// without them. Non-string values stay in the fields.
fn promote_trace_ids(
  fields : Array[@moontrace.Field],
  record : Map[String, Json],
  keys : JsonKeys,
) -> Array[@moontrace.Field] {
  let remaining : Array[@moontrace.Field] = []
  let mut trace_id : String? = None
  let mut span_id : String? = None
  for field in fields {
    match (field.key, field.value) {
      ("trace_id", String(value)) => trace_id = Some(value)
      ("span_id", String(value)) => span_id = Some(value)
      _ => remaining.push(field)
    }
  }
  if trace_id is Some(value) {
    record.set(keys.trace_id, Json(value))
  }
  if span_id is Some(value) {
    record.set(keys.span_id, Json(value))
  }
  remaining
}
