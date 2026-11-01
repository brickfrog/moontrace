///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend OtlpSignal with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend OtlpSignal with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend OtlpSignal with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend EncodingError with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend EncodingError with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend EncodingError with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend EncodingError with Show::{output}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend OtlpEncoder with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend OtlpEncoder with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend OtlpEncoder with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend ManagedExportStats with Eq::{equal, not_equal}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend ManagedExportStats with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend ExportPartialSuccess with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend ExportPartialSuccess with Compare::{
  compare,
  op_ge,
  op_gt,
  op_le,
  op_lt,
}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend ExportPartialSuccess with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend ExportReport with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend ExportReport with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend ExportReport with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend HttpResponse with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend HttpResponse with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend HttpResponse with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend TransportError with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend TransportError with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend TransportError with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend TransportError with Show::{output}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend RetryClass with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend RetryClass with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend RetryClass with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend ExportOutcome with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend ExportOutcome with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend ExportOutcome with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend MetricReaderStats with Eq::{equal, not_equal}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend MetricReaderStats with @debug.Debug::{to_repr}
