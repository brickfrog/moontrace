///|
fn redaction_sample_event(fields : Array[@moontrace.Field]) -> @moontrace.Event {
  @moontrace.Event::{
    level: @moontrace.Warn,
    message: "login attempt",
    fields,
    timestamp: (12345 : UInt64),
    source: "brickfrog/moontrace",
  }
}

///|
fn redaction_capture(
  event : @moontrace.Event,
  policy? : @moontrace.RedactionPolicy = @moontrace.default_redaction_policy(),
) -> @moontrace.Event {
  let captured : Array[@moontrace.Event] = []
  let subscriber = @moontrace.redact(
    fn(e : @moontrace.Event) { captured.push(e) },
    policy~,
  )
  subscriber(event)
  captured[0]
}

///|
fn assert_redaction_json_eq(actual : Json, expected : Json) -> Unit {
  if actual.stringify() != expected.stringify() {
    abort("expected \{expected.stringify()}, got \{actual.stringify()}")
  }
}

///|
fn assert_redaction_field(
  event : @moontrace.Event,
  index : Int,
  key : String,
  value : Json,
) -> Unit {
  let mut current = 0
  let mut found : @moontrace.Field? = None
  event.fields.each(fn(field) {
    if current == index {
      found = Some(field)
    }
    current = current + 1
  })
  match found {
    Some(field) => {
      if field.key != key {
        abort("expected field key \{key}, got \{field.key}")
      }
      assert_redaction_json_eq(field.value, value)
    }
    None => abort("missing field at index \{index}")
  }
}

///|
fn redaction_json_object(json : Json, label : String) -> Map[String, Json] {
  match json {
    Object(obj) => obj
    _ => abort("expected JSON object for \{label}")
  }
}

///|
fn redaction_json_field(obj : Map[String, Json], key : String) -> Json {
  match obj.get(key) {
    Some(value) => value
    None => abort("missing JSON field \{key}")
  }
}

///|
fn assert_no_redaction_json_field(
  obj : Map[String, Json],
  key : String,
) -> Unit {
  match obj.get(key) {
    Some(_) => abort("unexpected JSON field \{key}")
    None => ()
  }
}

///|
test "redaction mode show uses uppercase" {
  assert_eq(@moontrace.Redact.to_string(), "REDACT")
  assert_eq(@moontrace.Drop.to_string(), "DROP")
  assert_eq("\{@moontrace.Redact}", "REDACT")
  assert_eq("\{@moontrace.Drop}", "DROP")
}

///|
test "default redaction policy redacts sensitive fields and preserves event shape" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("user", "ada".to_json()),
      ("user_password", "secret-password".to_json()),
      ("api_token", "token-value".to_json()),
      ("client_secret", "secret-value".to_json()),
      ("status", "denied".to_json()),
    ]),
  )

  let redacted = redaction_capture(event)

  assert_eq(redacted.level, @moontrace.Warn)
  assert_eq(redacted.message, "login attempt")
  assert_eq(redacted.timestamp, (12345 : UInt64))
  assert_eq(redacted.source, "brickfrog/moontrace")
  assert_eq(redacted.fields.length(), 5)
  assert_redaction_field(redacted, 0, "user", "ada".to_json())
  assert_redaction_field(redacted, 1, "user_password", "[REDACTED]".to_json())
  assert_redaction_field(redacted, 2, "api_token", "[REDACTED]".to_json())
  assert_redaction_field(redacted, 3, "client_secret", "[REDACTED]".to_json())
  assert_redaction_field(redacted, 4, "status", "denied".to_json())
}

///|
test "drop mode removes denied fields and preserves surviving order" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("user", "ada".to_json()),
      ("password", "secret-password".to_json()),
      ("action", "login".to_json()),
      ("session_token", "token-value".to_json()),
      ("status", "denied".to_json()),
    ]),
  )
  let policy = @moontrace.redaction_policy(mode=@moontrace.Drop)

  let redacted = redaction_capture(event, policy~)

  assert_eq(redacted.fields.length(), 3)
  assert_redaction_field(redacted, 0, "user", "ada".to_json())
  assert_redaction_field(redacted, 1, "action", "login".to_json())
  assert_redaction_field(redacted, 2, "status", "denied".to_json())
}

