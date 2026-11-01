///|
fn capture_events(f : () -> Unit raise) -> Array[@moontrace.Event] raise {
  let subscriber = @test.test_subscriber()
  subscriber.with_install(f)
  subscriber.captured_events()
}

///|
fn parse_ok(directive : String) -> @moontrace.ParsedFilter {
  match @moontrace.parse_env_filter(directive) {
    Ok(parsed) => parsed
    Err(err) => abort("\{err}")
  }
}

///|
test "off directives parse into silenced packages and a silenced default" {
  let parsed = parse_ok("info, my/app=OFF, my/app/db=debug")
  assert_false(parsed.default_off)
  assert_eq(parsed.silenced_modules, ["my/app"])
  assert_eq(parsed.module_filters.get("my/app/db"), Some(@moontrace.Debug))
  assert_true(parse_ok("Off").default_off)
  // The last directive for a target or the default wins.
  assert_false(parse_ok("off,warn").default_off)
  assert_true(parse_ok("warn,off").default_off)
  let replaced = parse_ok("my/app=off,my/app=warn")
  assert_eq(replaced.silenced_modules, [])
  assert_eq(replaced.module_filters.get("my/app"), Some(@moontrace.Warn))
  assert_eq(parse_ok("my/app=warn,my/app=off").silenced_modules, ["my/app"])
  assert_true(@moontrace.parse_env_filter("my/app=of") is Err(_))
}

///|
test "a silenced package emits nothing, even at Error" {
  let events = capture_events(() => {
    match
      @moontrace.set_filter_from_directives("trace,brickfrog/moontrace=off") {
      Ok(_) => ()
      Err(err) => abort("\{err}")
    }
    @moontrace.error("dropped")
    assert_false(@moontrace.enabled(@moontrace.Error_))
    assert_false(@moontrace.span("s", level=@moontrace.Error_).is_enabled())
  })
  assert_eq(events.length(), 0)
}

///|
test "a bare off silences everything except more specific packages" {
  let events = capture_events(() => {
    match
      @moontrace.set_filter_from_directives("off,brickfrog/moontrace=debug") {
      Ok(_) => ()
      Err(err) => abort("\{err}")
    }
    @moontrace.debug("kept")
    let span = @moontrace.span("unleveled")
    // Span lifecycle events have no package, so the silenced default drops them.
    span.enter()
    span.exit()
  })
  assert_eq(events.map(e => e.message), ["kept"])
}

///|
test "silence_all, set_min_level, and scoped state restore" {
  @moontrace.with_trace_state(() => {
    @moontrace.silence_all()
    let silenced = capture_events(() => @moontrace.error("dropped"))
    assert_eq(silenced.length(), 0)
  })
  let restored = capture_events(() => @moontrace.info("after scope"))
  assert_eq(restored.length(), 1)
  let reset = capture_events(() => {
    @moontrace.silence_all()
    @moontrace.set_min_level(@moontrace.Info)
    @moontrace.info("back on")
  })
  assert_eq(reset.length(), 1)
}

///|
test "with_directives honors off for one subscriber" {
  let seen : Array[String] = []
  let filtered = @moontrace.with_directives(
    event => seen.push(event.message),
    parse_ok("off,keep/me=info"),
  )
  let event = (source : String) => @moontrace.Event::{
    level: @moontrace.Error_,
    message: source,
    fields: [],
    timestamp: 0UL,
    source,
    file: "",
    line: 0,
  }
  filtered(event("keep/me/sub"))
  filtered(event("other/pkg"))
  let silenced_pkg = @moontrace.with_directives(
    event => seen.push("pkg:" + event.message),
    parse_ok("trace,other/pkg=off"),
  )
  silenced_pkg(event("other/pkg"))
  silenced_pkg(event("keep/me"))
  assert_eq(seen, ["keep/me/sub", "pkg:keep/me"])
}
