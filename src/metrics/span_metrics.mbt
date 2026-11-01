///|
/// OpenTelemetry's default explicit histogram bucket bounds, in milliseconds.
pub let default_duration_buckets_ms : Array[UInt64] = [
  0UL, 5UL, 10UL, 25UL, 50UL, 75UL, 100UL, 250UL, 500UL, 750UL, 1000UL, 2500UL, 5000UL,
  7500UL, 10000UL,
]

///|
priv struct SpanSeries {
  name : String
  kind : @moontrace.SpanKind
  mut count : Int64
  mut errors : Int64
  mut duration_sum_ms : UInt64
  mut duration_min_ms : UInt64
  mut duration_max_ms : UInt64
  bucket_counts : Array[Int64]
}

///|
/// Request rate, error, and duration (RED) metrics derived from completed spans,
/// grouped by span name and kind. Built by `span_metrics`.
pub struct SpanMetrics {
  priv bounds : Array[UInt64]
  priv series : Map[String, SpanSeries]
}

///|
/// One series in a `SpanMetrics::snapshot`.
///
/// `bucket_counts[i]` counts durations `<= bucket_bounds_ms[i]` and above the
/// previous bound; the final entry counts durations above the last bound.
/// Durations use the span clock, which is in milliseconds. `errors` counts
/// spans that closed with `SpanError` status.
pub(all) struct SpanSeriesSnapshot {
  name : String
  kind : @moontrace.SpanKind
  count : Int64
  errors : Int64
  duration_sum_ms : UInt64
  duration_min_ms : UInt64
  duration_max_ms : UInt64
  bucket_bounds_ms : Array[UInt64]
  bucket_counts : Array[Int64]
}

///|
/// Create span-derived metrics. `buckets_ms` are histogram upper bounds in
/// milliseconds; they are sorted and de-duplicated.
pub fn span_metrics(
  buckets_ms~ : Array[UInt64] = default_duration_buckets_ms,
) -> SpanMetrics {
  let bounds = buckets_ms.copy()
  bounds.sort()
  bounds.dedup()
  { bounds, series: Map([]), }
}

///|
/// Record one completed span. `observer()` calls this for every closed,
/// sampled, enabled span; call it directly for spans collected elsewhere.
pub fn SpanMetrics::record(self : SpanMetrics, span : @moontrace.Span) -> Unit {
  let key = "\{span.kind}\u{0}\{span.name}"
  let series = match self.series.get(key) {
    Some(series) => series
    None => {
      let created : SpanSeries = {
        name: span.name,
        kind: span.kind,
        count: 0L,
        errors: 0L,
        duration_sum_ms: 0UL,
        duration_min_ms: 0UL,
        duration_max_ms: 0UL,
        bucket_counts: Array::make(self.bounds.length() + 1, 0L),
      }
      self.series.set(key, created)
      created
    }
  }
  let duration = span.duration()
  if series.count == 0L || duration < series.duration_min_ms {
    series.duration_min_ms = duration
  }
  if duration > series.duration_max_ms {
    series.duration_max_ms = duration
  }
  series.count += 1L
  series.duration_sum_ms += duration
  if span.status == @moontrace.SpanError {
    series.errors += 1L
  }
  let bucket = match self.bounds.search_by(bound => duration <= bound) {
    Some(index) => index
    None => self.bounds.length()
  }
  series.bucket_counts[bucket] += 1L
}

///|
/// A span observer that records every completed span. Combine it with
/// exporters using `@moontrace.compose_span_observers`.
pub fn SpanMetrics::observer(
  self : SpanMetrics,
) -> @moontrace.SpanLifecycleObserver {
  @moontrace.completed_span_observer(span => self.record(span))
}

///|
/// A copy of every series, sorted by name and then kind.
pub fn SpanMetrics::snapshot(self : SpanMetrics) -> Array[SpanSeriesSnapshot] {
  let result = self.series
    .values()
    .map(series => SpanSeriesSnapshot::{
      name: series.name,
      kind: series.kind,
      count: series.count,
      errors: series.errors,
      duration_sum_ms: series.duration_sum_ms,
      duration_min_ms: series.duration_min_ms,
      duration_max_ms: series.duration_max_ms,
      bucket_bounds_ms: self.bounds.copy(),
      bucket_counts: series.bucket_counts.copy(),
    })
    .collect()
  result.sort_by((a, b) => {
    let by_name = lexical_compare(a.name, b.name)
    if by_name != 0 {
      by_name
    } else {
      lexical_compare(a.kind.to_string(), b.kind.to_string())
    }
  })
  result
}

///|
/// Compare strings code unit by code unit, so shorter prefixes sort first.
fn lexical_compare(a : String, b : String) -> Int32 {
  let shared = if a.length() < b.length() { a.length() } else { b.length() }
  for i in 0..<shared {
    let diff = a.code_unit_at(i).to_int() - b.code_unit_at(i).to_int()
    if diff != 0 {
      return diff
    }
  }
  a.length() - b.length()
}

///|
/// Discard all series.
pub fn SpanMetrics::reset(self : SpanMetrics) -> Unit {
  self.series.clear()
}

///|
/// JSON with `name`, `kind`, `count`, `errors`, `duration_ms` (`sum`, `min`,
/// `max`), and `histogram` (`bounds_ms`, `counts`). 64-bit counts are encoded
/// as JSON numbers.
pub fn SpanSeriesSnapshot::to_json(self : SpanSeriesSnapshot) -> Json {
  let duration : Map[String, Json] = Map([])
  duration.set("sum", Json(self.duration_sum_ms.to_double()))
  duration.set("min", Json(self.duration_min_ms.to_double()))
  duration.set("max", Json(self.duration_max_ms.to_double()))
  let histogram : Map[String, Json] = Map([])
  histogram.set(
    "bounds_ms",
    Json(self.bucket_bounds_ms.map(bound => Json(bound.to_double()))),
  )
  histogram.set(
    "counts",
    Json(self.bucket_counts.map(count => Json(count.to_double()))),
  )
  let record : Map[String, Json] = Map([])
  record.set("name", Json(self.name))
  record.set("kind", Json(self.kind.to_string()))
  record.set("count", Json(self.count.to_double()))
  record.set("errors", Json(self.errors.to_double()))
  record.set("duration_ms", Json(duration))
  record.set("histogram", Json(histogram))
  Json(record)
}
