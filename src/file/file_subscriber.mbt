///|
const DEFAULT_MAX_SIZE_BYTES : Int32 = 10 * 1024 * 1024

///|
const DEFAULT_MAX_FILES : Int32 = 5

///|
const DEFAULT_MAX_BATCH : Int32 = 128

///|
const DEFAULT_QUEUE_CAPACITY : Int32 = 1024

///|
#cfg(target="native")
const FILE_PERMISSION : Int32 = 0o600

///|
/// Calendar periods for time-based rotation, in UTC.
pub(all) enum RotationPeriod {
  /// Archive as `path.YYYY-MM-DDTHH`.
  Hourly
  /// Archive as `path.YYYY-MM-DD`.
  Daily
} derive(Eq, Compare, Debug)

///|
/// File subscriber settings.
///
/// Without `rotate_every`, the active file rotates by size to `path.1` ...
/// `path.N` (`max_files`). With `rotate_every`, the active file is archived
/// when a UTC period ends, and on reaching `max_size_bytes`, as
/// `path.<stamp>` (or `path.<stamp>.1`, `.2`, ... if taken), where `<stamp>` is
/// the period the file covered. Dated archives older than `max_age_ms`,
/// measured from the start of their period, are deleted, and at most
/// `max_files` of the newest are kept. `gzip` adds `.gz` to archives.
pub(all) struct FileSubscriberConfig {
  path : String
  max_size_bytes : Int32
  max_files : Int32
  gzip : Bool
  max_batch : Int32
  queue_capacity : Int32
  rotate_every : RotationPeriod?
  max_age_ms : UInt64?
} derive(Eq, Compare, Debug)

///|
pub fn FileSubscriberConfig::new(
  path : String,
  max_size_bytes~ : Int32 = DEFAULT_MAX_SIZE_BYTES,
  max_files~ : Int32 = DEFAULT_MAX_FILES,
  gzip~ : Bool = false,
  max_batch~ : Int32 = DEFAULT_MAX_BATCH,
  queue_capacity~ : Int32 = DEFAULT_QUEUE_CAPACITY,
  rotate_every? : RotationPeriod,
  max_age_ms? : UInt64,
) -> FileSubscriberConfig {
  {
    path,
    max_size_bytes: clamp_positive(max_size_bytes),
    max_files: clamp_non_negative(max_files),
    gzip,
    max_batch: clamp_positive(max_batch),
    queue_capacity: clamp_positive(queue_capacity),
    rotate_every,
    max_age_ms,
  }
}

///|
#cfg(target="native")
struct FileSubscriber {
  config : FileSubscriberConfig
  queue : @aqueue.Queue[String]
  write_lock : @aqueue.Queue[Unit]
  clock : () -> UInt64
  mut period_start : UInt64
  mut initialized : Bool
  mut current_size : Int32
  mut enqueued_count : Int32
  mut written_count : Int32
  mut dropped_count : Int32
  mut is_shut_down : Bool
  mut worker_running : Bool
}

///|
#cfg(not(target="native"))
struct FileSubscriber {
  marker : Unit
}

///|
#cfg(not(target="native"))
let _non_native_file_subscriber_marker : FileSubscriber = FileSubscriber::{
  marker: (),
}

///|
pub fn file_subscriber(
  path : String,
  max_size_bytes~ : Int32 = DEFAULT_MAX_SIZE_BYTES,
  max_files~ : Int32 = DEFAULT_MAX_FILES,
  gzip~ : Bool = false,
  max_batch~ : Int32 = DEFAULT_MAX_BATCH,
  queue_capacity~ : Int32 = DEFAULT_QUEUE_CAPACITY,
  rotate_every? : RotationPeriod,
  max_age_ms? : UInt64,
  clock~ : () -> UInt64 = @env.now,
) -> FileSubscriber {
  FileSubscriber::new(
    FileSubscriberConfig::new(
      path,
      max_size_bytes~,
      max_files~,
      gzip~,
      max_batch~,
      queue_capacity~,
      rotate_every?,
      max_age_ms?,
    ),
    clock~,
  )
}

