///|
fn logfmt_event(
  fields~ : Array[@moontrace.Field] = [],
  message~ : String = "server started",
  source~ : String = "brickfrog/choir",
  file~ : String = "src/server/main.mbt",
) -> @moontrace.Event {
  @moontrace.Event::{
    level: @moontrace.Info,
    message,
    fields,
    timestamp: 1774708303903UL,
    source,
    file,
    line: 42,
  }
}

///|
test "logfmt formats a standard record" {
  assert_eq(
    @logfmt.format_event(
      logfmt_event(fields=[
        @moontrace.field("port", 8080),
        @moontrace.field("service", "choir"),
        @moontrace.field("ok", true),
      ]),
    ),
    "ts=2026-03-28T14:31:43.903Z level=info msg=\"server started\" source=brickfrog/choir caller=src/server/main.mbt:42 port=8080 service=choir ok=true",
  )
}

///|
test "logfmt omits missing source and caller" {
  assert_eq(
    @logfmt.format_event(logfmt_event(message="tick", source="", file="")),
    "ts=2026-03-28T14:31:43.903Z level=info msg=tick",
  )
}

///|
test "logfmt quotes and escapes values" {
  assert_eq(
    @logfmt.format_event(
      logfmt_event(message="", source="", file="", fields=[
        @moontrace.field("empty", ""),
        @moontrace.field("eq", "a=b"),
        @moontrace.field("quote", "say \"hi\""),
        @moontrace.field("lines", "a\nb\tc"),
        @moontrace.field("bell", "x\u{0007}"),
        @moontrace.field("path", "C:\\tmp"),
        @moontrace.field("obj", { "a": [1, 2] }),
        @moontrace.field("none", Json::null()),
      ]),
    ),
    "ts=2026-03-28T14:31:43.903Z level=info msg=\"\" empty=\"\" eq=\"a=b\" quote=\"say \\\"hi\\\"\" lines=\"a\\nb\\tc\" bell=\"x\\u0007\" path=C:\\tmp obj=\"{\\\"a\\\":[1,2]}\" none=null",
  )
}

///|
test "logfmt sanitizes keys and prefixes reserved keys" {
  assert_eq(
    @logfmt.format_event(
      logfmt_event(message="m", source="", file="", fields=[
        @moontrace.field("user name", "ann"),
        @moontrace.field("a=b", 1),
        @moontrace.field("", 2),
        @moontrace.field("level", "custom"),
        @moontrace.field("msg", "other"),
      ]),
    ),
    "ts=2026-03-28T14:31:43.903Z level=info msg=m user_name=ann a_b=1 _=2 fields.level=custom fields.msg=other",
  )
}

///|
test "logfmt subscriber filters by level and uses timestamp hook" {
  let output : Array[String] = []
  let subscriber = @logfmt.subscriber(
    min_level=@moontrace.Warn,
    output=line => output.push(line),
    format_timestamp=_ => "T",
  )
  subscriber(logfmt_event())
  subscriber({
    ..logfmt_event(message="disk", source="", file=""),
    level: @moontrace.Error_,
  })
  assert_eq(output, ["ts=T level=error msg=disk"])
}
