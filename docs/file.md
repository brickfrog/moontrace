# File subscriber

`brickfrog/moontrace/file` is a native-only buffered file subscriber. The
subscriber returned by `FileSubscriber::subscriber()` is synchronous: it formats
the event as one JSON line and attempts a non-blocking enqueue. When the queue
is full or shut down, the event is dropped and counted.

The application owns the async worker. Start `run()` inside the app's async
context, then call `flush()` at durability boundaries and `shutdown()` before
leaving the task group.

```moonbit
let files = @file.file_subscriber(
  "logs/moontrace.jsonl",
  max_size_bytes=10 * 1024 * 1024,
  max_files=5,
  gzip=true,
  max_batch=128,
  queue_capacity=1024,
)

@moontrace.set_subscriber(files.subscriber())

@async.with_task_group(group => {
  group.spawn_bg(() => files.run())

  @moontrace.info("service started")
  files.flush()

  files.shutdown()
})
```

By default rotation is size-based. When the active file crosses
`max_size_bytes`, it is renamed to `path.1`, older rotated files are shifted
up, and files beyond `max_files` are removed. With `gzip=true`, rotated files
are written as `path.N.gz` and the temporary uncompressed rotation is removed.

## Time-based rotation

`rotate_every=Daily` or `rotate_every=Hourly` archives the active file when a
UTC day or hour ends, like tracing-appender's `rolling::daily`:

```moonbit
let files = @file.file_subscriber(
  "logs/app.jsonl",
  rotate_every=Daily,
  max_age_ms=7UL * 24UL * 60UL * 60UL * 1000UL,
  max_files=30,
  gzip=true,
)
```

Archives are named for the period they cover: `app.jsonl.2026-03-28` for daily
rotation and `app.jsonl.2026-03-28T14` for hourly rotation, plus `.gz` with
`gzip=true`. Reaching `max_size_bytes` inside a period also archives the file,
as `app.jsonl.2026-03-28.1`, `.2`, and so on. The check runs when a batch is
written, so a quiet period rotates on the next write and the archive keeps the
stamp of the period the file covered. A subscriber that starts with an
existing active file treats it as part of the current period.

Retention applies to dated archives next to the active file. Archives whose
period started more than `max_age_ms` ago are deleted, and only the newest
`max_files` are kept. Files that don't match the `path.<stamp>[.n][.gz]`
pattern are never touched.

`file_subscriber(clock=...)` and `FileSubscriber::new(config, clock=...)`
accept a millisecond clock so tests can move time deterministically.

On Unix, every active or gzip file newly created by the subscriber requests
mode `0600` (owner read/write only). The process umask may make that mode more
restrictive, but cannot grant group or other access. A raw rotated file is a
rename of the active file and retains its mode.

The subscriber does not change the permissions of an existing active file. If
the configured path already exists, its mode and ownership remain the caller's
responsibility. The caller is also responsible for the ownership and
permissions of the parent directory. The underlying `moonbitlang/async/fs`
permission argument is ignored on Windows.

The file subscriber uses `moonbitlang/async/fs` and is only supported on the
native target. Constructing it on other targets aborts immediately with a clear
unsupported-target error instead of returning a subscriber that drops events.