///|
/// Create a subscriber. `clock` returns milliseconds since the Unix epoch and
/// decides time-based rotation; tests can inject one.
#cfg(target="native")
pub fn FileSubscriber::new(
  config : FileSubscriberConfig,
  clock~ : () -> UInt64 = @env.now,
) -> FileSubscriber {
  let queue : @aqueue.Queue[String] = @aqueue.Queue(
    kind=@aqueue.Kind::Blocking(config.queue_capacity),
  )
  let write_lock : @aqueue.Queue[Unit] = @aqueue.Queue(
    kind=@aqueue.Kind::Blocking(1),
  )
  let _ = write_lock.try_put(()) catch { _ => false }
  {
    config,
    queue,
    write_lock,
    clock,
    period_start: 0UL,
    initialized: false,
    current_size: 0,
    enqueued_count: 0,
    written_count: 0,
    dropped_count: 0,
    is_shut_down: false,
    worker_running: false,
  }
}

///|
#cfg(not(target="native"))
pub fn FileSubscriber::new(
  _config : FileSubscriberConfig,
  clock~ : () -> UInt64 = @env.now,
) -> FileSubscriber {
  ignore(clock)
  abort(unsupported_target_message())
}

///|
#cfg(target="native")
pub fn FileSubscriber::subscriber(
  self : FileSubscriber,
) -> (@moontrace.Event) -> Unit {
  fn(event) {
    if self.is_shut_down {
      self.dropped_count += 1
      return
    }
    let line = event.to_json().stringify() + "\n"
    let accepted = self.queue.try_put(line) catch { _ => false }
    if accepted {
      self.enqueued_count += 1
    } else {
      self.dropped_count += 1
    }
  }
}

///|
#cfg(not(target="native"))
pub fn FileSubscriber::subscriber(
  self : FileSubscriber,
) -> (@moontrace.Event) -> Unit {
  ignore(self.marker)
  fn(_event) { abort(unsupported_target_message()) }
}

///|
pub fn FileSubscriber::dropped(self : FileSubscriber) -> Int32 {
  self.dropped_count_impl()
}

///|
#cfg(target="native")
pub fn FileSubscriber::written(self : FileSubscriber) -> Int32 {
  self.written_count
}

///|
#cfg(not(target="native"))
pub fn FileSubscriber::written(_self : FileSubscriber) -> Int32 {
  0
}

///|
#cfg(target="native")
fn FileSubscriber::dropped_count_impl(self : FileSubscriber) -> Int32 {
  self.dropped_count
}

///|
#cfg(not(target="native"))
fn FileSubscriber::dropped_count_impl(_self : FileSubscriber) -> Int32 {
  ignore(_self.marker)
  0
}

///|
#cfg(target="native")
pub async fn FileSubscriber::run(self : FileSubscriber) -> Unit {
  if self.worker_running {
    raise Failure::Failure(
      "moontrace file subscriber worker is already running",
    )
  }
  self.worker_running = true
  defer {
    self.worker_running = false
  }
  while true {
    let first = self.queue.get() catch {
      @aqueue.QueueAlreadyClosed => return
      err => raise err
    }
    let batch = self.batch_with_first(first)
    self.write_batch(batch)
    @async.sleep(0)
  }
}

///|
#cfg(not(target="native"))
pub async fn FileSubscriber::run(self : FileSubscriber) -> Unit {
  ignore(self.marker)
  @async.sleep(0)
  raise Failure::Failure(unsupported_target_message())
}

///|
#cfg(target="native")
pub async fn FileSubscriber::flush(self : FileSubscriber) -> Unit {
  let target = self.enqueued_count
  if self.worker_running {
    while self.worker_running && self.written_count < target {
      @async.sleep(0)
    }
  }
  if self.written_count < target {
    self.drain_without_worker()
  }
  if self.written_count < target {
    raise Failure::Failure(
      "moontrace file subscriber flush could not write all accepted events",
    )
  }
}

///|
#cfg(not(target="native"))
pub async fn FileSubscriber::flush(self : FileSubscriber) -> Unit {
  ignore(self.marker)
  @async.sleep(0)
  raise Failure::Failure(unsupported_target_message())
}

///|
#cfg(target="native")
pub async fn FileSubscriber::shutdown(self : FileSubscriber) -> Unit {
  if !self.is_shut_down {
    self.is_shut_down = true
  }
  self.flush()
  self.queue.close()
  while self.worker_running {
    @async.sleep(0)
  }
}

///|
#cfg(not(target="native"))
pub async fn FileSubscriber::shutdown(self : FileSubscriber) -> Unit {
  ignore(self.marker)
  @async.sleep(0)
  raise Failure::Failure(unsupported_target_message())
}

///|
fn clamp_positive(value : Int32) -> Int32 {
  if value < 1 {
    1
  } else {
    value
  }
}

///|
fn clamp_non_negative(value : Int32) -> Int32 {
  if value < 0 {
    0
  } else {
    value
  }
}

