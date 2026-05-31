///|
suberror ScopedFailure

///|
fn has_field(event : @moontrace.Event, key : String) -> Bool {
  let mut found = false
  event.fields.each(fn(field) { if field.key == key { found = true } })
  found
}

///|
fn assert_field(event : @moontrace.Event, key : String, value : Json) -> Unit {
  let mut found : Json? = None
  event.fields.each(fn(field) {
    if field.key == key {
      found = Some(field.value)
    }
  })
  match found {
    Some(actual) =>
      if actual.stringify() != value.stringify() {
        abort("field " + key + " did not match expected value")
      }
    None => abort("expected field " + key)
  }
}

///|
fn reset_trace_state() -> Unit {
  @moontrace.clear_subscriber()
  @moontrace.set_min_level(@moontrace.Trace)
  @moontrace.clear_global_fields()
  @moontrace.clear_module_filters()
}

///|
test "with_trace_state restores all globals after normal return" {
  reset_trace_state()
  let base_events = []
  let inner_events = []
  @moontrace.set_subscriber(fn(event) { base_events.push(event) })
  @moontrace.set_min_level(@moontrace.Warn)
  @moontrace.set_global_field("scope", "base")
  @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Error_)

  let result = @moontrace.with_trace_state(fn() {
    @moontrace.set_subscriber(fn(event) { inner_events.push(event) })
    @moontrace.set_min_level(@moontrace.Trace)
    @moontrace.set_global_field("scope", "inner")
    @moontrace.set_global_field("inner_only", "yes")
    @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Trace)
    @moontrace.info("inside")
    7
  })

  assert_eq(result, 7)
  @moontrace.info("blocked after scope")
  @moontrace.warn("blocked by restored module filter")
  @moontrace.error("after scope")

  assert_eq(@moontrace.get_min_level(), @moontrace.Warn)
  assert_eq(inner_events.length(), 1)
  assert_eq(inner_events[0].message, "inside")
  assert_field(inner_events[0], "scope", "inner".to_json())
  assert_eq(has_field(inner_events[0], "inner_only"), true)

  assert_eq(base_events.length(), 1)
  assert_eq(base_events[0].message, "after scope")
  assert_field(base_events[0], "scope", "base".to_json())
  assert_eq(has_field(base_events[0], "inner_only"), false)
  reset_trace_state()
}

///|
test "scoped helpers restore nested state in LIFO order" {
  reset_trace_state()
  let captured = []

  @moontrace.with_subscriber(fn(event) { captured.push(event) }, fn() {
    @moontrace.with_min_level(@moontrace.Trace, fn() {
      @moontrace.with_global_field("scope", "outer", fn() {
        @moontrace.with_module_filter("brickfrog/moontrace", @moontrace.Warn, fn() {
          @moontrace.warn("outer before")
          @moontrace.with_global_fields([@moontrace.field("scope", "inner")], fn() {
            @moontrace.with_module_filter(
              "brickfrog/moontrace",
              @moontrace.Trace,
              fn() { @moontrace.debug("inner") },
            )
          })
          @moontrace.with_min_level(@moontrace.Error_, fn() {
            @moontrace.warn("allowed by module override")
          })
          @moontrace.debug("blocked after inner filter")
          @moontrace.warn("outer after")
        })
      })
    })
  })

  @moontrace.warn("after all scopes")

  assert_eq(captured.length(), 4)
  assert_eq(captured[0].message, "outer before")
  assert_eq(captured[1].message, "inner")
  assert_eq(captured[2].message, "allowed by module override")
  assert_eq(captured[3].message, "outer after")
  assert_field(captured[0], "scope", "outer".to_json())
  assert_field(captured[1], "scope", "inner".to_json())
  assert_field(captured[2], "scope", "outer".to_json())
  assert_field(captured[3], "scope", "outer".to_json())
  reset_trace_state()
}

///|
test "with_trace_state restores all globals after raised failure" {
  reset_trace_state()
  let base_events = []
  let inner_events = []
  @moontrace.set_subscriber(fn(event) { base_events.push(event) })
  @moontrace.set_min_level(@moontrace.Warn)
  @moontrace.set_global_field("scope", "base")
  @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Error_)

  fn fail_in_scope() -> Unit raise ScopedFailure {
    @moontrace.with_trace_state(() => {
      @moontrace.set_subscriber(fn(event) { inner_events.push(event) })
      @moontrace.set_min_level(@moontrace.Trace)
      @moontrace.set_global_field("scope", "inner")
      @moontrace.set_global_field("inner_only", "yes")
      @moontrace.set_module_filter("brickfrog/moontrace", @moontrace.Trace)
      @moontrace.info("before failure")
      raise ScopedFailure
    })
  }

  let result : Result[Unit, ScopedFailure] = try? fail_in_scope()
  guard result is Err(_) else { abort("expected scoped failure") }

  @moontrace.info("blocked after failure")
  @moontrace.warn("blocked by restored module filter after failure")
  @moontrace.error("after failure")

  assert_eq(@moontrace.get_min_level(), @moontrace.Warn)
  assert_eq(inner_events.length(), 1)
  assert_eq(inner_events[0].message, "before failure")
  assert_field(inner_events[0], "scope", "inner".to_json())

  assert_eq(base_events.length(), 1)
  assert_eq(base_events[0].message, "after failure")
  assert_field(base_events[0], "scope", "base".to_json())
  assert_eq(has_field(base_events[0], "inner_only"), false)
  reset_trace_state()
}
