///|
let id_counter : Ref[Int64] = { val: 0L }

///|
pub fn next_trace_id() -> String {
  id_counter.val = id_counter.val + 1L
  let id = id_counter.val
  // Pad to 32 hex chars (OTLP trace ID format)
  let hex = id.to_string()
  let pad = 32 - hex.length()
  let buf = StringBuilder::new()
  for i = 0; i < pad; i = i + 1 {
    buf.write_string("0")
  }
  buf.write_string(hex)
  buf.to_string()
}

///|
pub fn next_span_id() -> String {
  id_counter.val = id_counter.val + 1L
  let id = id_counter.val
  // Pad to 16 hex chars (OTLP span ID format)
  let hex = id.to_string()
  let pad = 16 - hex.length()
  let buf = StringBuilder::new()
  for i = 0; i < pad; i = i + 1 {
    buf.write_string("0")
  }
  buf.write_string(hex)
  buf.to_string()
}
