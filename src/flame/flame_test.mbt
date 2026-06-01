///|
fn test_span(
  name : String,
  span_id : String,
  parent_span_id : String,
  start_time : UInt64,
  end_time : UInt64,
) -> @moontrace.Span {
  test_span_with_trace(
    name, "00000000000000000000000000000001", span_id, parent_span_id, start_time,
    end_time,
  )
}

///|
fn test_span_with_trace(
  name : String,
  trace_id : String,
  span_id : String,
  parent_span_id : String,
  start_time : UInt64,
  end_time : UInt64,
) -> @moontrace.Span {
  @moontrace.Span::{
    name,
    fields: [],
    links: [],
    trace_id,
    span_id,
    parent_span_id,
    trace_flags: 0,
    trace_state: @moontrace.TraceState::empty(),
    kind: @moontrace.Internal,
    start_time,
    end_time,
    active: false,
    status: @moontrace.Unset,
    status_message: "",
  }
}

///|
test "fold spans uses self time for nested spans" {
  let root = test_span(
    "root",
    "0000000000000001",
    "",
    (10 : UInt64),
    (30 : UInt64),
  )
  let child = test_span(
    "child",
    "0000000000000002",
    root.span_id,
    (12 : UInt64),
    (17 : UInt64),
  )
  assert_eq(@flame.fold_spans([root, child]), "root 15\nroot;child 5")
}

///|
test "fold spans emits separate sibling stacks" {
  let root = test_span(
    "root",
    "0000000000000010",
    "",
    (0 : UInt64),
    (20 : UInt64),
  )
  let beta = test_span(
    "beta",
    "0000000000000011",
    root.span_id,
    (1 : UInt64),
    (4 : UInt64),
  )
  let alpha = test_span(
    "alpha",
    "0000000000000012",
    root.span_id,
    (5 : UInt64),
    (10 : UInt64),
  )
  assert_eq(
    @flame.fold_spans([root, beta, alpha]),
    "root 12\nroot;alpha 5\nroot;beta 3",
  )
}

///|
test "fold spans collapses repeated identical stacks" {
  let root = test_span(
    "root",
    "0000000000000020",
    "",
    (0 : UInt64),
    (12 : UInt64),
  )
  let first = test_span(
    "repeat",
    "0000000000000021",
    root.span_id,
    (1 : UInt64),
    (3 : UInt64),
  )
  let second = test_span(
    "repeat",
    "0000000000000022",
    root.span_id,
    (4 : UInt64),
    (7 : UInt64),
  )
  assert_eq(@flame.fold_spans([root, first, second]), "root 7\nroot;repeat 5")
}

///|
test "fold spans treats missing parents as roots" {
  let orphan = test_span(
    "orphan",
    "0000000000000030",
    "0000000000000999",
    (10 : UInt64),
    (14 : UInt64),
  )
  assert_eq(@flame.fold_spans([orphan]), "orphan 4")
}

///|
test "fold spans treats self parent as root" {
  let self_parent = test_span(
    "self",
    "0000000000000080",
    "0000000000000080",
    (0 : UInt64),
    (10 : UInt64),
  )
  assert_eq(@flame.fold_spans([self_parent]), "self 10")
}

///|
test "fold spans treats parent cycles as roots" {
  let a = test_span(
    "a",
    "0000000000000081",
    "0000000000000082",
    (0 : UInt64),
    (20 : UInt64),
  )
  let b = test_span(
    "b",
    "0000000000000082",
    a.span_id,
    (0 : UInt64),
    (5 : UInt64),
  )
  assert_eq(@flame.fold_spans([a, b]), "a 20\nb 5")
}

///|
test "fold spans does not link parent ids across traces" {
  let trace_a = "0000000000000000000000000000000a"
  let trace_b = "0000000000000000000000000000000b"
  let parent_a = test_span_with_trace(
    "trace-a-parent",
    trace_a,
    "0000000000000100",
    "",
    (0 : UInt64),
    (10 : UInt64),
  )
  let cross_trace_child = test_span_with_trace(
    "cross-trace-child",
    trace_b,
    "0000000000000101",
    parent_a.span_id,
    (0 : UInt64),
    (4 : UInt64),
  )
  assert_eq(
    @flame.fold_spans([parent_a, cross_trace_child]),
    "cross-trace-child 4\ntrace-a-parent 10",
  )
}

///|
test "fold spans sanitizes frame delimiters and ascii whitespace" {
  let span = test_span(
    "a;b c\tline\nnext",
    "0000000000000040",
    "",
    (2 : UInt64),
    (8 : UInt64),
  )
  assert_eq(@flame.fold_spans([span]), "a_b_c_line_next 6")
}

///|
test "fold spans omits zero self time stacks" {
  let root = test_span(
    "root",
    "0000000000000050",
    "",
    (0 : UInt64),
    (5 : UInt64),
  )
  let child = test_span(
    "child",
    "0000000000000051",
    root.span_id,
    (0 : UInt64),
    (5 : UInt64),
  )
  assert_eq(@flame.fold_spans([root, child]), "root;child 5")
}

///|
test "flame exporter flush emits and clears collected spans" {
  let output : Array[String] = []
  let exp = @flame.flame_exporter(output=fn(s) { output.push(s) })
  let observer = exp.span_observer()
  (observer.on_closed)(
    test_span("flush", "0000000000000060", "", (100 : UInt64), (109 : UInt64)),
  )
  exp.flush()
  assert_eq(output.length(), 1)
  assert_eq(output[0], "flush 9")
  assert_eq(exp.spans.length(), 0)
  exp.flush()
  assert_eq(output.length(), 2)
  assert_eq(output[1], "")
}

///|
test "flame exporter reset clears without output" {
  let output : Array[String] = []
  let exp = @flame.flame_exporter(output=fn(s) { output.push(s) })
  let observer = exp.span_observer()
  (observer.on_closed)(
    test_span("reset", "0000000000000070", "", (200 : UInt64), (207 : UInt64)),
  )
  assert_eq(exp.spans.length(), 1)
  exp.reset()
  assert_eq(output.length(), 0)
  assert_eq(exp.spans.length(), 0)
}
