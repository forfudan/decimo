"""
Sweeps `BigUInt`'s Toom-3 over the shapes its three-way split produces.

`multiply_slices_toom3` had no test of its own. It splits the longer operand
into three parts of `ceil(n_max / 3)` words and the shorter one into whatever
that leaves -- possibly a short or empty top part -- and then interpolates
through five products. The shapes worth sitting on are the residue of the
longer length modulo three, and the shorter length at each part boundary.

The oracle is the inverse operation: `(x * y) // y == x` with a zero
remainder, through the public operators. `BigUInt`'s division is well covered
and was itself just repaired on a shape this sweep would have hit.

A note on what not to use as the oracle here. The first version of this sweep
compared Toom-3 against `multiply_slices_schoolbook` called directly, and
reported 24 mismatches. Every one was the schoolbook: its column accumulator
holds `SCHOOLBOOK_MAX_COLUMN` products, 340 at eighteen digits a word, and a
341-word column overflows it. The dispatchers never send it that much, so the
kernel is correct in its contract -- and now asserts the contract -- but it
cannot be called on operands wider than the cutoff and trusted.
"""

from std import testing
from std.testing import assert_true

from decimo.biguint.biguint import BigUInt
from decimo.biguint import arithmetics as biguint_arithmetics


def repeated(digit: String, count: Int) -> String:
    var out = String("")
    for _ in range(count):
        out += digit
    return out^


def assert_product_inverts(x: BigUInt, y: BigUInt, context: String) raises:
    var product = x * y
    var remainder = BigUInt()
    var back = biguint_arithmetics.floor_divide_modulo(product, y, remainder)
    assert_true(remainder.is_zero(), context + ": (x * y) % y != 0")
    assert_true(back == x, context + ": (x * y) // y != x")


def test_every_residue_of_the_three_way_split() raises:
    comptime KARATSUBA = biguint_arithmetics.CUTOFF_KARATSUBA
    comptime TOOM3 = biguint_arithmetics.CUTOFF_TOOM3
    comptime DIGITS = BigUInt.DIGITS_PER_WORD
    for n_max in [TOOM3 + 1, TOOM3 + 2, TOOM3 + 3, 3 * 200, 3 * 200 + 1]:
        var m = (n_max + 2) // 3
        # The shorter operand at each boundary of the split: just past the
        # Karatsuba guard, one part, two parts, and equal, each a word either
        # side.
        for n_min in [
            KARATSUBA + 1,
            m - 1,
            m,
            m + 1,
            2 * m - 1,
            2 * m,
            2 * m + 1,
            n_max,
        ]:
            if n_min > n_max or n_min <= KARATSUBA:
                continue
            for pattern in [String("9"), String("1")]:
                var x = BigUInt(repeated(pattern, n_max * DIGITS))
                var y = BigUInt(repeated(pattern, n_min * DIGITS))
                assert_product_inverts(
                    x,
                    y,
                    pattern
                    + "s, "
                    + String(n_max)
                    + " by "
                    + String(n_min)
                    + " words",
                )


def test_the_schoolbook_column_bound_is_where_the_comment_said() raises:
    """`SCHOOLBOOK_MAX_COLUMN` is derived; this pins that it derives to 340.

    If the base or the word type changes, the bound moves and this test says
    so -- which is the point, since the dispatch cutoffs would need looking at
    too.
    """
    testing.assert_equal(biguint_arithmetics.SCHOOLBOOK_MAX_COLUMN, 340)
    testing.assert_true(
        biguint_arithmetics.CUTOFF_KARATSUBA
        < biguint_arithmetics.SCHOOLBOOK_MAX_COLUMN,
        "the Karatsuba cutoff must stay below the schoolbook column bound",
    )


def main() raises:
    testing.TestSuite.discover_tests[__functions_in_module()]().run()