///|
#cfg(not(target="native"))
fn unsupported_target_message() -> String {
  "moontrace file subscriber is only supported on the native target"
}

///|
#cfg(target="native")
fn byte_len(data : String) -> Int32 {
  let payload : &@io.Data = data
  payload.binary().length()
}

///|
#cfg(target="native")
fn FileSubscriber::try_take(self : FileSubscriber) -> String? {
  self.queue.try_get() catch {
    _ => None
  }
}

///|
#cfg(target="native")
fn FileSubscriber::batch_with_first(
  self : FileSubscriber,
  first : String,
) -> Array[String] {
  let batch = [first]
  while batch.length() < self.config.max_batch {
    match self.try_take() {
      Some(line) => batch.push(line)
      None => break
    }
  }
  batch
}

///|
#cfg(target="native")
async fn FileSubscriber::drain_without_worker(self : FileSubscriber) -> Unit {
  while true {
    match self.try_take() {
      Some(first) => {
        self.write_batch(self.batch_with_first(first))
        @async.sleep(0)
      }
      None => return
    }
  }
}

///|
#cfg(target="native")
async fn FileSubscriber::write_batch(
  self : FileSubscriber,
  lines : Array[String],
) -> Unit {
  if lines.is_empty() {
    return
  }
  ignore(self.write_lock.get())
  defer self.release_write_lock()
  self.initialize_file()
  self.rotate_if_period_ended()
  let builder = StringBuilder()
  let mut payload_bytes = 0
  lines.each(fn(line) {
    payload_bytes += byte_len(line)
    builder.write_string(line)
  })
  if self.current_size > 0 &&
    self.current_size + payload_bytes > self.config.max_size_bytes {
    self.rotate()
  }
  let payload = builder.to_string()
  @fs.write_file(
    self.config.path,
    payload,
    create_mode=@fs.CreateMode::OpenOrCreate,
    permission=FILE_PERMISSION,
    append=true,
  )
  self.current_size += payload_bytes
  self.written_count += lines.length()
  if self.current_size >= self.config.max_size_bytes {
    self.rotate()
  }
}

///|
#cfg(target="native")
fn FileSubscriber::release_write_lock(self : FileSubscriber) -> Unit {
  let _ = self.write_lock.try_put(()) catch { _ => false }
}

///|
#cfg(target="native")
async fn FileSubscriber::initialize_file(self : FileSubscriber) -> Unit {
  if self.initialized {
    return
  }
  if self.config.rotate_every is Some(period) {
    self.period_start = period_start_ms(period, (self.clock)())
  }
  if @fs.exists(self.config.path) {
    let file = @fs.open(
      self.config.path,
      mode=@fs.Mode::ReadOnly,
      create_mode=@fs.CreateMode::OpenExisting,
    )
    self.current_size = file.size().to_int()
    file.close()
    if self.current_size >= self.config.max_size_bytes {
      self.rotate()
    }
  } else {
    self.ensure_active_file()
  }
  self.initialized = true
}

///|
#cfg(target="native")
async fn FileSubscriber::ensure_active_file(self : FileSubscriber) -> Unit {
  @fs.write_file(
    self.config.path,
    "",
    create_mode=@fs.CreateMode::OpenOrCreate,
    permission=FILE_PERMISSION,
    append=true,
  )
}

///|
#cfg(target="native")
async fn FileSubscriber::rotate(self : FileSubscriber) -> Unit {
  if self.config.rotate_every is Some(period) {
    self.archive_dated(period, self.period_start)
    return
  }
  if !@fs.exists(self.config.path) {
    self.current_size = 0
    self.ensure_active_file()
    return
  }
  if self.config.max_files == 0 {
    @fs.remove(self.config.path)
    self.current_size = 0
    self.ensure_active_file()
    @async.sleep(0)
    return
  }
  self.shift_rotated_files()
  let raw_path = self.raw_rotated_path(1)
  self.remove_if_exists(raw_path)
  if self.config.gzip {
    self.remove_if_exists(self.rotated_path(1))
  }
  @fs.rename(self.config.path, raw_path, replace=true)
  if self.config.gzip {
    self.gzip_file(raw_path, self.rotated_path(1))
    self.remove_if_exists(raw_path)
  }
  self.current_size = 0
  self.ensure_active_file()
  @async.sleep(0)
}

