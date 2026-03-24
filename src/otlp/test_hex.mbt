pub fn to_hex_16(val : UInt64) -> String {
  let chars = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f']
  let buf = StringBuilder::new()
  let v = val
  for i = 0; i < 16; i = i + 1 {
    let shift = (15 - i) * 4
    let nibble = ((v >> shift) & 0xF).to_int()
    buf.write_char(chars[nibble])
  }
  buf.to_string()
}

pub fn now() -> UInt64 {
  @env.now()
}
