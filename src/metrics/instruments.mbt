///|
/// The kind of a collected metric.
pub(all) enum MetricKind {
  /// A monotonic sum from a `Counter`.
  MonotonicSum
  /// A non-monotonic sum from an `UpDownCounter`.
  NonMonotonicSum
  /// An explicit-bucket histogram from a `Histogram`.
  ExplicitHistogram
}

///|
/// One attribute set's cumulative value in a collected metric. For sums only
/// `value` is meaningful; histograms fill `count`, `value` (the sum), `min`,
/// `max`, and `bucket_counts`.
pub(all) struct MetricPoint {
  attributes : Array[@moontrace.Field]
  value : Double
  count : Int64
  min : Double
  max : Double
  bucket_counts : Array[Int64]
}

///|
/// A cumulative snapshot of one instrument, returned by `Meter::collect`.
pub(all) struct MetricData {
  name : String
  description : String
  unit : String
  kind : MetricKind
  bucket_bounds : Array[Double]
  points : Array[MetricPoint]
  start_time_ms : UInt64
  time_ms : UInt64
}

///|
priv struct PointState {
  attributes : Array[@moontrace.Field]
  mut value : Double
  mut count : Int64
  mut min : Double
  mut max : Double
  bucket_counts : Array[Int64]
}

///|
priv struct InstrumentState {
  name : String
  description : String
  unit : String
  kind : MetricKind
  bounds : Array[Double]
  points : Map[String, PointState]
}

///|
/// Creates instruments and collects their cumulative values. Built by
/// `meter`.
pub struct Meter {
  priv name : String
  priv version : String
  priv clock : () -> UInt64
  priv start_time_ms : UInt64
  priv instruments : Array[InstrumentState]
}

///|
/// Create a meter. `name` and `version` become the OTLP instrumentation
/// scope. `clock` returns milliseconds since the Unix epoch; the meter's
/// creation time is the start of every cumulative series.
pub fn meter(
  name~ : String = "moontrace",
  version~ : String = "",
  clock~ : () -> UInt64 = @env.now,
) -> Meter {
  { name, version, clock, start_time_ms: clock(), instruments: [], }
}

///|
/// A monotonic counter. Built by `Meter::counter`.
pub struct Counter {
  priv state : InstrumentState
}

///|
/// A counter that can go up and down. Built by `Meter::up_down_counter`.
pub struct UpDownCounter {
  priv state : InstrumentState
}

///|
/// A distribution of recorded values. Built by `Meter::histogram`.
pub struct Histogram {
  priv state : InstrumentState
}

///|
fn Meter::register(
  self : Meter,
  name : String,
  description : String,
  unit : String,
  kind : MetricKind,
  bounds : Array[Double],
) -> InstrumentState {
  let state : InstrumentState = {
    name,
    description,
    unit,
    kind,
    bounds,
    points: Map([]),
  }
  self.instruments.push(state)
  state
}

///|
/// Create a monotonic counter, e.g. requests served.
pub fn Meter::counter(
  self : Meter,
  name : String,
  description~ : String = "",
  unit~ : String = "",
) -> Counter {
  { state: self.register(name, description, unit, MonotonicSum, []), }
}

///|
/// Create a counter that can decrease, e.g. in-flight requests.
pub fn Meter::up_down_counter(
  self : Meter,
  name : String,
  description~ : String = "",
  unit~ : String = "",
) -> UpDownCounter {
  { state: self.register(name, description, unit, NonMonotonicSum, []), }
}

///|
/// OpenTelemetry's default explicit histogram bounds.
pub let default_histogram_bounds : Array[Double] = [
  0.0, 5.0, 10.0, 25.0, 50.0, 75.0, 100.0, 250.0, 500.0, 750.0, 1000.0, 2500.0, 5000.0,
  7500.0, 10000.0,
]

