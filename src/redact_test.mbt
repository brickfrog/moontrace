///|
fn redaction_sample_event(fields : Array[@moontrace.Field]) -> @moontrace.Event {
  @moontrace.Event::{
    level: @moontrace.Warn,
    message: "login attempt",
    fields,
    timestamp: (12345 : UInt64),
    source: "brickfrog/moontrace",
    file: "",
    line: 0,
  }
}

///|
fn redaction_capture(
  event : @moontrace.Event,
  policy~ : @moontrace.RedactionPolicy = @moontrace.default_redaction_policy(),
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
  index : Int32,
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
      ("user", Json("ada")),
      ("user_password", Json("secret-password")),
      ("api_token", Json("token-value")),
      ("client_secret", Json("secret-value")),
      ("status", Json("denied")),
    ]),
  )

  let redacted = redaction_capture(event)

  assert_eq(redacted.level, @moontrace.Warn)
  assert_eq(redacted.message, "login attempt")
  assert_eq(redacted.timestamp, (12345 : UInt64))
  assert_eq(redacted.source, "brickfrog/moontrace")
  assert_eq(redacted.fields.length(), 5)
  assert_redaction_field(redacted, 0, "user", Json("ada"))
  assert_redaction_field(redacted, 1, "user_password", Json("[REDACTED]"))
  assert_redaction_field(redacted, 2, "api_token", Json("[REDACTED]"))
  assert_redaction_field(redacted, 3, "client_secret", Json("[REDACTED]"))
  assert_redaction_field(redacted, 4, "status", Json("denied"))
}

///|
test "drop mode removes denied fields and preserves surviving order" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("user", Json("ada")),
      ("password", Json("secret-password")),
      ("action", Json("login")),
      ("session_token", Json("token-value")),
      ("status", Json("denied")),
    ]),
  )
  let policy = @moontrace.redaction_policy(mode=@moontrace.Drop)

  let redacted = redaction_capture(event, policy~)

  assert_eq(redacted.fields.length(), 3)
  assert_redaction_field(redacted, 0, "user", Json("ada"))
  assert_redaction_field(redacted, 1, "action", Json("login"))
  assert_redaction_field(redacted, 2, "status", Json("denied"))
}

///|
test "allowlist mode redacts fields outside exact allowed keys" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("user", Json("ada")),
      ("role", Json("admin")),
      ("tenant", Json("prod")),
    ]),
  )
  let policy = @moontrace.redaction_policy(
    deny=[],
    allow=Some(["USER", "tenant"]),
    placeholder="<private>",
  )

  let redacted = redaction_capture(event, policy~)

  assert_eq(redacted.fields.length(), 3)
  assert_redaction_field(redacted, 0, "user", Json("ada"))
  assert_redaction_field(redacted, 1, "role", Json("<private>"))
  assert_redaction_field(redacted, 2, "tenant", Json("prod"))
}

///|
test "allowlist drop mode omits fields outside exact allowed keys" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("user", Json("ada")),
      ("user_id", Json("u-1")),
      ("tenant", Json("prod")),
    ]),
  )
  let policy = @moontrace.redaction_policy(
    deny=[],
    allow=Some(["USER", "tenant"]),
    mode=@moontrace.Drop,
  )

  let redacted = redaction_capture(event, policy~)

  assert_eq(redacted.fields.length(), 2)
  assert_redaction_field(redacted, 0, "user", Json("ada"))
  assert_redaction_field(redacted, 1, "tenant", Json("prod"))
}

///|
test "redaction matching is case insensitive" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("Authorization", Json("bearer abc")),
      ("USER_TOKEN", Json("token-value")),
      ("safe", Json(true)),
    ]),
  )
  let policy = @moontrace.redaction_policy(deny=["authorization", "token"])

  let redacted = redaction_capture(event, policy~)

  assert_redaction_field(redacted, 0, "Authorization", Json("[REDACTED]"))
  assert_redaction_field(redacted, 1, "USER_TOKEN", Json("[REDACTED]"))
  assert_redaction_field(redacted, 2, "safe", Json(true))
}

