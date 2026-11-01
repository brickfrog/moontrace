///|
test "render_template substitutes fields and keeps unknown placeholders" {
  let fields = [
    @moontrace.field("user", "ann"),
    @moontrace.field("count", 3),
    @moontrace.field("tags", ["a", "b"]),
    @moontrace.field("user", "bob"),
  ]
  assert_eq(
    @moontrace.render_template(
      "{user} has {count} items {tags}; {missing} {} {{literal}} }}{", fields,
    ),
    "bob has 3 items [\"a\",\"b\"]; {missing} {} {literal} }{",
  )
  assert_eq(
    @moontrace.render_template("no placeholders", []),
    "no placeholders",
  )
  assert_eq(
    @moontrace.render_template("{a{b}", [@moontrace.field("b", 1)]),
    "{a1",
  )
}

///|
test "log_template renders the message and keeps a stable template field" {
  let span = @moontrace.span("op")
  let events = @test.capture(() => {
    @moontrace.log_template(@moontrace.Info, "user {id} logged in", fields=[
      @moontrace.field("id", 7),
      @moontrace.field("message_template", "spoofed"),
    ])
    @moontrace.log_template(
      @moontrace.Warn,
      "slow {ms}ms",
      fields=[@moontrace.field("ms", 900)],
      span~,
    )
  })
  assert_eq(events.map(e => e.message), ["user 7 logged in", "slow 900ms"])
  let templates = events.map(e => {
    let found = e.fields.filter(f => f.key == "message_template")
    assert_eq(found.length(), 1)
    found[0].value
  })
  assert_eq(templates, [Json("user {id} logged in"), Json("slow {ms}ms")])
  assert_true(events[1].fields.iter().any(f => f.key == "trace_id"))
  assert_eq(events[0].file, "src/template_test.mbt")
}

///|
test "log_template skips rendering when filtered" {
  let events = @test.capture(() => {
    @moontrace.set_min_level(@moontrace.Warn)
    @moontrace.log_template(@moontrace.Info, "hidden {x}", fields=[
      @moontrace.field("x", 1),
    ])
  })
  assert_eq(events.length(), 0)
}

///|
test "Logger::log_template uses bound fields for rendering" {
  let events = @test.capture(() => {
    let log = @moontrace.logger(fields=[@moontrace.field("job", "sync")])
    log.log_template(@moontrace.Info, "{job} handled {n}", fields=[
      @moontrace.field("n", 2),
    ])
    let quiet = log.with_min_level(@moontrace.Error_)
    quiet.log_template(@moontrace.Info, "dropped {job}")
  })
  assert_eq(events.map(e => e.message), ["sync handled 2"])
  assert_true(events[0].fields.iter().any(f => f.key == "job"))
}

///|
test "reloadable handles swap the target subscriber" {
  let first : Array[String] = []
  let second : Array[String] = []
  let handle = @moontrace.reloadable(e => first.push(e.message))
  let other : Array[String] = []
  @moontrace.with_subscriber(
    @moontrace.compose([handle.subscriber(), e => other.push(e.message)]),
    () => {
      @moontrace.info("a")
      handle.reload(e => second.push(e.message))
      @moontrace.info("b")
    },
  )
  assert_eq(first, ["a"])
  assert_eq(second, ["b"])
  assert_eq(other, ["a", "b"])
}
