///|
/// 2026-03-28T00:00:00Z in milliseconds.
#cfg(target="native")
const DAY0 : UInt64 = 1774656000000UL

///|
#cfg(target="native")
const DAY_MS : UInt64 = 86400000UL

///|
#cfg(target="native")
const HOUR_MS : UInt64 = 3600000UL

///|
#cfg(target="native")
async fn log_dir_entries(path : String) -> Array[String] {
  let (dir, base) = match path.rev_split_once("/") {
    Some((dir, base)) => (dir.to_owned(), base.to_owned())
    None => abort("expected a directory")
  }
  @fs.readdir(dir, sort=true).filter(name => name.has_prefix(base))
}

///|
#cfg(target="native")
async test "daily rotation archives the previous day's file by date" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let now = Ref(DAY0 + 10UL * HOUR_MS)
      let subscriber = @file.file_subscriber(path, rotate_every=Daily, clock=() => {
        now.val
      })
      let sink = subscriber.subscriber()
      sink(test_event("one"))
      subscriber.flush()
      sink(test_event("two"))
      subscriber.flush()
      now.val = DAY0 + DAY_MS + HOUR_MS
      sink(test_event("three"))
      subscriber.flush()
      assert_eq(
        @fs.read_file(path + ".2026-03-28").text(),
        lines(["one", "two"]),
      )
      assert_eq(@fs.read_file(path).text(), lines(["three"]))
      assert_eq(log_dir_entries(path), ["events.log", "events.log.2026-03-28"])
    })
  })
}

///|
#cfg(target="native")
async test "hourly rotation with gzip writes stamped gz archives" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let now = Ref(DAY0 + 14UL * HOUR_MS + 5UL)
      let subscriber = @file.file_subscriber(
        path,
        rotate_every=Hourly,
        gzip=true,
        clock=() => now.val,
      )
      let sink = subscriber.subscriber()
      sink(test_event("a"))
      subscriber.flush()
      now.val = now.val + HOUR_MS
      sink(test_event("b"))
      subscriber.flush()
      let archive = path + ".2026-03-28T14.gz"
      assert_eq(log_dir_entries(path), [
        "events.log", "events.log.2026-03-28T14.gz",
      ])
      let compressed = @fs.open(archive, mode=ReadOnly)
      defer compressed.close()
      assert_eq(@gzip.Decoder(compressed).read_all().text(), lines(["a"]))
    })
  })
}

///|
#cfg(target="native")
async test "size rotation within a period numbers dated archives" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let subscriber = @file.file_subscriber(
        path,
        rotate_every=Daily,
        max_size_bytes=1,
        max_batch=1,
        clock=() => DAY0,
      )
      let sink = subscriber.subscriber()
      sink(test_event("one"))
      sink(test_event("two"))
      sink(test_event("three"))
      subscriber.flush()
      assert_eq(@fs.read_file(path + ".2026-03-28").text(), event_line("one"))
      assert_eq(@fs.read_file(path + ".2026-03-28.1").text(), event_line("two"))
      assert_eq(
        @fs.read_file(path + ".2026-03-28.2").text(),
        event_line("three"),
      )
    })
  })
}

///|
#cfg(target="native")
async test "max_age_ms and max_files prune dated archives" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let now = Ref(DAY0)
      let subscriber = @file.file_subscriber(
        path,
        rotate_every=Daily,
        max_files=10,
        max_age_ms=DAY_MS * 2UL + HOUR_MS,
        clock=() => now.val,
      )
      let sink = subscriber.subscriber()
      for day in 0..<5 {
        now.val = DAY0 + day.to_uint64() * DAY_MS
        sink(test_event("day\{day}"))
        subscriber.flush()
      }
      // Writing on day 4 archived day 3. Archives for days 0 and 1 started more
      // than 2 days 1 hour before day 4.
      assert_eq(log_dir_entries(path), [
        "events.log", "events.log.2026-03-30", "events.log.2026-03-31",
      ])

      let capped = @file.file_subscriber(
        path + ".capped",
        rotate_every=Daily,
        max_files=1,
        clock=() => now.val,
      )
      let capped_sink = capped.subscriber()
      for day in 5..<8 {
        now.val = DAY0 + day.to_uint64() * DAY_MS
        capped_sink(test_event("day\{day}"))
        capped.flush()
      }
      assert_eq(log_dir_entries(path + ".capped"), [
        "events.log.capped", "events.log.capped.2026-04-03",
      ])
    })
  })
}

///|
#cfg(target="native")
async test "a quiet period does not rotate until the next write" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let now = Ref(DAY0)
      let subscriber = @file.file_subscriber(path, rotate_every=Daily, clock=() => {
        now.val
      })
      let sink = subscriber.subscriber()
      sink(test_event("first"))
      subscriber.flush()
      now.val = DAY0 + 3UL * DAY_MS
      assert_eq(log_dir_entries(path), ["events.log"])
      sink(test_event("later"))
      subscriber.flush()
      // The archive is stamped with the period the file covered.
      assert_eq(log_dir_entries(path), ["events.log", "events.log.2026-03-28"])
    })
  })
}

///|
#cfg(target="native")
async test "retention within one period keeps the newest archives" {
  @async.with_timeout(1000, () => {
    with_temp_log(path => {
      let subscriber = @file.file_subscriber(
        path,
        rotate_every=Daily,
        max_size_bytes=1,
        max_files=1,
        max_batch=1,
        clock=() => DAY0,
      )
      let sink = subscriber.subscriber()
      for i in 0..<5 {
        sink(test_event("e\{i}"))
      }
      subscriber.flush()
      // Each write rotates; with one archive kept, it must be the newest.
      assert_eq(log_dir_entries(path), ["events.log", "events.log.2026-03-28.4"])
      assert_eq(@fs.read_file(path + ".2026-03-28.4").text(), event_line("e4"))
    })
  })
}