///|
test "redacted event to_json includes placeholders and omits dropped fields" {
  let event = redaction_sample_event(
    @moontrace.fields([
      ("user", Json("ada")),
      ("password", Json("secret-password")),
      ("token", Json("token-value")),
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
    Json("[REDACTED]"),
  )
  assert_redaction_json_eq(
    redaction_json_field(redacted_fields, "token"),
    Json("[REDACTED]"),
  )

  let dropped_root = redaction_json_object(dropped.to_json(), "dropped event")
  let dropped_fields = redaction_json_object(
    redaction_json_field(dropped_root, "fields"),
    "dropped event.fields",
  )
  assert_redaction_json_eq(
    redaction_json_field(dropped_fields, "user"),
    Json("ada"),
  )
  assert_no_redaction_json_field(dropped_fields, "password")
  assert_no_redaction_json_field(dropped_fields, "token")
}

///|
test "redact is per subscriber and does not mutate the original event" {
  let original_fields = @moontrace.fields([
    ("user", Json("ada")),
    ("password", Json("secret-password")),
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
  assert_redaction_field(redacted_seen[0], 0, "user", Json("ada"))
  assert_redaction_field(redacted_seen[0], 1, "password", Json("[REDACTED]"))
  assert_redaction_field(original_seen[0], 0, "user", Json("ada"))
  assert_redaction_field(
    original_seen[0],
    1,
    "password",
    Json("secret-password"),
  )
  assert_eq(event.fields.length(), 2)
  assert_redaction_field(event, 1, "password", Json("secret-password"))
  assert_eq(original_fields.length(), 2)
  assert_eq(original_fields[1].key, "password")
  assert_redaction_json_eq(original_fields[1].value, Json("secret-password"))
}

///|
test "redact replaces denied keys inside nested objects and arrays" {
  let request : Map[String, Json] = Map([
    ("method", Json("POST")),
    ("headers", Json(Map([("authorization_token", Json("Bearer abc"))]))),
    (
      "credentials",
      Json([Json(Map([("user", Json("ana")), ("password", Json("pw"))]))]),
    ),
  ])
  let event = redaction_capture(
    redaction_sample_event([@moontrace.field("request", Json(request))]),
  )
  assert_redaction_field(
    event,
    0,
    "request",
    Json(
      Map([
        ("method", Json("POST")),
        ("headers", Json(Map([("authorization_token", Json("[REDACTED]"))]))),
        (
          "credentials",
          Json([
            Json(Map([("user", Json("ana")), ("password", Json("[REDACTED]"))])),
          ]),
        ),
      ]),
    ),
  )
}

///|
test "redact drop mode removes denied nested keys" {
  let policy = @moontrace.redaction_policy(mode=@moontrace.Drop)
  let auth : Map[String, Json] = Map([
    ("token", Json("abc")),
    ("scheme", Json("bearer")),
  ])
  let event = redaction_capture(
    redaction_sample_event([
      @moontrace.field("auth", Json(Map([("inner", Json(auth))]))),
    ]),
    policy~,
  )
  assert_redaction_field(
    event,
    0,
    "auth",
    Json(Map([("inner", Json(Map([("scheme", Json("bearer"))])))])),
  )
}

///|
test "redact leaves nested scalars and allow-listed fields unchanged" {
  let nested = Json(Map([("password", Json("pw")), ("count", Json(2))]))
  let allow_policy = @moontrace.redaction_policy(allow=Some(["profile"]))
  let allowed = redaction_capture(
    redaction_sample_event([@moontrace.field("profile", nested)]),
    policy=allow_policy,
  )
  assert_redaction_field(allowed, 0, "profile", nested)

  let scalars = redaction_capture(
    redaction_sample_event([
      @moontrace.field("items", Json([Json(1), Json("two"), Json(true)])),
    ]),
  )
  assert_redaction_field(
    scalars,
    0,
    "items",
    Json([Json(1), Json("two"), Json(true)]),
  )
}