///|
test "allowlist mode redacts fields outside exact allowed keys" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("user", "ada".to_json()),
      ("role", "admin".to_json()),
      ("tenant", "prod".to_json()),
    ]),
  )
  let policy = @moontrace.redaction_policy(
    deny=[],
    allow=Some(["USER", "tenant"]),
    placeholder="<private>",
  )

  let redacted = redaction_capture(event, policy~)

  assert_eq(redacted.fields.length(), 3)
  assert_redaction_field(redacted, 0, "user", "ada".to_json())
  assert_redaction_field(redacted, 1, "role", "<private>".to_json())
  assert_redaction_field(redacted, 2, "tenant", "prod".to_json())
}

///|
test "allowlist drop mode omits fields outside exact allowed keys" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("user", "ada".to_json()),
      ("user_id", "u-1".to_json()),
      ("tenant", "prod".to_json()),
    ]),
  )
  let policy = @moontrace.redaction_policy(
    deny=[],
    allow=Some(["USER", "tenant"]),
    mode=@moontrace.Drop,
  )

  let redacted = redaction_capture(event, policy~)

  assert_eq(redacted.fields.length(), 2)
  assert_redaction_field(redacted, 0, "user", "ada".to_json())
  assert_redaction_field(redacted, 1, "tenant", "prod".to_json())
}

///|
test "redaction matching is case insensitive" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("Authorization", "bearer abc".to_json()),
      ("USER_TOKEN", "token-value".to_json()),
      ("safe", true.to_json()),
    ]),
  )
  let policy = @moontrace.redaction_policy(deny=["authorization", "token"])

  let redacted = redaction_capture(event, policy~)

  assert_redaction_field(redacted, 0, "Authorization", "[REDACTED]".to_json())
  assert_redaction_field(redacted, 1, "USER_TOKEN", "[REDACTED]".to_json())
  assert_redaction_field(redacted, 2, "safe", true.to_json())
}

///|
test "redacted event to_json includes placeholders and omits dropped fields" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("user", "ada".to_json()),
      ("password", "secret-password".to_json()),
      ("token", "token-value".to_json()),
    ]),
  )
  let redacted = redaction_capture(event)
  let drop_policy = @moontrace.redaction_policy(mode=@moontrace.Drop)
  let dropped = redaction_capture(event, policy=drop_policy)

  let redacted_root = redaction_json_object(redacted.to_json(), "event")
  let redacted_fields = redaction_json_object(
    redaction_json_field(redacted_root, "fields"),
    "event.fields",
  )
  assert_redaction_json_eq(
    redaction_json_field(redacted_fields, "password"),
    "[REDACTED]".to_json(),
  )
  assert_redaction_json_eq(
    redaction_json_field(redacted_fields, "token"),
    "[REDACTED]".to_json(),
  )

  let dropped_root = redaction_json_object(dropped.to_json(), "dropped event")
  let dropped_fields = redaction_json_object(
    redaction_json_field(dropped_root, "fields"),
    "dropped event.fields",
  )
  assert_redaction_json_eq(
    redaction_json_field(dropped_fields, "user"),
    "ada".to_json(),
  )
  assert_no_redaction_json_field(dropped_fields, "password")
  assert_no_redaction_json_field(dropped_fields, "token")
}

///|
test "redact is per subscriber and does not mutate the original event" {
  let original_fields = @moontrace.fields([
    ("user", "ada".to_json()),
    ("password", "secret-password".to_json()),
  ])
  let event = redaction_sample_event(original_fields)
  let redacted_seen : Array[@moontrace.Event] = []
  let original_seen : Array[@moontrace.Event] = []
  let subscriber = @moontrace.compose([
    @moontrace.redact(fn(e : @moontrace.Event) { redacted_seen.push(e) }),
    fn(e : @moontrace.Event) { original_seen.push(e) },
  ])

  subscriber(event)

  assert_eq(redacted_seen.length(), 1)
  assert_eq(original_seen.length(), 1)
  assert_redaction_field(redacted_seen[0], 0, "user", "ada".to_json())
  assert_redaction_field(
    redacted_seen[0],
    1,
    "password",
    "[REDACTED]".to_json(),
  )
  assert_redaction_field(original_seen[0], 0, "user", "ada".to_json())
  assert_redaction_field(
    original_seen[0],
    1,
    "password",
    "secret-password".to_json(),
  )
  assert_eq(event.fields.length(), 2)
  assert_redaction_field(event, 1, "password", "secret-password".to_json())
  assert_eq(original_fields.length(), 2)
  assert_eq(original_fields[1].key, "password")
  assert_redaction_json_eq(
    original_fields[1].value,
    "secret-password".to_json(),
  )
}
