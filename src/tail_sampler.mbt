///|
/// What a tail sampling policy sees when a trace is decided.
pub(all) struct TraceSummary {
  trace_id : String
  /// Completed spans buffered for the trace, in completion order.
  spans : Array[Span]
  /// Whether any buffered span closed with `SpanError` status.
  has_error : Bool
  /// The longest buffered span duration, in milliseconds.
  max_duration_ms : UInt64
  /// Whether the trace was decided before it finished: because it timed out,
  /// was evicted to bound memory, hit `max_spans_per_trace`, or was flushed.
  forced : Bool
}

///|
/// A policy that keeps traces with an error, traces whose longest span took at
/// least `min_duration_ms`, and otherwise a deterministic `ratio` of trace IDs
/// (the same hash as `trace_sampler`).
pub fn tail_policy(
  keep_errors~ : Bool = true,
  min_duration_ms? : UInt64,
  ratio~ : Double = 0.0,
) -> (TraceSummary) -> Bool {
  summary => {
    (keep_errors && summary.has_error) ||
    (min_duration_ms is Some(min) && summary.max_duration_ms >= min) ||
    should_sample_trace(summary.trace_id, ratio)
  }
}

///|
priv struct PendingTrace {
  started_ms : UInt64
  spans : Array[Span]
  events : Array[Event]
  mut open : Int32
}

///|
/// Buffers completed spans and span-correlated events per trace and decides
/// when the trace finishes whether to forward them. Built by `tail_sampler`.
pub struct TailSampler {
  priv inner : SpanLifecycleObserver
  priv policy : (TraceSummary) -> Bool
  priv max_traces : Int32
  priv max_spans_per_trace : Int32
  priv max_events_per_trace : Int32
  priv trace_timeout_ms : UInt64
  priv clock : () -> UInt64
  priv pending : Map[String, PendingTrace]
  priv order : Array[String]
  priv decided : Map[String, Bool]
  priv decided_order : Array[String]
  priv mut event_sink : ((Event) -> Unit)?
  priv mut kept : Int64
  priv mut dropped : Int64
  priv mut forced : Int64
}

///|
/// Tail sampling, like the OpenTelemetry collector's tail sampler or
/// Honeycomb Refinery.
///
/// Install `observer()` as the span observer and, optionally, wrap the event
/// subscriber with `subscriber(inner)`. Spans of each trace are buffered until
/// every locally created span of the trace has closed; then `policy` decides.
/// Kept traces are delivered to `inner` as completed spans (`on_closed` only,
/// as with `completed_span_observer`) and their buffered events go to the
/// wrapped subscriber; dropped traces are discarded.
///
/// Memory is bounded: past `max_traces` pending traces the oldest is decided
/// early, a trace is decided early on reaching `max_spans_per_trace` completed
/// spans or `max_events_per_trace` held events, and
/// traces pending longer than `trace_timeout_ms` (for example with spans that
/// never close) are decided on the next callback. Early decisions set
/// `TraceSummary.forced`. Call `flush()` at shutdown. `clock` returns
/// milliseconds and can be injected for tests.
pub fn tail_sampler(
  inner : SpanLifecycleObserver,
  policy~ : (TraceSummary) -> Bool = tail_policy(),
  max_traces~ : Int32 = 1000,
  max_spans_per_trace~ : Int32 = 1000,
  max_events_per_trace~ : Int32 = 1000,
  trace_timeout_ms~ : UInt64 = 30_000UL,
  clock~ : () -> UInt64 = @env.now,
) -> TailSampler {
  {
    inner,
    policy,
    max_traces: if max_traces < 1 {
      1
    } else {
      max_traces
    },
    max_spans_per_trace: if max_spans_per_trace < 1 {
      1
    } else {
      max_spans_per_trace
    },
    max_events_per_trace: if max_events_per_trace < 1 {
      1
    } else {
      max_events_per_trace
    },
    trace_timeout_ms,
    clock,
    pending: Map([]),
    order: [],
    decided: Map([]),
    decided_order: [],
    event_sink: None,
    kept: 0L,
    dropped: 0L,
    forced: 0L,
  }
}

///|
/// Traces kept so far.
pub fn TailSampler::kept(self : TailSampler) -> Int64 {
  self.kept
}

///|
/// Traces dropped so far.
pub fn TailSampler::dropped(self : TailSampler) -> Int64 {
  self.dropped
}

///|
/// Traces decided before they finished (timeout, eviction, span limit, or
/// flush).
pub fn TailSampler::forced(self : TailSampler) -> Int64 {
  self.forced
}

///|
/// Traces currently buffered.
pub fn TailSampler::pending(self : TailSampler) -> Int32 {
  self.pending.length()
}

