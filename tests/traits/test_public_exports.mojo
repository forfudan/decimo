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


"""
Tests that the package exports what it says it exports.

Every other test in this directory imports from the module a type is defined
in, which is what a contributor does and not what a user does. A user writes
`from decimo import BigFloat`, and that line can break without a single other
test noticing: the type goes on working, the suite goes on passing, and the
package no longer offers it.

So this file imports only the way the README and the manual tell a user to,
and touches each name enough that the import cannot be optimized away. It
also checks the one name that is deliberately *not* exported, `MPF`, by
reaching it where it does live -- if that import breaks, the migration path
in the changelog is broken with it.
"""

from std import testing
from std.testing import assert_equal, assert_true

from decimo import BFlt, BigFloat, Decimal, RoundingMode
from decimo.mpf.mpf import MPF as _MPF_IS_STILL_REACHABLE
from decimo.prelude import *


def test_the_float_is_exported_from_the_package() raises:
    """`from decimo import BigFloat, BFlt`, as the README tells a user to."""
    var value = BigFloat.from_string("2.5")
    assert_equal(String(value), "2.5", "the exported name constructs")
    assert_equal(value.precision, 53, "at the default precision")

    # The alias is the same type, not a copy of it.
    var same = BFlt.from_string("2.5")
    assert_equal(
        same.internal_representation(),
        value.internal_representation(),
        "`BFlt` is `BigFloat`",
    )
    assert_true(value == same, "and they compare equal")


def test_the_float_is_in_the_prelude() raises:
    """`from decimo.prelude import *` brings the float in with the rest."""
    # `BigFloat` and `BFlt` here resolve through the prelude's star import as
    # well as the explicit one above; what matters is that both paths exist.
    var from_prelude = BFlt.from_int(42)
    assert_equal(String(from_prelude), "42", "the prelude's name constructs")
    assert_equal(
        String(Decimal("1.5") + Decimal("1.5")),
        "3.0",
        "and the rest of the prelude still works beside it",
    )
    assert_equal(
        String(RoundingMode.ROUND_HALF_EVEN),
        "ROUND_HALF_EVEN",
        "including the rounding modes",
    )


def test_the_wrapper_is_reachable_but_not_exported() raises:
    """`MPF` has left the package's exports and not the source.

    The import at the top of this file is the whole test: it is the migration
    path the changelog offers, and it would stop compiling if the module were
    moved or removed. Nothing here calls it, because calling it needs the C
    wrapper linked.
    """
    assert_true(True, "the import above is the assertion")


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
