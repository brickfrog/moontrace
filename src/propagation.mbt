///|
/// Header formats for `inject_headers`.
pub(all) enum PropagationFormat {
  /// W3C `traceparent` and `tracestate`.
  W3C
  /// Zipkin B3 single header: `b3: {trace}-{span}-{sampled}`.
  B3Single
  /// Zipkin B3 multiple headers: `X-B3-TraceId`, `X-B3-SpanId`, `X-B3-Sampled`.
  B3Multi
}

///|
/// Write trace context and baggage into `headers`.
///
/// `format` selects W3C (default) or B3 trace headers. A non-empty `baggage`
/// is written as the W3C `baggage` header in every format, and a non-empty
/// tracestate is written only for W3C. Every existing trace header of any
/// supported format (`traceparent`, `tracestate`, `b3`, `X-B3-*`) is removed
/// first, matching names case-insensitively, so stale headers cannot override
/// `ctx` on extraction.
pub fn inject_headers(
  headers : Map[String, String],
  ctx : SpanContext,
  baggage~ : Baggage = Baggage::empty(),
  format~ : PropagationFormat = W3C,
) -> Unit {
  remove_headers(headers, trace_header_names)
  match format {
    W3C => {
      set_header(headers, "traceparent", format_traceparent(ctx))
      if !ctx.trace_state.is_empty() {
        set_header(headers, "tracestate", ctx.trace_state.to_header())
      }
    }
    B3Single =>
      set_header(
        headers,
        "b3",
        "\{ctx.trace_id}-\{ctx.span_id}-\{if ctx.is_sampled() { "1" } else { "0" }}",
      )
    B3Multi => {
      set_header(headers, "X-B3-TraceId", ctx.trace_id)
      set_header(headers, "X-B3-SpanId", ctx.span_id)
      set_header(
        headers,
        "X-B3-Sampled",
        if ctx.is_sampled() {
          "1"
        } else {
          "0"
        },
      )
    }
  }
  if !baggage.is_empty() {
    let header = baggage.to_header()
    if !header.is_empty() {
      set_header(headers, "baggage", header)
    }
  }
}

///|
/// Write `span`'s trace context and `baggage` into `headers`; see
/// `inject_headers`. Returns `false` and writes no trace headers when the span
/// has invalid IDs.
pub fn inject_span_headers(
  headers : Map[String, String],
  span : Span,
  baggage~ : Baggage = Baggage::empty(),
  format~ : PropagationFormat = W3C,
) -> Bool {
  match span_context_from_span(span) {
    Ok(ctx) => {
      inject_headers(headers, ctx, baggage~, format~)
      true
    }
    Err(_) => false
  }
}

///|
/// Read trace context and baggage from `headers`, matching names
/// case-insensitively. W3C `traceparent` (with `tracestate`) is tried first,
/// then B3 single (`b3`), then B3 multiple headers. Invalid or missing trace
/// headers give `None`; baggage is parsed with `parse_baggage` and is empty
/// when absent. This never raises.
///
/// B3 64-bit trace IDs are left-padded to 128 bits. A B3 sampled value of `1`,
/// `true`, or `d` (debug) means sampled; any other or missing value means not
/// sampled.
pub fn extract_headers(
  headers : Map[String, String],
) -> (SpanContext?, Baggage) {
  let lookup = header_lookup(headers)
  let baggage = match lookup("baggage") {
    Some(value) => parse_baggage(value)
    None => Baggage::empty()
  }
  let ctx = match lookup("traceparent") {
    Some(traceparent) =>
      match
        parse_span_context(
          traceparent.trim().to_owned(),
          tracestate=lookup("tracestate").unwrap_or(""),
        ) {
        Ok(ctx) => Some(ctx)
        Err(_) => None
      }
    None =>
      match lookup("b3") {
        Some(single) => parse_b3_single(single.trim().to_owned())
        None =>
          match (lookup("x-b3-traceid"), lookup("x-b3-spanid")) {
            (Some(trace_id), Some(span_id)) =>
              b3_context(
                trace_id.trim().to_owned(),
                span_id.trim().to_owned(),
                b3_sampled(
                  lookup("x-b3-sampled").unwrap_or(""),
                  lookup("x-b3-flags").unwrap_or(""),
                ),
              )
            _ => None
          }
      }
  }
  (ctx, baggage)
}

///|
/// Lowercase names of every trace-context header `inject_headers` can write or
/// `extract_headers` reads.
let trace_header_names : Array[String] = [
  "traceparent", "tracestate", "b3", "x-b3-traceid", "x-b3-spanid", "x-b3-parentspanid",
  "x-b3-sampled", "x-b3-flags",
]

///|
/// Remove headers whose lowercase names are in `names`.
fn remove_headers(headers : Map[String, String], names : Array[String]) -> Unit {
  let existing = headers
    .keys()
    .filter(key => names.contains(key.to_lower()))
    .collect()
  existing.each(key => headers.remove(key))
}

///|
/// Replace any header named `name` (case-insensitively) with `value`.
fn set_header(
  headers : Map[String, String],
  name : String,
  value : String,
) -> Unit {
  remove_headers(headers, [name.to_lower()])
  headers.set(name, value)
}

///|
fn header_lookup(headers : Map[String, String]) -> (String) -> String? {
  let lowered : Map[String, String] = Map([])
  headers.each((key, value) => lowered.set(key.to_lower(), value))
  name => lowered.get(name)
}

///|
fn b3_sampled(sampled : String, flags : String) -> Bool {
  flags.trim() == "1" ||
  (match sampled.trim().to_lower() {
    "1" | "true" | "d" => true
    _ => false
  })
}

///|
/// Parse `{trace}-{span}[-{sampled}[-{parent}]]` or a bare sampling value.
fn parse_b3_single(value : String) -> SpanContext? {
  let parts = value.split("-").map(part => part.to_owned()).collect()
  if parts.length() < 2 || parts.length() > 4 {
    return None
  }
  let sampled = if parts.length() >= 3 {
    b3_sampled(parts[2], "")
  } else {
    false
  }
  b3_context(parts[0], parts[1], sampled)
}

///|
fn b3_context(
  trace_id : String,
  span_id : String,
  sampled : Bool,
) -> SpanContext? {
  let trace_id = if trace_id.length() == 16 {
    "0000000000000000" + trace_id
  } else {
    trace_id
  }
  let flags = if sampled {
    TraceFlags::sampled()
  } else {
    TraceFlags::unsampled()
  }
  match
    span_context_from_ids(
      trace_id.to_lower(),
      span_id.to_lower(),
      flags~,
      is_remote=true,
    ) {
    Ok(ctx) => Some(ctx)
    Err(_) => None
  }
}
