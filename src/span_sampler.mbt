///|
/// Data a `SpanSampler` sees when a span is created.
///
/// `parent` is `None` for root spans. For child spans it holds the parent's
/// trace flags, and `parent_is_remote` reports whether the parent came from
/// an extracted `SpanContext` rather than a local `Span`.
pub(all) struct SamplingInput {
  trace_id : String
  name : String
  kind : SpanKind
  fields : Array[Field]
  parent : TraceFlags?
  parent_is_remote : Bool
}

///|
/// Head-sampling decision run when a span is created.
///
/// The decision sets the span's sampled trace flag. Unsampled spans still get
/// IDs and still propagate through `traceparent`, but span observers (and the
/// exporters built on them) do not receive them.
pub struct SpanSampler {
  priv decide : (SamplingInput) -> Bool
}

///|
/// Build a sampler from a custom decision function.
pub fn span_sampler(decide : (SamplingInput) -> Bool) -> SpanSampler {
  { decide, }
}

///|
pub fn SpanSampler::should_sample(
  self : SpanSampler,
  input : SamplingInput,
) -> Bool {
  (self.decide)(input)
}

///|
/// Sample every span, ignoring any parent decision.
pub fn always_on_sampler() -> SpanSampler {
  span_sampler(_ => true)
}

///|
/// Sample no spans, ignoring any parent decision.
pub fn always_off_sampler() -> SpanSampler {
  span_sampler(_ => false)
}

///|
/// Sample a deterministic `ratio` of traces by trace ID. The decision uses the
/// same trace-ID hash as `should_sample_trace` and `trace_sampler`, so spans
/// and events sampled at the same ratio agree.
pub fn trace_id_ratio_sampler(ratio : Double) -> SpanSampler {
  let ratio = clamp_sampling_ratio(ratio)
  span_sampler(input => should_sample_trace(input.trace_id, ratio))
}

///|
/// Follow the parent's sampled flag, local or remote, and use `root` only for
/// spans without a parent.
pub fn parent_based_sampler(root : SpanSampler) -> SpanSampler {
  span_sampler(input => {
    match input.parent {
      Some(flags) => flags.is_sampled()
      None => root.should_sample(input)
    }
  })
}

///|
fn default_span_sampler() -> SpanSampler {
  parent_based_sampler(always_on_sampler())
}

///|
let global_span_sampler : Ref[SpanSampler] = { val: default_span_sampler(), }

///|
/// Install the sampler consulted by `span`, `span_with_trace`, `child_span`,
/// and `span_from_remote_context`. The default is
/// `parent_based_sampler(always_on_sampler())`.
pub fn set_span_sampler(sampler : SpanSampler) -> Unit {
  global_span_sampler.val = sampler
}

///|
/// Restore the default `parent_based_sampler(always_on_sampler())`.
pub fn reset_span_sampler() -> Unit {
  global_span_sampler.val = default_span_sampler()
}

///|
/// Run `f` with a scoped span sampler, then restore the previous tracing
/// globals. This is a synchronous scope, not task-local async propagation.
pub fn[T] with_span_sampler(
  sampler : SpanSampler,
  f : () -> T raise?,
) -> T raise? {
  with_trace_state(() => {
    set_span_sampler(sampler)
    f()
  })
}

///|
/// Run the installed sampler and return the new span's trace flags. Child
/// spans keep the parent's other flag bits.
fn sampled_trace_flags(
  trace_id : String,
  name : String,
  kind : SpanKind,
  fields : Array[Field],
  parent~ : TraceFlags? = None,
  parent_is_remote~ : Bool = false,
) -> Int32 {
  let sampled = global_span_sampler.val.should_sample({
    trace_id,
    name,
    kind,
    fields: fields.copy(),
    parent,
    parent_is_remote,
  })
  let base = match parent {
    Some(flags) => flags
    None => TraceFlags::unsampled()
  }
  base.with_sampled(sampled).to_int()
}

///|
/// Report whether the span's sampled trace flag is set.
pub fn Span::is_sampled(self : Span) -> Bool {
  span_trace_flags(self).is_sampled()
}
