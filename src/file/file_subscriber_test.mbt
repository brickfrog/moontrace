///|
#cfg(target="native")
fn test_event(message : String) -> @moontrace.Event {
  @moontrace.Event::{
    level: @moontrace.Info,
    message,
    fields: [],
    timestamp: (123 : UInt64),
    source: "brickfrog/moontrace/file/test",
  }
}

///|
#cfg(target="native")
fn event_line(message : String) -> String {
  test_event(message).to_json().stringify() + "\n"
}

///|
#cfg(target="native")
fn lines(messages : Array[String]) -> String {
  let builder = StringBuilder::new()
  messages.each(fn(message) { builder.write_string(event_line(message)) })
  builder.to_string()
}

///|
#cfg(target="native")
fn string_bytes(data : String) -> Int {
  let payload : &@io.Data = data
  payload.binary().length()
}

///|
#cfg(target="native")
async fn with_temp_log(f : async (String) -> Unit) -> Unit {
  @async.with_task_group(group => {
    let dir = @fs.tmpdir(prefix="moontrace-file")
    group.add_defer(() => {
      @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
    })
    f(dir + "/events.log")
  })
}

///|
#cfg(target="native")
async test "append writes json lines in order after flush" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let subscriber = @file.file_subscriber(path, max_batch=16)
      let sink = subscriber.subscriber()
      sink(test_event("one"))
      sink(test_event("two"))
      subscriber.flush()
      assert_eq(@fs.read_file(path).text(), lines(["one", "two"]))
      assert_eq(subscriber.written(), 2)
      assert_eq(subscriber.dropped(), 0)
    })
  })
}

///|
#cfg(target="native")
async test "rotation creates rotated file and fresh active file" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let expected = lines(["before", "after"])
      let subscriber = @file.file_subscriber(
        path,
        max_size_bytes=string_bytes(expected) - 1,
        max_files=3,
        max_batch=16,
      )
      let sink = subscriber.subscriber()
      sink(test_event("before"))
      sink(test_event("after"))
      subscriber.flush()
      assert_eq(@fs.read_file(path + ".1").text(), expected)
      assert_true(@fs.exists(path))
      assert_eq(@fs.read_file(path).text(), "")
    })
  })
}

///|
#cfg(target="native")
async test "retention deletes rotated files beyond max_files" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let subscriber = @file.file_subscriber(
        path,
        max_size_bytes=1,
        max_files=2,
        max_batch=1,
      )
      let sink = subscriber.subscriber()
      sink(test_event("one"))
      sink(test_event("two"))
      sink(test_event("three"))
      sink(test_event("four"))
      subscriber.flush()
      assert_eq(@fs.read_file(path + ".1").text(), event_line("four"))
      assert_eq(@fs.read_file(path + ".2").text(), event_line("three"))
      assert_true(!@fs.exists(path + ".3"))
    })
  })
}

///|
#cfg(target="native")
async test "gzip compresses rotated files" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let expected = event_line("compressed")
      let subscriber = @file.file_subscriber(
        path,
        max_size_bytes=1,
        max_files=1,
        gzip=true,
        max_batch=1,
      )
      let sink = subscriber.subscriber()
      sink(test_event("compressed"))
      subscriber.flush()
      assert_true(@fs.exists(path + ".1.gz"))
      assert_true(!@fs.exists(path + ".1"))
      let compressed = @fs.open(
        path + ".1.gz",
        mode=@fs.Mode::ReadOnly,
        create_mode=@fs.CreateMode::OpenExisting,
      )
      defer compressed.close()
      assert_eq(@gzip.Decoder(compressed).read_all().text(), expected)
    })
  })
}

///|
#cfg(target="native")
async test "bounded batches drain bursts and overflow counts drops" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let dir = @fs.tmpdir(prefix="moontrace-file")
      group.add_defer(() => {
        @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
      })
      let path = dir + "/events.log"
      let subscriber = @file.file_subscriber(
        path,
        max_size_bytes=100000,
        max_files=1,
        max_batch=3,
        queue_capacity=16,
      )
      group.spawn_bg(() => subscriber.run())
      @async.sleep(0)
      let sink = subscriber.subscriber()
      let messages = ["m0", "m1", "m2", "m3", "m4", "m5", "m6"]
      messages.each(fn(message) { sink(test_event(message)) })
      subscriber.flush()
      assert_eq(@fs.read_file(path).text(), lines(messages))
      assert_eq(subscriber.written(), 7)
      assert_eq(subscriber.dropped(), 0)
      subscriber.shutdown()

      let overflow_path = dir + "/overflow.log"
      let overflow = @file.file_subscriber(
        overflow_path,
        max_size_bytes=100000,
        max_files=1,
        max_batch=8,
        queue_capacity=2,
      )
      let overflow_sink = overflow.subscriber()
      overflow_sink(test_event("keep-one"))
      overflow_sink(test_event("keep-two"))
      overflow_sink(test_event("drop-one"))
      overflow_sink(test_event("drop-two"))
      overflow.flush()
      assert_eq(overflow.dropped(), 2)
      assert_eq(overflow.written(), 2)
      assert_eq(
        @fs.read_file(overflow_path).text(),
        lines(["keep-one", "keep-two"]),
      )
    })
  })
}

///|
#cfg(target="native")
async test "shutdown flushes queued lines and drops future events" {
  @async.with_timeout(1000, () => {
    @async.with_task_group(group => {
      let dir = @fs.tmpdir(prefix="moontrace-file")
      group.add_defer(() => {
        @async.protect_from_cancel(() => @fs.rmdir(dir, recursive=true))
      })
      let path = dir + "/events.log"
      let subscriber = @file.file_subscriber(
        path,
        max_batch=2,
        queue_capacity=8,
      )
      group.spawn_bg(() => subscriber.run())
      @async.sleep(0)
      let sink = subscriber.subscriber()
      sink(test_event("queued-one"))
      sink(test_event("queued-two"))
      subscriber.shutdown()
      assert_eq(@fs.read_file(path).text(), lines(["queued-one", "queued-two"]))
      let dropped_before = subscriber.dropped()
      sink(test_event("after-shutdown"))
      assert_eq(subscriber.dropped(), dropped_before + 1)
      assert_eq(subscriber.written(), 2)
      assert_eq(@fs.read_file(path).text(), lines(["queued-one", "queued-two"]))
    })
  })
}