///|
#cfg(target="native")
async fn FileSubscriber::shift_rotated_files(self : FileSubscriber) -> Unit {
  self.remove_if_exists(self.rotated_path(self.config.max_files))
  if self.config.gzip {
    self.remove_if_exists(self.raw_rotated_path(self.config.max_files))
  }
  let mut index = self.config.max_files - 1
  while index >= 1 {
    let from = self.rotated_path(index)
    if @fs.exists(from) {
      @fs.rename(from, self.rotated_path(index + 1), replace=true)
    }
    index -= 1
  }
}

///|
#cfg(target="native")
fn FileSubscriber::raw_rotated_path(
  self : FileSubscriber,
  index : Int32,
) -> String {
  self.config.path + "." + index.to_string()
}

///|
#cfg(target="native")
fn FileSubscriber::rotated_path(self : FileSubscriber, index : Int32) -> String {
  let path = self.raw_rotated_path(index)
  if self.config.gzip {
    path + ".gz"
  } else {
    path
  }
}

///|
#cfg(target="native")
async fn FileSubscriber::remove_if_exists(
  _self : FileSubscriber,
  path : String,
) -> Unit {
  if @fs.exists(path) {
    @fs.remove(path)
  }
}

///|
#cfg(target="native")
async fn FileSubscriber::gzip_file(
  _self : FileSubscriber,
  source : String,
  destination : String,
) -> Unit {
  let reader = @fs.open(
    source,
    mode=@fs.Mode::ReadOnly,
    create_mode=@fs.CreateMode::OpenExisting,
  )
  defer reader.close()
  let writer = @fs.open(
    destination,
    mode=@fs.Mode::WriteOnly,
    create_mode=@fs.CreateMode::CreateOrTruncate,
    permission=FILE_PERMISSION,
  )
  defer writer.close()
  let encoder = @gzip.Encoder(writer)
  encoder.write(reader.read_all())
  encoder.end()
  @async.sleep(0)
}

///|
#cfg(target="native")
fn period_length_ms(period : RotationPeriod) -> UInt64 {
  match period {
    Hourly => 3_600_000UL
    Daily => 86_400_000UL
  }
}

///|
/// The start of the UTC period containing `now_ms`.
#cfg(target="native")
fn period_start_ms(period : RotationPeriod, now_ms : UInt64) -> UInt64 {
  let length = period_length_ms(period)
  now_ms / length * length
}

///|
/// `YYYY-MM-DD` for daily periods, `YYYY-MM-DDTHH` for hourly ones.
#cfg(target="native")
fn period_stamp(period : RotationPeriod, start_ms : UInt64) -> String {
  let text = @moontrace.format_timestamp_rfc3339(start_ms)
  match period {
    Daily => text[0:10].to_owned()
    Hourly => text[0:13].to_owned()
  }
}

///|
/// Parse ASCII digits, rejecting values that would overflow `Int64`.
#cfg(target="native")
fn parse_digits(text : StringView) -> Int64? {
  if text.is_empty() || text.length() > 18 {
    return None
  }
  let mut value = 0L
  for ch in text {
    if ch < '0' || ch > '9' {
      return None
    }
    value = value * 10L + (ch.to_int() - '0'.to_int()).to_int64()
  }
  Some(value)
}

///|
/// Days since 1970-01-01 for a proleptic Gregorian date (Hinnant's
/// `days_from_civil`).
#cfg(target="native")
fn days_from_civil(year : Int64, month : Int64, day : Int64) -> Int64 {
  let y = if month <= 2L { year - 1L } else { year }
  let era = (if y >= 0L { y } else { y - 399L }) / 400L
  let year_of_era = y - era * 400L
  let shifted_month = if month > 2L { month - 3L } else { month + 9L }
  let day_of_year = (153L * shifted_month + 2L) / 5L + day - 1L
  let day_of_era = year_of_era * 365L +
    year_of_era / 4L -
    year_of_era / 100L +
    day_of_year
  era * 146097L + day_of_era - 719468L
}

///|
/// Parse a stamp written by `period_stamp` back to its period start.
#cfg(target="native")
fn parse_period_stamp(period : RotationPeriod, stamp : StringView) -> UInt64? {
  let expected = match period {
    Daily => 10
    Hourly => 13
  }
  if stamp.length() != expected ||
    stamp[4:5] != "-" ||
    stamp[7:8] != "-" ||
    (period is Hourly && stamp[10:11] != "T") {
    return None
  }
  guard parse_digits(stamp[0:4]) is Some(year) &&
    parse_digits(stamp[5:7]) is Some(month) &&
    parse_digits(stamp[8:10]) is Some(day) &&
    month >= 1L &&
    month <= 12L &&
    day >= 1L &&
    day <= 31L else {
    return None
  }
  let hour = match period {
    Daily => 0L
    Hourly =>
      match parse_digits(stamp[11:13]) {
        Some(hour) if hour < 24L => hour
        _ => return None
      }
  }
  let days = days_from_civil(year, month, day)
  if days < 0L {
    return None
  }
  Some((days * 86_400_000L + hour * 3_600_000L).reinterpret_as_uint64())
}

