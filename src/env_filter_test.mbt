///|
fn must_parse_env_filter(directive : String) -> @moontrace.ParsedFilter {
  match @moontrace.parse_env_filter(directive) {
    Ok(parsed) => parsed
    Err(err) => abort("expected parsed env filter, got \{err}")
  }
}

///|
fn assert_set_filter_ok(directive : String) -> Unit {
  match @moontrace.set_filter_from_directives(directive) {
    Ok(_) => ()
    Err(err) => abort("expected filter apply ok, got \{err}")
  }
}

///|
fn unique_env_filter_key(label : String) -> String {
  "__MOONTRACE_ENV_FILTER_TEST_" + label + "_" + @env.now().to_string()
}

///|
test "parse default-only directive" {
  let parsed = must_parse_env_filter("info")
  assert_eq(parsed.default_level, @moontrace.Info)
  assert_true(parsed.module_filters.is_empty())
}

///|
test "parse package-specific directive" {
  let parsed = must_parse_env_filter("info,foo=debug")
  assert_eq(parsed.default_level, @moontrace.Info)
  assert_true(parsed.module_filters.get("foo") == Some(@moontrace.Debug))
}

///|
test "parse uses info fallback without bare default" {
  let parsed = must_parse_env_filter("foo=debug")
  assert_eq(parsed.default_level, @moontrace.Info)
  assert_true(parsed.module_filters.get("foo") == Some(@moontrace.Debug))
}

///|
test "parse repeated directives last wins" {
  let parsed = must_parse_env_filter("warn,foo=error,debug,foo=trace")
  assert_eq(parsed.default_level, @moontrace.Debug)
  assert_true(parsed.module_filters.get("foo") == Some(@moontrace.Trace))
}

///|
test "parse invalid package level returns structured error" {
  match @moontrace.parse_env_filter("info,foo=bogus") {
    Err(@moontrace.InvalidLevel(level)) => assert_eq(level, "bogus")
    Ok(_) => abort("expected invalid level error")
    Err(err) => abort("expected InvalidLevel, got \{err}")
  }
}

///|
test "parse malformed directive returns structured error" {
  match @moontrace.parse_env_filter("foo=bar=baz") {
    Err(@moontrace.MalformedDirective(directive)) =>
      assert_eq(directive, "foo=bar=baz")
    Ok(_) => abort("expected malformed directive error")
    Err(err) => abort("expected MalformedDirective, got \{err}")
  }
}

///|
test "parse trims whitespace around directives" {
  let parsed = must_parse_env_filter(" info , foo = debug ")
  assert_eq(parsed.default_level, @moontrace.Info)
  assert_true(parsed.module_filters.get("foo") == Some(@moontrace.Debug))
}

///|
test "parse skips empty directives" {
  let parsed = must_parse_env_filter(",,info,,")
  assert_eq(parsed.default_level, @moontrace.Info)
  assert_true(parsed.module_filters.is_empty())
}

///|
test "apply replaces filter state and source package matches parent package" {
  let capture = @test.test_subscriber()
  capture.with_install(() => {
    assert_set_filter_ok("trace,brickfrog/moontrace=warn")
    @moontrace.debug("blocked by package filter")
    @moontrace.warn("allowed by package filter")
    let events = capture.captured_events()
    assert_eq(events.length(), 1)
    assert_eq(events[0].level, @moontrace.Warn)
    assert_eq(events[0].message, "allowed by package filter")
    assert_eq(events[0].source, "brickfrog/moontrace")
  })
}

///|
test "apply clears stale module filters" {
  let capture = @test.test_subscriber()
  capture.with_install(() => {
    @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Error_)
    assert_set_filter_ok("trace")
    @moontrace.debug("allowed after stale filter cleared")
    let events = capture.captured_events()
    assert_eq(events.length(), 1)
    assert_eq(events[0].level, @moontrace.Debug)
  })
}

///|
test "initialize_from_env no-ops for unset variable" {
  let key = unique_env_filter_key("UNSET")
  @env.unset_env_var(key)
  @moontrace.with_trace_state(() => {
    @moontrace.set_min_level(@moontrace.Warn)
    match @moontrace.initialize_from_env(env_var=key) {
      Ok(_) => ()
      Err(err) => abort("expected unset env init ok, got \{err}")
    }
    assert_eq(@moontrace.get_min_level(), @moontrace.Warn)
  })
}

///|
test "initialize_from_env no-ops for empty variable" {
  let key = unique_env_filter_key("EMPTY")
  @env.set_env_var(key, " \t\r\n")
  @moontrace.with_trace_state(() => {
    @moontrace.set_min_level(@moontrace.Warn)
    match @moontrace.initialize_from_env(env_var=key) {
      Ok(_) => ()
      Err(err) => abort("expected empty env init ok, got \{err}")
    }
    assert_eq(@moontrace.get_min_level(), @moontrace.Warn)
  })
  @env.unset_env_var(key)
}

///|
test "initialize_from_env applies present variable" {
  let key = unique_env_filter_key("PRESENT")
  @env.set_env_var(key, "error")
  @moontrace.with_trace_state(() => {
    @moontrace.set_min_level(@moontrace.Trace)
    match @moontrace.initialize_from_env(env_var=key) {
      Ok(_) => ()
      Err(err) => abort("expected present env init ok, got \{err}")
    }
    assert_eq(@moontrace.get_min_level(), @moontrace.Error_)
  })
  @env.unset_env_var(key)
}

///|
test "initialize_from_env returns invalid present variable without applying" {
  let key = unique_env_filter_key("INVALID")
  @env.set_env_var(key, "bogus")
  @moontrace.with_trace_state(() => {
    @moontrace.set_min_level(@moontrace.Warn)
    match @moontrace.initialize_from_env(env_var=key) {
      Err(@moontrace.InvalidLevel(level)) => assert_eq(level, "bogus")
      Ok(_) => abort("expected invalid env init error")
      Err(err) => abort("expected InvalidLevel, got \{err}")
    }
    assert_eq(@moontrace.get_min_level(), @moontrace.Warn)
  })
  @env.unset_env_var(key)
}
