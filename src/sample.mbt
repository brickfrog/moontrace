///|
fn sampling_seed() -> Bytes {
  let t = @env.now()
  let constants : Array[UInt64] = [
    0x243f6a8885a308d3UL, 0x13198a2e03707344UL, 0xa4093822299f31d0UL, 0x082efa98ec4e6c89UL,
  ]
  let arr : Array[Byte] = Array::make(32, b'\x00')
  for seg in 0..<4 {
    let v = t ^ constants[seg]
    for i in 0..<8 {
      arr[seg * 8 + i] = (v >> ((7 - i) * 8)).to_byte()
    }
  }
  Bytes::from_array(arr[:])
}

///|
let sampling_rng : @random.Rand = @random.Rand::chacha8(seed=sampling_seed())

///|
fn default_sampling_rand() -> Double {
  sampling_rng.double()
}

///|
fn clamp_sampling_ratio(ratio : Double) -> Double {
  match (ratio <= 0.0, ratio >= 1.0) {
    (true, _) => 0.0
    (_, true) => 1.0
    _ => ratio
  }
}

///|
fn keep_by_ratio(ratio : Double, rand : () -> Double) -> Bool {
  let ratio = clamp_sampling_ratio(ratio)
  match (ratio <= 0.0, ratio >= 1.0) {
    (true, _) => false
    (_, true) => true
    _ => rand() < ratio
  }
}

///|
pub(all) struct RatioSampler {
  inner : (Event) -> Unit
  ratio : Double
  rand : () -> Double
  mut kept : Int
  mut dropped : Int
}

///|
pub fn ratio_sampler(
  inner : (Event) -> Unit,
  ratio : Double,
  rand? : () -> Double = default_sampling_rand,
) -> RatioSampler {
  { inner, ratio: clamp_sampling_ratio(ratio), rand, kept: 0, dropped: 0 }
}

///|
pub fn RatioSampler::subscriber(self : RatioSampler) -> (Event) -> Unit {
  fn(event) {
    match keep_by_ratio(self.ratio, self.rand) {
      true => {
        self.kept = self.kept + 1
        (self.inner)(event)
      }
      false => self.dropped = self.dropped + 1
    }
  }
}

///|
pub fn RatioSampler::kept(self : RatioSampler) -> Int {
  self.kept
}

///|
pub fn RatioSampler::dropped(self : RatioSampler) -> Int {
  self.dropped
}

///|
pub(all) struct RateLimiter {
  inner : (Event) -> Unit
  limit : Int
  window_ns : UInt64
  clock : () -> UInt64
  mut window_start : UInt64
  mut count : Int
  mut kept : Int
  mut dropped : Int
}

///|
pub fn rate_limiter(
  inner : (Event) -> Unit,
  limit : Int,
  window_ns : UInt64,
  clock? : () -> UInt64 = @env.now,
) -> RateLimiter {
  {
    inner,
    limit,
    window_ns,
    clock,
    window_start: clock(),
    count: 0,
    kept: 0,
    dropped: 0,
  }
}

///|
fn should_reset_window(
  now : UInt64,
  window_start : UInt64,
  window_ns : UInt64,
) -> Bool {
  match now >= window_start {
    true => now - window_start >= window_ns
    false => false
  }
}

///|
pub fn RateLimiter::subscriber(self : RateLimiter) -> (Event) -> Unit {
  fn(event) {
    let now = (self.clock)()
    match should_reset_window(now, self.window_start, self.window_ns) {
      true => {
        self.window_start = now
        self.count = 0
      }
      false => ()
    }
    match self.count < self.limit {
      true => {
        self.count = self.count + 1
        self.kept = self.kept + 1
        (self.inner)(event)
      }
      false => self.dropped = self.dropped + 1
    }
  }
}

///|
pub fn RateLimiter::kept(self : RateLimiter) -> Int {
  self.kept
}

///|
pub fn RateLimiter::dropped(self : RateLimiter) -> Int {
  self.dropped
}

///|
fn hex_value_for_sampling(unit : Int) -> UInt64 {
  if unit >= 48 && unit <= 57 {
    (unit - 48).to_uint64()
  } else if unit >= 65 && unit <= 70 {
    (unit - 55).to_uint64()
  } else if unit >= 97 && unit <= 102 {
    (unit - 87).to_uint64()
  } else {
    0UL
  }
}

///|
fn trace_id_hash(trace_id : String) -> UInt64 {
  let mut hash = 14695981039346656037UL
  for i in 0..<trace_id.length() {
    hash = hash ^ trace_id.code_unit_at(i).to_int().to_uint64()
    hash = hash * 1099511628211UL
  }
  hash
}

///|
fn trace_id_unit(trace_id : String) -> Double {
  let mut hash = trace_id_hash(trace_id)
  let limit = if trace_id.length() >= 16 { 16 } else { trace_id.length() }
  for i in 0..<limit {
    hash = (hash << 4) ^
      hex_value_for_sampling(trace_id.code_unit_at(i).to_int())
  }
  Double::convert_uint64(hash << 11 >> 11) / Double::convert_uint64(1UL << 53)
}

///|
pub fn should_sample_trace(trace_id : String, ratio : Double) -> Bool {
  let ratio = clamp_sampling_ratio(ratio)
  match (ratio <= 0.0, ratio >= 1.0) {
    (true, _) => false
    (_, true) => true
    _ => trace_id_unit(trace_id) < ratio
  }
}

///|
pub fn sample_trace_decision(
  parent_flags : TraceFlags?,
  trace_id : String,
  ratio : Double,
) -> Bool {
  match parent_flags {
    Some(flags) => flags.is_sampled()
    None => should_sample_trace(trace_id, ratio)
  }
}

///|
fn trace_id_field(event : Event) -> String? {
  for field in event.fields {
    if field.key == "trace_id" {
      match field.value {
        String(trace_id) => return Some(trace_id)
        _ => return None
      }
    }
  }
  None
}

///|
pub(all) struct TraceSampler {
  inner : (Event) -> Unit
  ratio : Double
  mut kept : Int
  mut dropped : Int
}

///|
pub fn trace_sampler(inner : (Event) -> Unit, ratio : Double) -> TraceSampler {
  { inner, ratio: clamp_sampling_ratio(ratio), kept: 0, dropped: 0 }
}

///|
pub fn TraceSampler::subscriber(self : TraceSampler) -> (Event) -> Unit {
  fn(event) {
    match trace_id_field(event) {
      Some(trace_id) =>
        match should_sample_trace(trace_id, self.ratio) {
          true => {
            self.kept = self.kept + 1
            (self.inner)(event)
          }
          false => self.dropped = self.dropped + 1
        }
      None => {
        self.kept = self.kept + 1
        (self.inner)(event)
      }
    }
  }
}

///|
pub fn TraceSampler::kept(self : TraceSampler) -> Int {
  self.kept
}

///|
pub fn TraceSampler::dropped(self : TraceSampler) -> Int {
  self.dropped
}
