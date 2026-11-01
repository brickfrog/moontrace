///|
fn queue_event(
  message : String,
  fields~ : Array[@moontrace.Field] = [],
) -> @moontrace.Event {
  @moontrace.Event::{
    level: @moontrace.Info,
    message,
    fields,
    timestamp: 0UL,
    source: "brickfrog/moontrace/queue",
    file: "",
    line: 0,
  }
}

///|
async test "flush drains in the calling task without a worker" {
  let batches : Array[Array[String]] = []
  let q = @queue.queued(
    batch => batches.push(batch.map(e => e.message)),
    max_batch=2,
  )
  let sub = q.subscriber()
  for i in 0..<5 {
    sub(queue_event("e\{i}"))
  }
  assert_eq(batches.length(), 0)
  q.flush()
  assert_eq(batches, [["e0", "e1"], ["e2", "e3"], ["e4"]])
  assert_eq(q.enqueued(), 5L)
  assert_eq(q.delivered(), 5L)
}

///|
async test "full queue drops and counts newest events" {
  let seen : Array[String] = []
  let q = @queue.queued(
    batch => batch.each(e => seen.push(e.message)),
    capacity=2,
  )
  let sub = q.subscriber()
  for i in 0..<4 {
    sub(queue_event("e\{i}"))
  }
  assert_eq(q.dropped(), 2L)
  q.shutdown()
  assert_eq(seen, ["e0", "e1"])
}

///|
async test "worker delivers to an async sink and shutdown ends it" {
  @async.with_task_group(group => {
    let seen : Array[String] = []
    let q = @queue.queued(batch => {
      @async.sleep(1)
      batch.each(e => seen.push(e.message))
    })
    group.spawn_bg(() => q.run())
    let sub = q.subscriber()
    sub(queue_event("a"))
    sub(queue_event("b"))
    q.flush()
    assert_eq(seen, ["a", "b"])
    sub(queue_event("c"))
    q.shutdown()
    assert_eq(seen, ["a", "b", "c"])
    sub(queue_event("late"))
    assert_eq(q.dropped(), 1L)
    assert_eq(q.delivered(), 3L)
  })
}

///|
async test "a raising sink counts the batch as failed and the worker continues" {
  @async.with_task_group(group => {
    let seen : Array[String] = []
    let q = @queue.queued(
      batch => {
        if batch[0].message == "bad" {
          fail("sink failure")
        }
        batch.each(e => seen.push(e.message))
      },
      max_batch=1,
    )
    group.spawn_bg(() => q.run())
    let sub = q.subscriber()
    sub(queue_event("bad"))
    sub(queue_event("good"))
    q.shutdown()
    assert_eq(q.failed(), 1L)
    assert_eq(q.delivered(), 1L)
    assert_eq(seen, ["good"])
  })
}

///|
async test "queued events keep a copy of their fields" {
  let seen : Array[Int32] = []
  let q = @queue.queued(batch => batch.each(e => seen.push(e.fields.length())))
  let fields = [@moontrace.field("k", 1)]
  q.subscriber()(queue_event("m", fields~))
  fields.push(@moontrace.field("late", 2))
  q.flush()
  assert_eq(seen, [1])
}

///|
async test "only one worker may run" {
  let q = @queue.queued(_ => ())
  let rejected = Ref(false)
  @async.with_task_group(group => {
    group.spawn_bg(() => q.run())
    @async.pause()
    q.run() catch {
      _ => rejected.val = true
    }
    q.shutdown()
  })
  assert_true(rejected.val)
}
