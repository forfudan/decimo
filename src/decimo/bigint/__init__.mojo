# ===----------------------------------------------------------------------=== #
# Copyright 2025-2026 Yuhao Zhu
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

"""Sub-package for binary base-2^32 big integer type.

BigInt is a signed arbitrary-precision integer that uses base-2^32
representation internally. This is the binary counterpart to BigInt10 (base-10^9).

`BInt` now names BigInt. BigInt10 is no longer referenced by any other module
of the library: the base-10^9 side of the bridge is `to_biguint()` /
`from_biguint()`, which speak `BigUInt` directly, and BigInt10 itself carries
`to_bigint()` / `from_bigint()` for the code that still wants it. The module is
kept for now, but nothing depends on it.

Modules:
- bigint: Core struct with constructors, conversions, dunders
- arithmetics: add, subtract, multiply, divide, modulo, power, shifts
- bitwise: AND, OR, XOR, NOT (Python two's complement semantics)
- comparison: compare, greater, less, equal
- exponential: sqrt, isqrt
- number_theory: gcd, extended_gcd, lcm, mod_pow, mod_inverse
- special: factorial (and future special functions)
"""
