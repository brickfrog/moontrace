///|
test "compose fans out to multiple subscribers" {
  let a : Array[String] = []
  let b : Array[String] = []
  let sub1 = fn(e : @moontrace.Event) { a.push(e.message) }
  let sub2 = fn(e : @moontrace.Event) { b.push(e.message) }
  @moontrace.set_subscriber(@moontrace.compose([sub1, sub2]))
  @moontrace.info("hello")
  assert_eq(a.length(), 1)
  assert_eq(b.length(), 1)
  assert_eq(a[0], "hello")
  assert_eq(b[0], "hello")
  @moontrace.clear_subscriber()
}

///|
test "compose with empty array does not crash" {
  @moontrace.set_subscriber(@moontrace.compose([]))
  @moontrace.info("noop")
  @moontrace.clear_subscriber()
}

///|
test "with_filter blocks events below min_level" {
  let captured : Array[String] = []
  let sub = fn(e : @moontrace.Event) { captured.push(e.message) }
  @moontrace.set_subscriber(@moontrace.with_filter(sub, @moontrace.Warn))
  @moontrace.debug("skip")
  @moontrace.info("skip")
  @moontrace.warn("keep1")
  @moontrace.error("keep2")
  assert_eq(captured.length(), 2)
  assert_eq(captured[0], "keep1")
  assert_eq(captured[1], "keep2")
  @moontrace.clear_subscriber()
}

///|
test "compose with with_filter" {
  let all_events : Array[String] = []
  let errors_only : Array[String] = []
  let sub_all = fn(e : @moontrace.Event) { all_events.push(e.message) }
  let sub_errors = fn(e : @moontrace.Event) { errors_only.push(e.message) }
  @moontrace.set_subscriber(
    @moontrace.compose([
      sub_all,
      @moontrace.with_filter(sub_errors, @moontrace.Error_),
    ]),
  )
  @moontrace.info("i")
  @moontrace.error("e")
  assert_eq(all_events.length(), 2)
  assert_eq(errors_only.length(), 1)
  assert_eq(errors_only[0], "e")
  @moontrace.clear_subscriber()
}

///|
fn combinator_event(
  level : @moontrace.Level,
  source : String,
  fields : Array[@moontrace.Field],
) -> @moontrace.Event {
  @moontrace.Event::{
    level,
    message: "m",
    fields,
    timestamp: (1 : UInt64),
    source,
  }
}

///|
test "map_events transforms or drops events for one subscriber" {
  let mapped : Array[@moontrace.Event] = []
  let original : Array[@moontrace.Event] = []
  let sub = @moontrace.compose([
    @moontrace.map_events(e => mapped.push(e), e => {
      if e.level == @moontrace.Debug {
        None
      } else {
        Some({ ..e, message: "rewritten", })
      }
    }),
    e => original.push(e),
  ])
  sub(combinator_event(@moontrace.Info, "a", []))
  sub(combinator_event(@moontrace.Debug, "a", []))
  assert_eq(mapped.map(e => e.message), ["rewritten"])
  assert_eq(original.map(e => e.message), ["m", "m"])
}

///|
test "filter_events forwards only matching events" {
  let seen : Array[@moontrace.Event] = []
  let sub = @moontrace.filter_events(e => seen.push(e), e => e.source == "keep")
  sub(combinator_event(@moontrace.Info, "keep", []))
  sub(combinator_event(@moontrace.Info, "drop", []))
  assert_eq(seen.map(e => e.source), ["keep"])
}

///|
test "enrich adds computed fields and event fields win" {
  let seen : Array[@moontrace.Event] = []
  let sub = @moontrace.enrich(e => seen.push(e), e => {
    [
      @moontrace.field("host", "h1"),
      @moontrace.field("level_name", e.level.to_string()),
      @moontrace.field("user", "computed"),
      @moontrace.field("host", "h2"),
    ]
  })
  let event = combinator_event(@moontrace.Warn, "a", [
    @moontrace.field("user", "explicit"),
  ])
  sub(event)
  assert_eq(seen[0].fields.map(f => f.key), ["host", "level_name", "user"])
  assert_eq(seen[0].fields.map(f => f.value), [
    Json("h2"),
    Json("WARN"),
    Json("explicit"),
  ])
  assert_eq(event.fields.length(), 1)
}

///|
test "with_directives filters one subscriber by package prefix" {
  let filter = match
    @moontrace.parse_env_filter("warn,my/app=debug,my/app/db=error") {
    Ok(filter) => filter
    Err(err) => abort("unexpected directive error: \{err}")
  }
  let seen : Array[@moontrace.Event] = []
  let sub = @moontrace.with_directives(e => seen.push(e), filter)
  filter.module_filters.set("my/other", @moontrace.Trace)
  sub(combinator_event(@moontrace.Debug, "my/app/http", []))
  sub(combinator_event(@moontrace.Warn, "my/app/db/pool", []))
  sub(combinator_event(@moontrace.Error_, "my/app/db", []))
  sub(combinator_event(@moontrace.Info, "my/other", []))
  sub(combinator_event(@moontrace.Warn, "", []))
  assert_eq(seen.map(e => e.source), ["my/app/http", "my/app/db", ""])
}