///|
/// Create a histogram, e.g. request duration in ms. `bounds` are inclusive
/// upper limits; they are sorted and de-duplicated, and a final bucket counts
/// values above the last bound.
pub fn Meter::histogram(
  self : Meter,
  name : String,
  description~ : String = "",
  unit~ : String = "",
  bounds~ : Array[Double] = default_histogram_bounds,
) -> Histogram {
  let sorted = bounds.copy()
  sorted.sort()
  sorted.dedup()
  { state: self.register(name, description, unit, ExplicitHistogram, sorted), }
}

///|
/// Recursively copy JSON containers so stored series and snapshots never share
/// mutable data with callers.
fn copy_json(value : Json) -> Json {
  match value {
    Object(fields) => {
      let copied : Map[String, Json] = Map([])
      fields.each((key, inner) => copied.set(key, copy_json(inner)))
      Json(copied)
    }
    Array(items) => Json(items.map(copy_json))
    other => other
  }
}

///|
fn copy_fields(fields : Array[@moontrace.Field]) -> Array[@moontrace.Field] {
  fields.map(field => { key: field.key, value: copy_json(field.value), })
}

///|
/// A stable key for an attribute set: sorted `key=json` pairs, last value per
/// key winning.
fn attribute_set(
  attributes : Array[@moontrace.Field],
) -> (String, Array[@moontrace.Field]) {
  let latest : Map[String, Json] = Map([])
  attributes.each(field => latest.set(field.key, field.value))
  let keys = latest.keys().collect()
  keys.sort_by(lexical_compare)
  let normalized = keys.map(key => @moontrace.Field::{
    key,
    value: latest.get(key).unwrap(),
  })
  let id = normalized
    .map(field => "\{field.key}=\{field.value.stringify()}")
    .join("\u{0}")
  (id, normalized)
}

///|
fn InstrumentState::point(
  self : InstrumentState,
  attributes : Array[@moontrace.Field],
) -> PointState {
  let (id, normalized) = attribute_set(attributes)
  match self.points.get(id) {
    Some(point) => point
    None => {
      let point : PointState = {
        attributes: copy_fields(normalized),
        value: 0.0,
        count: 0L,
        min: 0.0,
        max: 0.0,
        bucket_counts: Array::make(
          if self.kind is ExplicitHistogram {
            self.bounds.length() + 1
          } else {
            0
          },
          0L,
        ),
      }
      self.points.set(id, point)
      point
    }
  }
}

///|
/// Add a non-negative `value`. Negative values are ignored, as counters only
/// increase.
pub fn Counter::add(
  self : Counter,
  value : Double,
  attributes~ : Array[@moontrace.Field] = [],
) -> Unit {
  if !(value >= 0.0) {
    return
  }
  let point = self.state.point(attributes)
  point.value += value
}

///|
/// Add `value`, which may be negative. NaN values are ignored.
pub fn UpDownCounter::add(
  self : UpDownCounter,
  value : Double,
  attributes~ : Array[@moontrace.Field] = [],
) -> Unit {
  if value != value {
    return
  }
  let point = self.state.point(attributes)
  point.value += value
}

///|
/// Record one value. NaN values are ignored.
pub fn Histogram::record(
  self : Histogram,
  value : Double,
  attributes~ : Array[@moontrace.Field] = [],
) -> Unit {
  if value != value {
    return
  }
  let point = self.state.point(attributes)
  if point.count == 0L || value < point.min {
    point.min = value
  }
  if point.count == 0L || value > point.max {
    point.max = value
  }
  point.count += 1L
  point.value += value
  let bucket = match self.state.bounds.search_by(bound => value <= bound) {
    Some(index) => index
    None => self.state.bounds.length()
  }
  point.bucket_counts[bucket] += 1L
}

///|
/// Cumulative snapshots of every instrument, in creation order, with data
/// points sorted by attribute set. Instruments with no recordings are
/// included with no points.
pub fn Meter::collect(self : Meter) -> Array[MetricData] {
  let now = (self.clock)()
  self.instruments.map(state => {
    let ids = state.points.keys().collect()
    ids.sort_by(lexical_compare)
    let points = ids.map(id => {
      let point = state.points.get(id).unwrap()
      MetricPoint::{
        attributes: copy_fields(point.attributes),
        value: point.value,
        count: point.count,
        min: point.min,
        max: point.max,
        bucket_counts: point.bucket_counts.copy(),
      }
    })
    MetricData::{
      name: state.name,
      description: state.description,
      unit: state.unit,
      kind: state.kind,
      bucket_bounds: state.bounds.copy(),
      points,
      start_time_ms: self.start_time_ms,
      time_ms: now,
    }
  })
}

