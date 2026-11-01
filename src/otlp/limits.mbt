///|
/// OpenTelemetry span and log record limits applied by `span_to_otlp` and
/// `event_to_log_record`. Items past a count limit are dropped (the first ones
/// are kept) and counted in the matching `dropped_*_count` field. With
/// `attribute_value_length`, longer string values, including strings inside
/// array values, are truncated to that many characters.
pub(all) struct OtlpLimits {
  attribute_count : Int32
  attribute_value_length : Int32?
  event_count : Int32
  link_count : Int32
}

///|
/// Limits with OpenTelemetry's defaults: 128 attributes, events, and links,
/// and no value-length limit. Negative counts clamp to zero.
pub fn otlp_limits(
  attribute_count~ : Int32 = 128,
  attribute_value_length? : Int32,
  event_count~ : Int32 = 128,
  link_count~ : Int32 = 128,
) -> OtlpLimits {
  let non_negative = (n : Int32) => if n < 0 { 0 } else { n }
  {
    attribute_count: non_negative(attribute_count),
    attribute_value_length: attribute_value_length.map(non_negative),
    event_count: non_negative(event_count),
    link_count: non_negative(link_count),
  }
}

///|
fn truncate_value(value : OtlpValue, max_length : Int32?) -> OtlpValue {
  match (value, max_length) {
    (StringVal(text), Some(limit)) => {
      // Count and cut characters, not UTF-16 code units, so surrogate pairs
      // are never split and short strings stay unchanged.
      let chars = text.to_array()
      if chars.length() > limit {
        StringVal(String::from_array(chars[0:limit]))
      } else {
        value
      }
    }
    (ArrayVal(items), Some(_)) =>
      ArrayVal(items.map(item => truncate_value(item, max_length)))
    _ => value
  }
}

///|
/// Keep the first `limits.attribute_count` attributes, truncating values, and
/// return them with the number dropped.
fn limit_attributes(
  attributes : Array[OtlpAttribute],
  limits : OtlpLimits,
) -> (Array[OtlpAttribute], Int32) {
  let kept = if attributes.length() > limits.attribute_count {
    attributes[0:limits.attribute_count].to_owned()
  } else {
    attributes
  }
  let kept = kept.map(attribute => OtlpAttribute::{
    key: attribute.key,
    value: truncate_value(attribute.value, limits.attribute_value_length),
  })
  (kept, attributes.length() - kept.length())
}

///|
/// Keep the first `limit` items and return them with the number dropped.
fn[T] limit_items(items : Array[T], limit : Int32) -> (Array[T], Int32) {
  if items.length() > limit {
    (items[0:limit].to_owned(), items.length() - limit)
  } else {
    (items, 0)
  }
}
