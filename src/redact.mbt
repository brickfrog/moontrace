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
  deny~ : Array[String] = ["password", "token", "secret"],
  allow~ : Array[String]? = None,
  mode~ : RedactionMode = Redact,
  placeholder~ : String = "[REDACTED]",
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
/// Apply a deny-list policy to object keys at any depth, including objects
/// inside arrays. Scalars are returned unchanged.
fn redact_nested_json(value : Json, policy : RedactionPolicy) -> Json {
  match value {
    Object(entries) => {
      let redacted : Map[String, Json] = Map([])
      for key, nested in entries {
        match key_matches_deny(key, policy.deny) {
          false => redacted.set(key, redact_nested_json(nested, policy))
          true =>
            match policy.mode {
              Redact => redacted.set(key, Json(policy.placeholder))
              Drop => ()
            }
        }
      }
      Json(redacted)
    }
    Array(items) => Json(items.map(item => redact_nested_json(item, policy)))
    _ => value
  }
}

///|
fn redact_field(field : Field, policy : RedactionPolicy) -> Field? {
  match should_transform_field(field.key, policy) {
    false =>
      match policy.allow {
        // An allow-listed field is passed through whole.
        Some(_) => Some(field)
        None =>
          Some({
            key: field.key,
            value: redact_nested_json(field.value, policy),
          })
      }
    true =>
      match policy.mode {
        Redact => Some({ key: field.key, value: Json(policy.placeholder), })
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
  { ..event, fields, }
}

///|
pub fn redact(
  inner : (Event) -> Unit,
  policy~ : RedactionPolicy = default_redaction_policy(),
) -> (Event) -> Unit {
  fn(event) { inner(redact_event(event, policy)) }
}
