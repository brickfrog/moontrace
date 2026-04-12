///|
// Stretch an 8-byte wall-clock timestamp to 32 bytes using splitmix64-style
// mixing constants. Not cryptographically strong, but sufficient to prevent
// accidental trace-ID collisions between independently-launched processes.
// Two processes starting within the same nanosecond would still collide —
// for adversarial collision resistance, OS entropy would be needed, which
// moonbitlang/core/random does not currently expose.
fn make_seed() -> Bytes {
  let t = @env.now()
  let constants : Array[UInt64] = [
    0UL, 0x9e3779b97f4a7c15UL, 0x6c62272e07bb0142UL, 0x94d049bb133111ebUL,
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
let rng : @random.Rand = @random.Rand::chacha8(seed=make_seed())

///|
fn to_hex_16(val : UInt64) -> String {
  val.to_string(radix=16).pad_start(16, '0')
}

///|
pub fn next_trace_id() -> String {
  let mut hi = rng.uint64()
  let mut lo = rng.uint64()
  // OTLP forbids all-zero trace IDs (probability 2^-128, checked for correctness)
  while hi == 0UL && lo == 0UL {
    hi = rng.uint64()
    lo = rng.uint64()
  }
  to_hex_16(hi) + to_hex_16(lo)
}

///|
pub fn next_span_id() -> String {
  let mut id = rng.uint64()
  // OTLP forbids all-zero span IDs (probability 2^-64, checked for correctness)
  while id == 0UL {
    id = rng.uint64()
  }
  to_hex_16(id)
}
