///|
fn tail_fixture(
  policy~ : (@moontrace.TraceSummary) -> Bool = @moontrace.tail_policy(),
  max_traces~ : Int32 = 1000,
  max_spans_per_trace~ : Int32 = 1000,
  clock~ : () -> UInt64 = () => 0UL,
) -> (@moontrace.TailSampler, Array[String]) {
  let delivered : Array[String] = []
  let sampler = @moontrace.tail_sampler(
    @moontrace.completed_span_observer(span => delivered.push(span.name)),
    policy~,
    max_traces~,
    max_spans_per_trace~,
    trace_timeout_ms=1000UL,
    clock~,
  )
  (sampler, delivered)
}

///|
test "error traces are kept after every span closes; clean traces are dropped" {
  let (sampler, delivered) = tail_fixture()
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_observer(sampler.observer())
    let root = @moontrace.span("root")
    root.enter()
    let child = @moontrace.child_span(root, "child")
    child.enter()
    child.record_error("boom")
    child.exit()
    assert_eq(delivered, [])
    assert_eq(sampler.pending(), 1)
    root.exit()
    let clean = @moontrace.span("clean")
    clean.enter()
    clean.exit()
  })
  assert_eq(delivered, ["child", "root"])
  assert_eq(sampler.kept(), 1L)
  assert_eq(sampler.dropped(), 1L)
  assert_eq(sampler.pending(), 0)
  assert_eq(sampler.forced(), 0L)
}

///|
test "events wait for their trace's decision" {
  let (sampler, _) = tail_fixture(policy=summary => {
    summary.spans.iter().any(s => s.name == "keep")
  })
  let events : Array[String] = []
  @moontrace.with_trace_state(() => {
    // Lifecycle events have no trace_id and would pass straight through.
    @moontrace.set_min_level(@moontrace.Info)
    @moontrace.set_subscriber(sampler.subscriber(e => events.push(e.message)))
    @moontrace.set_span_observer(sampler.observer())
    let kept = @moontrace.span("keep")
    kept.enter()
    kept.info("inside kept")
    let dropped = @moontrace.span("drop")
    dropped.enter()
    dropped.info("inside dropped")
    @moontrace.info("untraced")
    assert_eq(events, ["untraced"])
    dropped.exit()
    kept.exit()
    kept.info("after kept")
    dropped.info("after dropped")
  })
  assert_eq(events, ["untraced", "inside kept", "after kept"])
}

///|
test "memory bounds force early decisions" {
  let (sampler, delivered) = tail_fixture(
    policy=_ => true,
    max_traces=2,
    max_spans_per_trace=2,
  )
  let seen : Array[Bool] = []
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_observer(sampler.observer())
    let a = @moontrace.span("a")
    let _b = @moontrace.span("b")
    let _c = @moontrace.span("c")
    // Creating a third pending trace evicted the oldest, "a", with no spans.
    assert_eq(sampler.pending(), 2)
    assert_eq(sampler.forced(), 1L)
    a.enter()
    let root = @moontrace.span("big")
    root.enter()
    for i in 0..<2 {
      let child = @moontrace.child_span(root, "child\{i}")
      child.enter()
      child.exit()
    }
    seen.push(delivered.contains("child1"))
  })
  // The span limit decided "big" early, before its root closed.
  assert_eq(seen, [true])
}

///|
test "timeouts and flush decide unfinished traces" {
  let now = Ref(0UL)
  let summaries : Array[Bool] = []
  let (sampler, _) = tail_fixture(
    policy=summary => {
      summaries.push(summary.forced)
      true
    },
    clock=() => now.val,
  )
  @moontrace.with_trace_state(() => {
    @moontrace.set_span_observer(sampler.observer())
    let orphan = @moontrace.span("orphan")
    orphan.enter()
    now.val = 1500UL
    // Any callback checks timeouts.
    let _other = @moontrace.span("other")
    assert_eq(summaries, [true])
    sampler.flush()
  })
  assert_eq(summaries, [true, true])
  assert_eq(sampler.pending(), 0)
  assert_eq(sampler.forced(), 2L)
}

///|
test "tail_policy keeps errors, slow traces, and a ratio" {
  let summary = (has_error : Bool, ms : UInt64) => @moontrace.TraceSummary::{
    trace_id: "ffffffffffffffffffffffffffffffff",
    spans: [],
    has_error,
    max_duration_ms: ms,
    forced: false,
  }
  let default = @moontrace.tail_policy()
  assert_true(default(summary(true, 0UL)))
  assert_false(default(summary(false, 10_000UL)))
  let slow = @moontrace.tail_policy(min_duration_ms=500UL, keep_errors=false)
  assert_true(slow(summary(false, 500UL)))
  assert_false(slow(summary(true, 10UL)))
  assert_true(@moontrace.tail_policy(ratio=1.0)(summary(false, 0UL)))
}
