///|
let id_counter : Ref[Int64] = { val: 0L }

///|
fn int64_to_hex(n : Int64, width : Int) -> String {
  let hex_chars = "0123456789abcdef"
  let buf = StringBuilder::new()
  let mut val = n
  if val < 0L {
    val = -val
  }
  if val == 0L {
    buf.write_string("0")
  } else {
    let digits : Array[String] = []
    while val > 0L {
      let rem = (val % 16L).to_int()
      digits.push(hex_chars[rem].to_string())
      val = val / 16L
    }
    // Reverse
    let mut i = digits.length() - 1
    while i >= 0 {
      buf.write_string(digits[i])
      i = i - 1
    }
  }
  let hex = buf.to_string()
  let pad = width - hex.length()
  if pad <= 0 {
    return hex
  }
  let result = StringBuilder::new()
  for j = 0; j < pad; j = j + 1 {
    result.write_string("0")
  }
  result.write_string(hex)
  result.to_string()
}

///|
pub fn next_trace_id() -> String {
  id_counter.val = id_counter.val + 1L
  int64_to_hex(id_counter.val, 32)
}

///|
pub fn next_span_id() -> String {
  id_counter.val = id_counter.val + 1L
  int64_to_hex(id_counter.val, 16)
}