///|
/// A dated archive found next to the active file.
#cfg(target="native")
priv struct DatedArchive {
  name : String
  start_ms : UInt64
  sequence : Int64
}

///|
/// Parse `<base>.<stamp>[.<n>][.gz]` into its period start and sequence.
#cfg(target="native")
fn parse_dated_archive(
  base : String,
  period : RotationPeriod,
  name : String,
) -> DatedArchive? {
  guard name.has_prefix(base + ".") else { return None }
  let rest = name[base.length() + 1:]
  let rest = if rest.has_suffix(".gz") {
    rest[0:rest.length() - 3]
  } else {
    rest
  }
  let (stamp, sequence) = match rest.split_once(".") {
    Some((stamp, n)) =>
      match parse_digits(n) {
        Some(n) => (stamp, n)
        None => return None
      }
    None => (rest, 0L)
  }
  match parse_period_stamp(period, stamp) {
    Some(start_ms) => Some({ name, start_ms, sequence, })
    None => None
  }
}

///|
#cfg(target="native")
fn split_dir(path : String) -> (String, String) {
  match path.rev_split_once("/") {
    Some((dir, base)) =>
      (if dir.is_empty() { "/" } else { dir.to_owned() }, base.to_owned())
    None => (".", path)
  }
}

///|
#cfg(target="native")
async fn FileSubscriber::rotate_if_period_ended(self : FileSubscriber) -> Unit {
  guard self.config.rotate_every is Some(period) else { return }
  let current = period_start_ms(period, (self.clock)())
  if current == self.period_start {
    return
  }
  if self.current_size > 0 {
    self.archive_dated(period, self.period_start)
  }
  self.period_start = current
  self.prune_dated(period)
}

///|
/// Move the active file to `path.<stamp>` for the period starting at
/// `start_ms`, or to `path.<stamp>.<n>` with `n` above every existing sequence
/// for that period, so names freed by retention are never reused. Then gzip it
/// if configured and prune archives.
#cfg(target="native")
async fn FileSubscriber::archive_dated(
  self : FileSubscriber,
  period : RotationPeriod,
  start_ms : UInt64,
) -> Unit {
  if !@fs.exists(self.config.path) {
    self.current_size = 0
    self.ensure_active_file()
    return
  }
  let base = self.config.path + "." + period_stamp(period, start_ms)
  let (dir, name) = split_dir(self.config.path)
  let mut highest : Int64? = None
  for entry in @fs.readdir(dir) {
    if parse_dated_archive(name, period, entry) is Some(archive) &&
      archive.start_ms == start_ms {
      highest = match highest {
        Some(seen) if seen >= archive.sequence => Some(seen)
        _ => Some(archive.sequence)
      }
    }
  }
  let raw = match highest {
    None => base
    Some(seen) => base + "." + (seen + 1L).to_string()
  }
  @fs.rename(self.config.path, raw, replace=false)
  if self.config.gzip {
    self.gzip_file(raw, raw + ".gz")
    self.remove_if_exists(raw)
  }
  self.current_size = 0
  self.ensure_active_file()
  self.prune_dated(period)
  @async.sleep(0)
}

///|
/// Delete dated archives older than `max_age_ms` and all but the newest
/// `max_files`.
#cfg(target="native")
async fn FileSubscriber::prune_dated(
  self : FileSubscriber,
  period : RotationPeriod,
) -> Unit {
  let (dir, base) = split_dir(self.config.path)
  let archives = @fs.readdir(dir).filter_map(name => {
    parse_dated_archive(base, period, name)
  })
  archives.sort_by((a, b) => {
    let by_start = b.start_ms.compare(a.start_ms)
    if by_start != 0 {
      by_start
    } else {
      b.sequence.compare(a.sequence)
    }
  })
  let now = (self.clock)()
  for index, archive in archives {
    let expired = match self.config.max_age_ms {
      Some(max_age) =>
        now > archive.start_ms && now - archive.start_ms > max_age
      None => false
    }
    if expired || index >= self.config.max_files {
      self.remove_if_exists(dir + "/" + archive.name)
    }
  }
}
