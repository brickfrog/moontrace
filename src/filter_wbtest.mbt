///|
test "effective_min uses verbose module override" {
  with_trace_state(() => {
    set_min_level(Info)
    set_module_filter("brickfrog/moontrace", Debug)
    assert_eq(effective_min("brickfrog/moontrace"), Debug)
    assert_true(should_log_module("brickfrog/moontrace", Debug))
  })
}

///|
test "effective_min uses stricter module override" {
  with_trace_state(() => {
    set_min_level(Trace)
    set_module_filter("brickfrog/moontrace", Warn)
    assert_eq(effective_min("brickfrog/moontrace"), Warn)
    assert_true(!should_log_module("brickfrog/moontrace", Info))
  })
}

///|
test "effective_min falls back to global for unmatched source" {
  with_trace_state(() => {
    set_min_level(Info)
    set_module_filter("brickfrog/moontrace", Debug)
    assert_eq(effective_min("other/package"), Info)
    assert_true(!should_log_module("other/package", Debug))
    assert_true(should_log_module("other/package", Info))
  })
}

///|
test "module filters apply to subpackages" {
  with_trace_state(() => {
    set_min_level(Info)
    set_module_filter("my/app", Debug)
    assert_eq(effective_min("my/app"), Debug)
    assert_eq(effective_min("my/app/db"), Debug)
    assert_eq(effective_min("my/app/db/pool"), Debug)
  })
}

///|
test "module filter prefixes match whole package segments only" {
  with_trace_state(() => {
    set_min_level(Info)
    set_module_filter("my/app", Debug)
    assert_eq(effective_min("my/apple"), Info)
    assert_eq(effective_min("my"), Info)
    assert_eq(effective_min("other/my/app"), Info)
  })
}

///|
test "longest matching module filter wins" {
  with_trace_state(() => {
    set_min_level(Info)
    set_module_filter("my/app", Debug)
    set_module_filter("my/app/db", Warn)
    assert_eq(effective_min("my/app"), Debug)
    assert_eq(effective_min("my/app/http"), Debug)
    assert_eq(effective_min("my/app/db"), Warn)
    assert_eq(effective_min("my/app/db/pool"), Warn)
  })
}

///|
test "env directives apply to subpackages" {
  with_trace_state(() => {
    match set_filter_from_directives("warn,my/app=trace,my/app/noisy=error") {
      Ok(_) => ()
      Err(err) => abort("unexpected directive error: \{err}")
    }
    assert_eq(effective_min("my/app/db"), Trace)
    assert_eq(effective_min("my/app/noisy/inner"), Error_)
    assert_eq(effective_min("my/other"), Warn)
  })
}