///|
fn TailSampler::remember(
  self : TailSampler,
  trace_id : String,
  keep : Bool,
) -> Unit {
  // Keep one order entry per trace so evicting an old entry can never remove
  // a newer decision for the same trace.
  self.decided_order.retain(id => id != trace_id)
  self.decided_order.push(trace_id)
  self.decided.set(trace_id, keep)
  // Remember as many decisions as traces may be pending, for late events.
  while self.decided_order.length() > self.max_traces {
    let oldest = self.decided_order.remove(0)
    self.decided.remove(oldest)
  }
}

///|
fn TailSampler::decide(
  self : TailSampler,
  trace_id : String,
  forced : Bool,
) -> Unit {
  guard self.pending.get(trace_id) is Some(trace) else { return }
  self.pending.remove(trace_id)
  self.order.retain(id => id != trace_id)
  let mut has_error = false
  let mut max_duration_ms = 0UL
  for span in trace.spans {
    if span.status == SpanError {
      has_error = true
    }
    if span.duration() > max_duration_ms {
      max_duration_ms = span.duration()
    }
  }
  let keep = (self.policy)({
    trace_id,
    // Independent snapshots, so a policy that mutates them cannot change the
    // spans replayed to `inner`.
    spans: trace.spans.map(span_snapshot),
    has_error,
    max_duration_ms,
    forced,
  })
  if forced {
    self.forced += 1L
  }
  self.remember(trace_id, keep)
  if keep {
    self.kept += 1L
    trace.spans.each(span => (self.inner.on_closed)(span))
    match self.event_sink {
      Some(sink) => trace.events.each(sink)
      None => ()
    }
  } else {
    self.dropped += 1L
  }
}

///|
/// Decide traces that have been pending longer than the timeout.
fn TailSampler::expire(self : TailSampler) -> Unit {
  let now = (self.clock)()
  let expired = self.order.filter(id => {
    match self.pending.get(id) {
      Some(trace) =>
        now > trace.started_ms &&
        now - trace.started_ms >= self.trace_timeout_ms
      None => false
    }
  })
  expired.each(id => self.decide(id, true))
}

///|
fn TailSampler::trace_for(
  self : TailSampler,
  trace_id : String,
) -> PendingTrace {
  match self.pending.get(trace_id) {
    Some(trace) => trace
    None => {
      let trace : PendingTrace = {
        started_ms: (self.clock)(),
        spans: [],
        events: [],
        open: 0,
      }
      self.pending.set(trace_id, trace)
      self.order.push(trace_id)
      while self.order.length() > self.max_traces {
        self.decide(self.order[0], true)
      }
      trace
    }
  }
}

///|
/// The span observer to install with `set_span_observer`.
pub fn TailSampler::observer(self : TailSampler) -> SpanLifecycleObserver {
  span_lifecycle_observer(
    on_created=span => {
      self.expire()
      if self.decided.contains(span.trace_id) {
        // A late span for a decided trace starts a fresh pending trace.
        self.decided.remove(span.trace_id)
        self.decided_order.retain(id => id != span.trace_id)
      }
      let trace = self.trace_for(span.trace_id)
      trace.open += 1
    },
    on_closed=span => {
      self.expire()
      guard self.pending.get(span.trace_id) is Some(trace) else {
        // A span created before the sampler was installed: decide alone.
        let trace = self.trace_for(span.trace_id)
        trace.spans.push(span)
        self.decide(span.trace_id, false)
        return
      }
      trace.spans.push(span)
      trace.open -= 1
      if trace.spans.length() >= self.max_spans_per_trace {
        self.decide(span.trace_id, true)
      } else if trace.open <= 0 {
        self.decide(span.trace_id, false)
      }
    },
  )
}

///|
/// Wrap an event subscriber. Events whose `trace_id` belongs to a pending
/// trace are held until it is decided and forwarded only if it is kept;
/// events for recently dropped traces are discarded; all other events pass
/// straight through.
pub fn TailSampler::subscriber(
  self : TailSampler,
  inner : (Event) -> Unit,
) -> (Event) -> Unit {
  self.event_sink = Some(inner)
  event => {
    self.expire()
    let trace_id = event.fields
      .iter()
      .fold(init=None, (found, field) => {
        match (field.key, field.value) {
          ("trace_id", String(id)) => Some(id)
          _ => found
        }
      })
    match trace_id {
      Some(id) =>
        match self.pending.get(id) {
          Some(trace) => {
            trace.events.push({ ..event, fields: event.fields.copy(), })
            if trace.events.length() >= self.max_events_per_trace {
              self.decide(id, true)
            }
          }
          None =>
            match self.decided.get(id) {
              Some(false) => ()
              _ => inner(event)
            }
        }
      None => inner(event)
    }
  }
}

///|
/// Decide every pending trace now, for example at shutdown.
pub fn TailSampler::flush(self : TailSampler) -> Unit {
  self.order.copy().each(id => self.decide(id, true))
}