///|
fn ms_to_ns_string(ms : UInt64) -> String {
  (ms * 1_000_000UL).to_string()
}

///|
fn MetricData::to_otlp_json(self : MetricData) -> Json {
  let points = self.points.map(point => {
    let m : Map[String, Json] = Map([])
    m.set(
      "attributes",
      Json(
        point.attributes.map(field => @otlp.field_to_attribute(field).to_json()),
      ),
    )
    m.set("startTimeUnixNano", Json(ms_to_ns_string(self.start_time_ms)))
    m.set("timeUnixNano", Json(ms_to_ns_string(self.time_ms)))
    match self.kind {
      ExplicitHistogram => {
        m.set("count", Json(point.count.to_string()))
        m.set("sum", Json(point.value))
        m.set(
          "bucketCounts",
          Json(point.bucket_counts.map(count => Json(count.to_string()))),
        )
        m.set("explicitBounds", Json(self.bucket_bounds.map(b => Json(b))))
        if point.count > 0L {
          m.set("min", Json(point.min))
          m.set("max", Json(point.max))
        }
      }
      _ => m.set("asDouble", Json(point.value))
    }
    Json(m)
  })
  let data : Map[String, Json] = Map([])
  data.set("dataPoints", Json(points))
  // AGGREGATION_TEMPORALITY_CUMULATIVE
  data.set("aggregationTemporality", Json(2))
  let metric : Map[String, Json] = Map([])
  metric.set("name", Json(self.name))
  if !self.description.is_empty() {
    metric.set("description", Json(self.description))
  }
  if !self.unit.is_empty() {
    metric.set("unit", Json(self.unit))
  }
  match self.kind {
    MonotonicSum => {
      data.set("isMonotonic", Json(true))
      metric.set("sum", Json(data))
    }
    NonMonotonicSum => {
      data.set("isMonotonic", Json(false))
      metric.set("sum", Json(data))
    }
    ExplicitHistogram => metric.set("histogram", Json(data))
  }
  Json(metric)
}

///|
/// The OTLP instrumentation scope for this meter: its `name` and `version`.
pub fn Meter::scope(self : Meter) -> @otlp.InstrumentationScope {
  @otlp.instrumentation_scope(name=self.name, version=self.version)
}

///|
/// Wrap collected metrics as an OTLP/HTTP JSON `ExportMetricsServiceRequest`.
pub fn metrics_to_otlp_json(
  metrics : Array[MetricData],
  resource~ : @otlp.Resource = @otlp.default_resource(),
  scope~ : @otlp.InstrumentationScope = @otlp.instrumentation_scope(),
) -> Json {
  let scope_metrics : Map[String, Json] = Map([])
  scope_metrics.set("scope", scope.to_json())
  scope_metrics.set(
    "metrics",
    Json(metrics.map(metric => metric.to_otlp_json())),
  )
  let resource_metrics : Map[String, Json] = Map([])
  resource_metrics.set("resource", resource.to_json())
  resource_metrics.set("scopeMetrics", Json([Json(scope_metrics)]))
  let root : Map[String, Json] = Map([])
  root.set("resourceMetrics", Json([Json(resource_metrics)]))
  Json(root)
}

///|
/// Collect and wrap every instrument as an OTLP/HTTP JSON
/// `ExportMetricsServiceRequest`, with this meter as the instrumentation scope.
/// `@transport.OtlpHttpTransport::export_metrics` collects and sends in one
/// step, in JSON or protobuf.
pub fn Meter::to_otlp_json(
  self : Meter,
  resource~ : @otlp.Resource = @otlp.default_resource(),
) -> Json {
  metrics_to_otlp_json(self.collect(), resource~, scope=self.scope())
}
