///|
/// Keeps the first `first` events per key in each window, then every
/// `thereafter`-th event for that key. Built by `burst_sampler`.
pub struct BurstSampler {
  priv inner : (Event) -> Unit
  priv first : Int32
  priv thereafter : Int32
  priv window_ns : UInt64
  priv key : (Event) -> String
  priv clock : () -> UInt64
  priv counts : FixedArray[Int32]
  priv mut window_start : UInt64
  priv mut kept : Int32
  priv mut dropped : Int32
}

///|
/// The default burst key: level and message, so repeats of one log line are
/// sampled together.
pub fn burst_key_level_message(event : Event) -> String {
  "\{event.level}|\{event.message}"
}

///|
/// Burst sampling in the style of zap's `Initial`/`Thereafter` sampler.
///
/// Within each fixed window of `window_ns`, the first `first` events with the
/// same `key` pass through; after that, every `thereafter`-th one does, and
/// `thereafter = 0` drops the rest of the window. Counts are kept in `buckets`
/// hash buckets, so memory is bounded; keys sharing a bucket share a count.
/// `clock` defaults to `@env.now` and can be injected for tests.
pub fn burst_sampler(
  inner : (Event) -> Unit,
  first : Int32,
  thereafter : Int32,
  window_ns : UInt64,
  key~ : (Event) -> String = burst_key_level_message,
  buckets~ : Int32 = 4096,
  clock~ : () -> UInt64 = @env.now,
) -> BurstSampler {
  {
    inner,
    first: if first < 0 {
      0
    } else {
      first
    },
    thereafter: if thereafter < 0 {
      0
    } else {
      thereafter
    },
    window_ns: if window_ns == 0UL {
      1UL
    } else {
      window_ns
    },
    key,
    clock,
    counts: FixedArray::make(if buckets < 1 { 1 } else { buckets }, 0),
    window_start: clock(),
    kept: 0,
    dropped: 0,
  }
}

///|
fn BurstSampler::admit(self : BurstSampler, event : Event) -> Bool {
  let now = (self.clock)()
  if should_reset_window(now, self.window_start, self.window_ns) {
    self.window_start = now
    self.counts.fill(0)
  }
  let bucket = (trace_id_hash((self.key)(event)) %
  self.counts.length().to_uint64()).to_int()
  let count = self.counts[bucket] + 1
  self.counts[bucket] = count
  if count <= self.first {
    true
  } else if self.thereafter > 0 {
    (count - self.first) % self.thereafter == 0
  } else {
    false
  }
}

///|
pub fn BurstSampler::subscriber(self : BurstSampler) -> (Event) -> Unit {
  fn(event) {
    if self.admit(event) {
      self.kept = self.kept + 1
      (self.inner)(event)
    } else {
      self.dropped = self.dropped + 1
    }
  }
}

///|
pub fn BurstSampler::kept(self : BurstSampler) -> Int32 {
  self.kept
}

///|
pub fn BurstSampler::dropped(self : BurstSampler) -> Int32 {
  self.dropped
}

///|
/// Holds recent low-level events and forwards them only when a triggering
/// event arrives. Built by `breadcrumbs`.
pub struct Breadcrumbs {
  priv inner : (Event) -> Unit
  priv trigger : Level
  priv ring : FixedArray[Event?]
  priv mut start : Int32
  priv mut len : Int32
  priv mut flushed : Int32
  priv mut dropped : Int32
}

///|
/// Breadcrumb buffering in the style of Sentry.
///
/// Events below `trigger` are held in a ring of the last `capacity` events and
/// not forwarded. An event at or above `trigger` first flushes the held events
/// to `inner` in arrival order, then is forwarded itself. When the ring is full
/// the oldest held event is discarded and counted in `dropped()`. Held events
/// keep a copy of their field array, so later caller changes do not alter them.
///
/// Compose with an ordinary subscriber to also see low-level events as they
/// happen, for example `compose([console, crumbs.subscriber()])`.
pub fn breadcrumbs(
  inner : (Event) -> Unit,
  capacity~ : Int32 = 100,
  trigger~ : Level = Error_,
) -> Breadcrumbs {
  {
    inner,
    trigger,
    ring: FixedArray::make(if capacity < 1 { 1 } else { capacity }, None),
    start: 0,
    len: 0,
    flushed: 0,
    dropped: 0,
  }
}

///|
pub fn Breadcrumbs::subscriber(self : Breadcrumbs) -> (Event) -> Unit {
  fn(event) {
    if event.level >= self.trigger {
      self.flush()
      (self.inner)(event)
    } else {
      self.hold(event)
    }
  }
}

///|
fn Breadcrumbs::hold(self : Breadcrumbs, event : Event) -> Unit {
  let capacity = self.ring.length()
  let held = Some({ ..event, fields: event.fields.copy(), })
  if self.len < capacity {
    self.ring[(self.start + self.len) % capacity] = held
    self.len = self.len + 1
  } else {
    self.ring[self.start] = held
    self.start = (self.start + 1) % capacity
    self.dropped = self.dropped + 1
  }
}

///|
/// Forward all held events to `inner` in arrival order and empty the ring.
pub fn Breadcrumbs::flush(self : Breadcrumbs) -> Unit {
  let capacity = self.ring.length()
  let held : Array[Event] = []
  for i in 0..<self.len {
    let index = (self.start + i) % capacity
    if self.ring[index] is Some(event) {
      held.push(event)
    }
    self.ring[index] = None
  }
  self.start = 0
  self.len = 0
  self.flushed = self.flushed + held.length()
  held.each(event => (self.inner)(event))
}

///|
/// Discard held events without forwarding them.
pub fn Breadcrumbs::clear(self : Breadcrumbs) -> Unit {
  self.ring.fill(None)
  self.start = 0
  self.len = 0
}

///|
/// Number of events currently held.
pub fn Breadcrumbs::len(self : Breadcrumbs) -> Int32 {
  self.len
}

///|
/// Number of held events forwarded by flushes.
pub fn Breadcrumbs::flushed(self : Breadcrumbs) -> Int32 {
  self.flushed
}

///|
/// Number of held events discarded because the ring was full.
pub fn Breadcrumbs::dropped(self : Breadcrumbs) -> Int32 {
  self.dropped
}
