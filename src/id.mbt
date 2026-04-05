///|
let id_counter : Ref[UInt64] = { val: (0x8000000000000000 : UInt64) }

///|
fn to_hex_16(val : UInt64) -> String {
  val.to_string(radix=16).pad_start(16, '0')
}

///|
pub fn next_trace_id() -> String {
  id_counter.val = id_counter.val + (1 : UInt64)
  let time_part = @env.now()
  let counter_part = id_counter.val
  to_hex_16(time_part) + to_hex_16(counter_part)
}

///|
pub fn next_span_id() -> String {
  id_counter.val = id_counter.val + (1 : UInt64)
  to_hex_16(id_counter.val)
}
