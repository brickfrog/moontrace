///|
let hex_chars = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
let id_counter : Ref[UInt64] = { val: (0x8000000000000000 : UInt64) }

///|
fn to_hex_16(val : UInt64) -> String {
  let buf = StringBuilder::new()
  for i = 0; i < 16; i = i + 1 {
    let shift = (15 - i) * 4
    let nibble = ((val >> shift) & (0xF : UInt64)).to_int()
    buf.write_char(hex_chars[nibble])
  }
  buf.to_string()
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
