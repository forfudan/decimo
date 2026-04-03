# ===----------------------------------------------------------------------=== #
# Copyright 2025 Yuhao Zhu
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
# ===----------------------------------------------------------------------=== #

"""Implements the BigFloat type: arbitrary-precision binary floating-point.

BigFloat wraps a single MPFR handle via a C wrapper. Every arithmetic and
transcendental operation is a single MPFR call. Requires MPFR at runtime.

Usage:
    from decimo.bigfloat.bigfloat import BigFloat

    var x = BigFloat("3.14159", precision=1000)
    var r = x.sqrt()
    var bd = r.to_bigdecimal(1000)

Design:
    - Single field: `handle: Int32` (index into C wrapper's mpfr_t handle pool)
    - Precision specified in decimal digits, converted to bits internally
    - Guard bits (64 extra) ensure requested decimal digits are correct
    - RAII: destructor frees MPFR handle via `mpfrw_clear`
"""

from decimo.bigfloat.mpfr_wrapper import (
    mpfrw_available,
    mpfrw_init,
    mpfrw_clear,
    mpfrw_set_str,
    mpfrw_get_str,
    mpfrw_free_str,
    mpfrw_add,
    mpfrw_sub,
    mpfrw_mul,
    mpfrw_div,
    mpfrw_neg,
    mpfrw_abs,
    mpfrw_cmp,
    mpfrw_sqrt,
    mpfrw_exp,
    mpfrw_log,
    mpfrw_sin,
    mpfrw_cos,
    mpfrw_tan,
    mpfrw_pow,
    mpfrw_rootn_ui,
    mpfrw_const_pi,
)

# Guard bits added to user-requested precision to absorb binary↔decimal rounding.
comptime _GUARD_BITS: Int = 64

# Approximate bits per decimal digit: ceil(log2(10)) ≈ 3.322 → use 4 for safety.
comptime _BITS_PER_DIGIT: Int = 4


fn _dps_to_bits(precision: Int) -> Int:
    """Converts decimal digit precision to MPFR bit precision with guard bits.
    """
    return precision * _BITS_PER_DIGIT + _GUARD_BITS


# TODO: Implement BigFloat struct.
#
# struct BigFloat:
#     var handle: Int32
#
#     fn __init__(out self, value: String, precision: Int) raises:
#         ...
#
#     fn __init__(out self, bd: BigDecimal, precision: Int) raises:
#         ...
#
#     fn sqrt(self) raises -> Self:
#         ...
#
#     fn exp(self) raises -> Self:
#         ...
#
#     fn ln(self) raises -> Self:
#         ...
#
#     fn to_bigdecimal(self, precision: Int) raises -> BigDecimal:
#         ...
#
#     fn __del__(owned self):
#         mpfrw_clear(self.handle)
