///|
/// An in-memory `@io.Writer` collecting everything written to it.
priv struct ByteSink {
  bytes : Array[Byte]
}

///|
impl @io.Writer for ByteSink with fn write_once(self, data, offset~, len~) {
  for i in offset..<(offset + len) {
    self.bytes.push(data[i])
  }
  len
}

///|
/// gzip-compress `body` in memory.
async fn gzip_bytes(body : Bytes) -> Bytes {
  let sink : ByteSink = { bytes: [], }
  let encoder = @gzip.Encoder(sink)
  encoder.write(body)
  encoder.end()
  Bytes::from_array(sink.bytes[:])
}
