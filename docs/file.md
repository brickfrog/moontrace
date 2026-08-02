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

Rotation is size-based. When the active file crosses `max_size_bytes`, it is
renamed to `path.1`, older rotated files are shifted up, and files beyond
`max_files` are removed. With `gzip=true`, rotated files are written as
`path.N.gz` and the temporary uncompressed rotation is removed.

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
