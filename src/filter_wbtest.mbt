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
