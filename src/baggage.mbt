///|
/// One W3C Baggage list member. `properties` holds any `;`-separated metadata
/// after the value exactly as received, without the leading `;`.
pub struct BaggageEntry {
  key : String
  value : String
  properties : String
}

///|
/// An immutable set of W3C Baggage entries, passed explicitly alongside a
/// `SpanContext`. Entry order is preserved; setting an existing key replaces
/// its value in place.
pub struct Baggage {
  priv entries : Array[BaggageEntry]
}

///|
/// The most list members moontrace keeps or writes. W3C Baggage requires
/// propagators to support at least 64 members.
pub let baggage_max_members : Int32 = 64

///|
/// The longest `baggage` header moontrace writes, in bytes. W3C Baggage
/// requires propagators to support at least 8192 bytes.
pub let baggage_max_bytes : Int32 = 8192

///|
pub fn Baggage::empty() -> Baggage {
  { entries: [], }
}

///|
pub fn Baggage::len(self : Baggage) -> Int32 {
  self.entries.length()
}

///|
pub fn Baggage::is_empty(self : Baggage) -> Bool {
  self.entries.is_empty()
}

///|
pub fn Baggage::get(self : Baggage, key : String) -> String? {
  for entry in self.entries {
    if entry.key == key {
      return Some(entry.value)
    }
  }
  None
}

///|
/// A copy of the entries in order.
pub fn Baggage::entries(self : Baggage) -> Array[BaggageEntry] {
  self.entries.copy()
}

///|
/// Return baggage with `key` set to `value`. An existing key keeps its
/// position. Returns the baggage unchanged when `key` is not an HTTP token, or
/// when adding a new key would exceed `baggage_max_members`.
pub fn Baggage::set(
  self : Baggage,
  key : String,
  value : String,
  properties~ : String = "",
) -> Baggage {
  if !is_baggage_key(key) {
    return self
  }
  let entry = { key, value, properties: properties.trim().to_owned(), }
  let entries = self.entries.copy()
  match entries.search_by(existing => existing.key == key) {
    Some(index) => entries[index] = entry
    None => {
      if entries.length() >= baggage_max_members {
        return self
      }
      entries.push(entry)
    }
  }
  { entries, }
}

///|
/// Return baggage without `key`.
pub fn Baggage::remove(self : Baggage, key : String) -> Baggage {
  { entries: self.entries.filter(entry => entry.key != key), }
}

///|
/// Format as a W3C `baggage` header value. Values are percent-encoded where
/// required. Members that would push the header past `baggage_max_bytes` are
/// left out.
pub fn Baggage::to_header(self : Baggage) -> String {
  let buf = StringBuilder()
  let mut bytes = 0
  for entry in self.entries {
    let item = StringBuilder()
    item.write_string(entry.key)
    item.write_char('=')
    item.write_string(baggage_encode(entry.value))
    if !entry.properties.is_empty() {
      item.write_char(';')
      item.write_string(entry.properties)
    }
    let item = item.to_string()
    let separator = if bytes == 0 { 0 } else { 1 }
    let size = @utf8.encode(item).length()
    if bytes + separator + size > baggage_max_bytes {
      continue
    }
    if separator == 1 {
      buf.write_char(',')
    }
    buf.write_string(item)
    bytes = bytes + separator + size
  }
  buf.to_string()
}

///|
/// Parse a W3C `baggage` header value. Parsing never fails: malformed members
/// are skipped, a later duplicate key replaces an earlier one, and members
/// past `baggage_max_members` are ignored. Values are percent-decoded; a value
/// that does not decode is kept as received.
pub fn parse_baggage(header : String) -> Baggage {
  let mut baggage = Baggage::empty()
  for raw in header.split(",") {
    let (pair, properties) = match raw.split_once(";") {
      Some((pair, rest)) => (pair, rest.trim().to_owned())
      None => (raw, "")
    }
    guard pair.split_once("=") is Some((key, value)) else { continue }
    let key = key.trim().to_owned()
    let value = value.trim().to_owned()
    if !is_baggage_key(key) || !value.iter().all(is_baggage_value_char) {
      continue
    }
    let decoded = baggage_decode(value).unwrap_or(value)
    baggage = baggage.set(key, decoded, properties~)
  }
  baggage
}

///|
/// RFC 7230 `tchar`, the characters allowed in a baggage key.
fn is_token_char(ch : Char) -> Bool {
  match ch {
    'a'..<='z' | 'A'..<='Z' | '0'..<='9' => true
    '!'
    | '#'
    | '$'
    | '%'
    | '&'
    | '\''
    | '*'
    | '+'
    | '-'
    | '.'
    | '^'
    | '_'
    | '`'
    | '|'
    | '~' => true
    _ => false
  }
}

///|
fn is_baggage_key(key : String) -> Bool {
  !key.is_empty() && key.iter().all(is_token_char)
}

///|
/// W3C `baggage-octet`: printable ASCII except space, `"`, `,`, `;`, and `\`.
fn is_baggage_value_char(ch : Char) -> Bool {
  let code = ch.to_int()
  code >= 0x21 &&
  code <= 0x7e &&
  ch != '"' &&
  ch != ',' &&
  ch != ';' &&
  ch != '\\'
}

///|
fn baggage_encode(value : String) -> String {
  let buf = StringBuilder()
  for byte in @utf8.encode(value) {
    let ch = byte.to_int().unsafe_to_char()
    if byte < b'\x80' && is_baggage_value_char(ch) && ch != '%' {
      buf.write_char(ch)
    } else {
      buf.write_char('%')
      buf.write_string(hex_digit(byte.to_int() / 16).to_upper())
      buf.write_string(hex_digit(byte.to_int() % 16).to_upper())
    }
  }
  buf.to_string()
}

///|
fn baggage_hex_value(ch : Char) -> Int32? {
  match ch {
    '0'..<='9' => Some(ch.to_int() - '0'.to_int())
    'a'..<='f' => Some(ch.to_int() - 'a'.to_int() + 10)
    'A'..<='F' => Some(ch.to_int() - 'A'.to_int() + 10)
    _ => None
  }
}

///|
fn baggage_decode(value : String) -> String? {
  if !value.contains("%") {
    return Some(value)
  }
  let chars = value.to_array()
  let bytes : Array[Byte] = []
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '%' {
      if i + 2 >= chars.length() {
        return None
      }
      match (baggage_hex_value(chars[i + 1]), baggage_hex_value(chars[i + 2])) {
        (Some(high), Some(low)) => bytes.push((high * 16 + low).to_byte())
        _ => return None
      }
      i = i + 3
    } else {
      bytes.push(ch.to_int().to_byte())
      i = i + 1
    }
  }
  Some(@utf8.decode(Bytes::from_array(bytes[:]))) catch {
    _ => None
  }
}
