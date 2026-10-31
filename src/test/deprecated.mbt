///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend SpanLifecycleKind with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend SpanLifecycleKind with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend SpanLifecycleKind with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend SpanLifecycleEvent with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend CapturedRecord with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend EventQuery with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend LifecycleQuery with @debug.Debug::{to_repr}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend TestSubscriber with @debug.Debug::{to_repr}

///|
#deprecated("use `Show::output` instead")
#doc(hidden)
pub extend SpanLifecycleKind with Show::{output}
