///|
/// A span observer that writes one line per completed span, like Rust
/// tracing-subscriber's `FmtSpan::CLOSE`; see `@moontrace.format_span_close`
/// for the layout. Spans shorter than `min_duration_ms` are skipped. Install it
/// with `@moontrace.set_span_observer`, or combine it with exporters using
/// `@moontrace.compose_span_observers`.
pub fn span_observer(
  output~ : (String) -> Unit = fn(s) { println(s) },
  color~ : Bool = true,
  format_timestamp~ : (UInt64) -> String = @moontrace.format_timestamp_utc,
  min_duration_ms~ : UInt64 = 0UL,
) -> @moontrace.SpanLifecycleObserver {
  @moontrace.completed_span_observer(span => {
    if span.duration() < min_duration_ms {
      return
    }
    output(@moontrace.format_span_close(span, color~, format_timestamp~))
  })
}
