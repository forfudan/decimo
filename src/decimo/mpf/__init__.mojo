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

MPF is an MPFR-backed binary float type, and it is not part of the package's
public interface: `decimo` does not export it, so reaching it means naming
this module, `from decimo.mpf.mpf import MPF`. Nothing here is covered by the
package's promises about its API, and it can change without a major version.
It is kept because it is a second implementation to test the traits against,
the baseline the pure-Mojo float is measured against, and the way anyone
relying on the old MPFR-backed `BigFloat` can go on doing so.

What a user wants instead, in almost every case, is `BigFloat`: a binary
float of the same kind written in Mojo, with no dependency to install, and
correctly rounded in all seven of decimo's rounding modes. `BigDecimal` is
the choice where the arithmetic has to be decimal.

Using MPF takes two things that `BigFloat` does not. MPFR has to be on the
system at run time (`brew install mpfr`, or `apt install libmpfr-dev`), and
the C wrapper that loads it has to be compiled and linked into the program:

    pixi run buildgmp

and then the wrapper object passed to the linker. Without it a program that
calls MPF fails to build with `ld: symbol(s) not found` and no explanation,
which is the one sharp edge of reaching past the public interface. Nothing
that leaves MPF alone needs either: a program that never calls it links
without the wrapper, and MPFR itself is loaded through `dlopen` at the first
call rather than at build time.

Modules:
- mpf: Core MPF struct with constructors, arithmetic, transcendentals
- mpfr_wrapper: Low-level FFI bindings to the MPFR C wrapper
"""

from .mpf import MPF, PRECISION as MPF_PRECISION
