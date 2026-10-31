///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend EnvFilterError with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend EnvFilterError with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend EnvFilterError with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend EnvFilterError with Show::{output}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend ParsedFilter with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend Event with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend Event with Show::{output}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend Field with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend Field with Show::{output}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend Level with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend Level with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend Level with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend Level with Show::{output}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend RedactionMode with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend RedactionMode with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend RedactionMode with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend RedactionMode with Show::{output}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend RedactionPolicy with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend Span with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend SpanKind with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend SpanKind with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend SpanKind with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend SpanKind with Show::{output}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend SpanStatus with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend SpanStatus with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend SpanStatus with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend SpanStatus with Show::{output}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend SpanLinkKind with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend SpanLinkKind with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend SpanLinkKind with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend SpanLink with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend SpanLinkKind with Show::{output}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend Span with Show::{output}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend TraceContextError with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend TraceContextError with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend TraceContextError with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend TraceContextError with Show::{output}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend TraceId with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend TraceId with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend TraceId with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend SpanId with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend SpanId with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend SpanId with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend TraceFlags with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend TraceFlags with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend TraceFlags with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend TraceStateEntry with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend TraceStateEntry with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend TraceStateEntry with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend TraceState with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend SpanContext with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend TraceId with Show::{output}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend SpanId with Show::{output}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend TraceFlags with Show::{output}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend SpanEvent with @debug.Debug::{to_repr}
