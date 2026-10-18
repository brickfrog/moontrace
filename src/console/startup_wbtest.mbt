///|
fn expect_startup_ok(result : Result[Unit, @moontrace.EnvFilterError]) -> Unit {
  match result {
    Ok(_) => ()
    Err(err) => abort("unexpected startup error: \{err}")
  }
}

///|
test "startup defaults replace stale filters with Info" {
  for directive in [None, Some(""), Some(" \t\r\n")] {
    @moontrace.with_trace_state(() => {
      let lines : Array[String] = []
      @moontrace.set_min_level(@moontrace.Error_)
      @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Error_)
      expect_startup_ok(
        configure_startup(
          _ => directive,
          () => false,
          "TEST_LOG",
          None,
          Some(line => lines.push(line)),
        ),
      )
      assert_eq(@moontrace.get_min_level(), @moontrace.Info)
      @moontrace.debug("hidden")
      @moontrace.info("visible")
      assert_eq(lines.length(), 1)
      assert_true(lines[0].contains("visible"))
      assert_false(lines[0].contains("\u{1b}"))
    })
  }
}

///|
test "startup honors verbose exact-package override and last directive" {
  @moontrace.with_trace_state(() => {
    let lines : Array[String] = []
    expect_startup_ok(
      configure_startup(
        key => {
          if key == "CUSTOM_LOG" {
            Some(
              "error,warn,brickfrog/moontrace=error,brickfrog/moontrace=debug",
            )
          } else {
            None
          }
        },
        () => false,
        "CUSTOM_LOG",
        None,
        Some(line => lines.push(line)),
      ),
    )
    assert_eq(@moontrace.get_min_level(), @moontrace.Warn)
    @moontrace.trace("hidden")
    @moontrace.debug("package debug")
    assert_eq(lines.length(), 1)
    assert_true(lines[0].contains("package debug"))
  })
}

///|
test "invalid startup leaves subscriber filters context and observer intact" {
  for directive in ["trace,bogus", "trace,=debug"] {
    @moontrace.with_trace_state(() => {
      let previous : Array[@moontrace.Event] = []
      let replacement : Array[String] = []
      let closed : Array[@moontrace.Span] = []
      @moontrace.set_subscriber(e => previous.push(e))
      @moontrace.set_min_level(@moontrace.Error_)
      @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Debug)
      @moontrace.set_global_field("existing", true)
      @moontrace.set_span_observer(
        @moontrace.completed_span_observer(s => closed.push(s)),
      )
      let reads : Array[String] = []
      let result = configure_startup(
        key => {
          reads.push(key)
          Some(directive)
        },
        () => abort("invalid filter must not inspect terminal"),
        "TEST_LOG",
        None,
        Some(line => replacement.push(line)),
      )
      assert_true(result is Err(_))
      assert_eq(reads, ["TEST_LOG"])
      assert_eq(@moontrace.get_min_level(), @moontrace.Error_)
      @moontrace.debug("old subscriber")
      assert_eq(previous.length(), 1)
      assert_true(
        previous[0].fields.any(f => f.key == "existing" && f.value == Json(true)),
      )
      assert_eq(replacement.length(), 0)
      @moontrace.with_span("observer", () => ())
      assert_eq(closed.length(), 1)
    })
  }
}

///|
test "startup color is explicit then environment then terminal" {
  let no_env = fn(_key : String) -> String? { None }
  let disabled = fn(key : String) -> String? {
    if key == "NO_COLOR" {
      Some("1")
    } else {
      Some("dumb")
    }
  }
  assert_true(startup_color(Some(true), true, disabled, () => false))
  assert_false(startup_color(Some(false), false, no_env, () => true))
  assert_true(startup_color(None, false, no_env, () => true))
  assert_false(startup_color(None, false, no_env, () => false))
  assert_false(startup_color(None, true, no_env, () => true))
  assert_false(startup_color(None, false, disabled, () => true))
  assert_false(
    startup_color(
      None,
      false,
      key => if key == "TERM" { Some("dumb") } else { None },
      () => true,
    ),
  )
  assert_false(
    startup_color(
      None,
      false,
      key => if key == "NO_COLOR" { Some(" ") } else { None },
      () => true,
    ),
  )
  assert_true(startup_color(None, false, _ => Some(""), () => true))
}

///|
test "startup custom output can explicitly request ANSI" {
  @moontrace.with_trace_state(() => {
    let lines : Array[String] = []
    expect_startup_ok(
      configure_startup(
        _ => None,
        () => false,
        "TEST_LOG",
        Some(true),
        Some(line => lines.push(line)),
      ),
    )
    @moontrace.info("colored")
    assert_eq(lines.length(), 1)
    assert_true(lines[0].contains("\u{1b}["))
  })
}

///|
test "repeated startup replaces subscriber and filters" {
  @moontrace.with_trace_state(() => {
    let first : Array[String] = []
    let second : Array[String] = []
    expect_startup_ok(
      configure_startup(
        _ => Some("debug"),
        () => false,
        "TEST_LOG",
        None,
        Some(line => first.push(line)),
      ),
    )
    expect_startup_ok(
      configure_startup(
        _ => Some("warn"),
        () => false,
        "TEST_LOG",
        None,
        Some(line => second.push(line)),
      ),
    )
    @moontrace.info("hidden")
    @moontrace.warn("second only")
    assert_eq(first.length(), 0)
    assert_eq(second.length(), 1)
    assert_true(second[0].contains("second only"))
  })
}
