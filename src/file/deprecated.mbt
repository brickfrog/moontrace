///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend FileSubscriberConfig with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend FileSubscriberConfig with Compare::{
  compare,
  op_ge,
  op_gt,
  op_le,
  op_lt,
}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend FileSubscriberConfig with @debug.Debug::{to_repr}

///|
#deprecated("use `==` or `!=` instead")
#doc(hidden)
pub extend RotationPeriod with Eq::{equal, not_equal}

///|
#deprecated("use comparison operators or `Compare::compare` instead")
#doc(hidden)
pub extend RotationPeriod with Compare::{compare, op_ge, op_gt, op_le, op_lt}

///|
#deprecated("use `@debug.to_string` or `Debug::to_repr` instead")
#doc(hidden)
pub extend RotationPeriod with @debug.Debug::{to_repr}
