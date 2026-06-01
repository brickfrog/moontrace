///|
pub(all) enum RedactionMode {
  Redact
  Drop
} derive(Eq, Compare, Debug)

///|
pub fn RedactionMode::to_string(self : RedactionMode) -> String {
  match self {
    Redact => "REDACT"
    Drop => "DROP"
  }
}

///|
pub impl Show for RedactionMode with fn output(self, logger) {
  logger.write_string(self.to_string())
}

///|
pub(all) struct RedactionPolicy {
  deny : Array[String]
  allow : Array[String]?
  mode : RedactionMode
  placeholder : String
} derive(Debug)

///|
pub fn redaction_policy(
  deny? : Array[String] = ["password", "token", "secret"],
  allow? : Array[String]? = None,
  mode? : RedactionMode = Redact,
  placeholder? : String = "[REDACTED]",
) -> RedactionPolicy {
  {
    deny: deny.copy(),
    allow: match allow {
      Some(allowed) => Some(allowed.copy())
      None => None
    },
    mode,
    placeholder,
  }
}

///|
pub fn default_redaction_policy() -> RedactionPolicy {
  redaction_policy()
}

///|
fn key_matches_allow(key : String, allow : Array[String]) -> Bool {
  let lower_key = key.to_lower()
  for allowed in allow {
    if lower_key == allowed.to_lower() {
      return true
    }
  }
  false
}

///|
fn key_matches_deny(key : String, deny : Array[String]) -> Bool {
  let lower_key = key.to_lower()
  for pattern in deny {
    let lower_pattern = pattern.to_lower()
    if lower_key.contains(lower_pattern) {
      return true
    }
  }
  false
}

///|
fn should_transform_field(key : String, policy : RedactionPolicy) -> Bool {
  match policy.allow {
    Some(allow) => !key_matches_allow(key, allow)
    None => key_matches_deny(key, policy.deny)
  }
}

///|
fn redact_field(field : Field, policy : RedactionPolicy) -> Field? {
  match should_transform_field(field.key, policy) {
    false => Some(field)
    true =>
      match policy.mode {
        Redact => Some({ key: field.key, value: policy.placeholder.to_json() })
        Drop => None
      }
  }
}

///|
fn redact_event(event : Event, policy : RedactionPolicy) -> Event {
  let fields : Array[Field] = []
  event.fields.each(fn(field) {
    match redact_field(field, policy) {
      Some(redacted) => fields.push(redacted)
      None => ()
    }
  })
  Event::{
    level: event.level,
    message: event.message,
    fields,
    timestamp: event.timestamp,
    source: event.source,
  }
}

///|
pub fn redact(
  inner : (Event) -> Unit,
  policy? : RedactionPolicy = default_redaction_policy(),
) -> (Event) -> Unit {
  fn(event) { inner(redact_event(event, policy)) }
}
