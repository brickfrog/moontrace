///|
const DEFAULT_MAX_SIZE_BYTES : Int = 10 * 1024 * 1024

///|
const DEFAULT_MAX_FILES : Int = 5

///|
const DEFAULT_MAX_BATCH : Int = 128

///|
const DEFAULT_QUEUE_CAPACITY : Int = 1024

///|
pub(all) struct FileSubscriberConfig {
  path : String
  max_size_bytes : Int
  max_files : Int
  gzip : Bool
  max_batch : Int
  queue_capacity : Int
} derive(Eq, Compare, Debug)

///|
pub fn FileSubscriberConfig::new(
  path : String,
  max_size_bytes? : Int = DEFAULT_MAX_SIZE_BYTES,
  max_files? : Int = DEFAULT_MAX_FILES,
  gzip? : Bool = false,
  max_batch? : Int = DEFAULT_MAX_BATCH,
  queue_capacity? : Int = DEFAULT_QUEUE_CAPACITY,
) -> FileSubscriberConfig {
  {
    path,
    max_size_bytes: clamp_positive(max_size_bytes),
    max_files: clamp_non_negative(max_files),
    gzip,
    max_batch: clamp_positive(max_batch),
    queue_capacity: clamp_positive(queue_capacity),
  }
}

///|
#cfg(target="native")
struct FileSubscriber {
  config : FileSubscriberConfig
  queue : @aqueue.Queue[String]
  write_lock : @aqueue.Queue[Unit]
  mut initialized : Bool
  mut current_size : Int
  mut enqueued_count : Int
  mut written_count : Int
  mut dropped_count : Int
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
  max_size_bytes? : Int = DEFAULT_MAX_SIZE_BYTES,
  max_files? : Int = DEFAULT_MAX_FILES,
  gzip? : Bool = false,
  max_batch? : Int = DEFAULT_MAX_BATCH,
  queue_capacity? : Int = DEFAULT_QUEUE_CAPACITY,
) -> FileSubscriber {
  FileSubscriber::new(
    FileSubscriberConfig::new(
      path,
      max_size_bytes~,
      max_files~,
      gzip~,
      max_batch~,
      queue_capacity~,
    ),
  )
}

///|
#cfg(target="native")
pub fn FileSubscriber::new(config : FileSubscriberConfig) -> FileSubscriber {
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
pub fn FileSubscriber::new(_config : FileSubscriberConfig) -> FileSubscriber {
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
pub fn FileSubscriber::dropped(self : FileSubscriber) -> Int {
  self.dropped_count_impl()
}

///|
#cfg(target="native")
pub fn FileSubscriber::written(self : FileSubscriber) -> Int {
  self.written_count
}

///|
#cfg(not(target="native"))
pub fn FileSubscriber::written(_self : FileSubscriber) -> Int {
  0
}

///|
#cfg(target="native")
fn FileSubscriber::dropped_count_impl(self : FileSubscriber) -> Int {
  self.dropped_count
}

///|
#cfg(not(target="native"))
fn FileSubscriber::dropped_count_impl(_self : FileSubscriber) -> Int {
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
fn clamp_positive(value : Int) -> Int {
  if value < 1 {
    1
  } else {
    value
  }
}

///|
fn clamp_non_negative(value : Int) -> Int {
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
fn byte_len(data : String) -> Int {
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
  let builder = StringBuilder::new()
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
    append=true,
  )
}

///|
#cfg(target="native")
async fn FileSubscriber::rotate(self : FileSubscriber) -> Unit {
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
  index : Int,
) -> String {
  self.config.path + "." + index.to_string()
}

///|
#cfg(target="native")
fn FileSubscriber::rotated_path(self : FileSubscriber, index : Int) -> String {
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
    permission=0o600,
  )
  defer writer.close()
  let encoder = @gzip.Encoder(writer)
  encoder.write(reader.read_all())
  encoder.end()
  @async.sleep(0)
}
