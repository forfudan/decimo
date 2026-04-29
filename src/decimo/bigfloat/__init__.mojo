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

"""Sub-package for arbitrary-precision binary floating-point type.

BigFloat is an MPFR-backed binary float type. It requires MPFR to be installed
on the system (`brew install mpfr` on macOS, `apt install libmpfr-dev` on Linux).

BigFloat is the fast path for scientific computing at high precision. Every
operation (sqrt, exp, ln, sin, cos, tan, pi, divide) is a single MPFR call.

For exact decimal arithmetic without external dependencies, use BigDecimal instead.

Modules:
- bigfloat: Core BigFloat struct with constructors, arithmetic, transcendentals
- mpfr_wrapper: Low-level FFI bindings to the MPFR C wrapper
"""

from .bigfloat import BigFloat, BFlt, Float, PRECISION as BIGFLOAT_PRECISION
