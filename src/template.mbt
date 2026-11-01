///|
/// Render a message template by replacing `{key}` with the value of the field
/// named `key`; the last field with that key wins. String values are inserted
/// as text and other values as compact JSON. Placeholders without a matching
/// field, and empty `{}`, are left as written. `{{` and `}}` produce literal
/// braces.
pub fn render_template(template : String, fields : Array[Field]) -> String {
  let values : Map[String, Json] = Map([])
  fields.each(field => values.set(field.key, field.value))
  let chars = template.to_array()
  let buf = StringBuilder()
  let mut i = 0
  while i < chars.length() {
    let ch = chars[i]
    if ch == '{' && i + 1 < chars.length() && chars[i + 1] == '{' {
      buf.write_char('{')
      i += 2
    } else if ch == '}' && i + 1 < chars.length() && chars[i + 1] == '}' {
      buf.write_char('}')
      i += 2
    } else if ch == '{' {
      let mut close = i + 1
      while close < chars.length() && chars[close] != '}' && chars[close] != '{' {
        close += 1
      }
      if close < chars.length() && chars[close] == '}' && close > i + 1 {
        let key = String::from_array(chars[i + 1:close])
        match values.get(key) {
          Some(String(text)) => buf.write_string(text)
          Some(value) => buf.write_string(value.stringify())
          None => buf.write_string("{" + key + "}")
        }
        i = close + 1
      } else {
        buf.write_char(ch)
        i += 1
      }
    } else {
      buf.write_char(ch)
      i += 1
    }
  }
  buf.to_string()
}

///|
/// The fields of a templated event: the caller's fields followed by
/// `message_template`, which wins over a caller field of the same name.
fn template_fields(template : String, fields : Array[Field]) -> Array[Field] {
  let all = fields.filter(field => field.key != "message_template")
  all.push({ key: "message_template", value: Json(template), })
  all
}

///|
/// Emit an event whose message is `template` rendered with `fields` (see
/// `render_template`) and which keeps the unrendered template in a
/// `message_template` field, so events from one call site group together in
/// log backends. With `span`, the event is correlated like `Span::info`.
/// Filters are checked before rendering.
#callsite(autofill(loc))
pub fn log_template(
  level : Level,
  template : String,
  fields~ : Array[Field] = [],
  span? : Span,
  loc~ : SourceLoc,
) -> Unit {
  let source = extract_package(loc)
  if !should_log_module(source, level) {
    return
  }
  let message = render_template(template, fields)
  let all = template_fields(template, fields)
  match span {
    Some(span) =>
      dispatch_in_span_from_source(span, level, message, all, source, loc)
    None => dispatch_from_source(level, message, all, source, loc)
  }
}

///|
/// Emit a templated event through the logger; see `log_template`. Bound
/// fields are available to the template, and the logger's level rules apply
/// before rendering.
#callsite(autofill(loc))
pub fn Logger::log_template(
  self : Logger,
  level : Level,
  template : String,
  fields~ : Array[Field] = [],
  loc~ : SourceLoc,
) -> Unit {
  if !self.admits(level, extract_package(loc)) {
    return
  }
  let message = render_template(
    template,
    merge_logger_fields(self.bound_fields, fields),
  )
  self.event(level, message, fields=template_fields(template, fields), loc~)
}
