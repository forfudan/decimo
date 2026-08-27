"""Number-theoretic transform multiplication for base-2^64 magnitudes.

Multiplying two `n`-word magnitudes is a convolution of their digit sequences,
and a convolution is a pointwise product under a discrete Fourier transform.
Toom-3 gets the exponent down to `log_3(5) = 1.465` by evaluating at five
points; the transform evaluates at `L` points at once and brings the exponent
down to `n log n`.

The transform runs over the integers modulo the Goldilocks prime

    P = 2^64 - 2^32 + 1

rather than over the complex numbers, so every value is exact and there is no
error analysis to get wrong: the answer either is the product or is not, and
the tests decide which. `P - 1 = 2^32 * (2^32 - 1)` is divisible by `2^32`, so
`P` has primitive roots of unity of every power-of-two order up to `2^32`,
which is the only property the transform needs. It also sits just under `2^64`,
so a residue is one machine word and reduction after a multiplication costs a
shift, a subtract and two conditional fixups rather than a division.

Reduction rests on `2^64 = 2^32 - 1 (mod P)`. Writing a 128-bit product as
`hi * 2^64 + lo` and `hi` as `h1 * 2^32 + h0`,

    hi * 2^64 + lo = lo - h1 + h0 * (2^32 - 1)   (mod P)

and each of the three terms is already a single word, so `mod_mul()` finishes
with one subtract and one add. See `mod_mul()` for why no term can overflow.

The operands are re-cut before the transform. A base-2^64 magnitude is a bit
string, and nothing forces the transform to see it in word-sized pieces: cutting it
into `chunk_bits`-bit pieces instead trades the number of coefficients against
how large each convolution coefficient can grow. That freedom is what
`_plan()` spends, and it is worth up to a factor of two - see there.
"""

from std.bit import count_leading_zeros
from std.memory import unsafe_memset_zero

from decimo.bigint.bigint import Magnitude

# ===----------------------------------------------------------------------=== #
# Field arithmetic modulo the Goldilocks prime
# ===----------------------------------------------------------------------=== #

comptime NTT_PRIME: UInt64 = 0xFFFF_FFFF_0000_0001
"""The Goldilocks prime `2^64 - 2^32 + 1`."""

comptime _P_COMPLEMENT: UInt64 = 0xFFFF_FFFF
"""`2^64 - NTT_PRIME`, the amount a wrapped 64-bit sum is short by."""

comptime _NTT_GENERATOR: UInt64 = 7
"""A primitive root modulo `NTT_PRIME`, so `7^((P-1)/2^k)` has order `2^k`."""

comptime MAX_TRANSFORM_LOG: Int = 32
"""`P - 1` is divisible by `2^32` and no more, capping the transform length."""


@always_inline
def mod_add(a: UInt64, b: UInt64) -> UInt64:
    """Adds two residues already reduced into `[0, P)`.

    A wrapped sum is short by `2^64`, and `2^64 = 2^32 - 1 (mod P)`, so the
    fixup adds `_P_COMPLEMENT` rather than subtracting `P`. That add cannot
    itself wrap: the true sum is below `2 * P`, so the wrapped value is below
    `2 * P - 2^64 = 2^64 - 2^33 + 2`.
    """
    var total = a + b
    if total < a:
        return total + _P_COMPLEMENT
    if total >= NTT_PRIME:
        return total - NTT_PRIME
    return total


@always_inline
def mod_sub(a: UInt64, b: UInt64) -> UInt64:
    """Subtracts two residues already reduced into `[0, P)`."""
    if a >= b:
        return a - b
    return NTT_PRIME - (b - a)


@always_inline
def mod_mul(a: UInt64, b: UInt64) -> UInt64:
    """Multiplies two residues already reduced into `[0, P)`.

    With the product written `hi * 2^64 + lo` and `hi = h1 * 2^32 + h0`, the
    identity `2^64 = 2^32 - 1 (mod P)` gives `lo - h1 + h0 * (2^32 - 1)`. Each
    term reduces to `[0, P)` on its own before the two additions:

    - `lo` is a full word, so one conditional subtract suffices.
    - `h1 < 2^32 < P` already.
    - `h0 * (2^32 - 1)` is written `(h0 << 32) - h0`, which needs no wider
      arithmetic: `h0 < 2^32` makes the shift exact, and the subtract cannot
      go negative. Its value is at most `(2^32 - 1)^2 = 2^64 - 2^33 + 1`,
      which is below `P`, so it is reduced already.
    """
    var product = UInt128(a) * UInt128(b)
    var lo = UInt64(product & 0xFFFF_FFFF_FFFF_FFFF)
    var hi = UInt64(product >> 64)
    var h0 = hi & 0xFFFF_FFFF
    var h1 = hi >> 32
    var reduced_lo = lo - NTT_PRIME if lo >= NTT_PRIME else lo
    return mod_add(mod_sub(reduced_lo, h1), (h0 << 32) - h0)


def mod_power(base: UInt64, exponent: UInt64) -> UInt64:
    """Raises `base` to `exponent` modulo `NTT_PRIME`."""
    var result: UInt64 = 1
    var current = base
    var remaining = exponent
    while remaining > 0:
        if (remaining & 1) != 0:
            result = mod_mul(result, current)
        current = mod_mul(current, current)
        remaining >>= 1
    return result


# ===----------------------------------------------------------------------=== #
# Choosing the transform length and the chunk width
# ===----------------------------------------------------------------------=== #


@fieldwise_init
struct _TransformPlan(Copyable, Movable):
    """How one product will be cut up and transformed."""

    var chunk_bits: Int
    """Width in bits of each transform coefficient taken from the operands."""
    var coefficients_a: Int
    """Number of coefficients the first operand occupies."""
    var coefficients_b: Int
    """Number of coefficients the second operand occupies."""
    var log_length: Int
    """Base-two logarithm of the transform length."""
    var length: Int
    """The transform length, a power of two."""


def _plan(bits_a: Int, bits_b: Int) -> _TransformPlan:
    """Chooses the cheapest chunk width and transform length for one product.

    The transform costs `L log L` for a length `L` that must be a power of two,
    so the whole game is to make `L` small. Cutting the operands into
    `chunk_bits`-bit coefficients pulls in two directions:

    - Wider chunks mean fewer coefficients, so a shorter transform.
    - Wider chunks mean larger coefficients. A convolution coefficient is a sum
      of at most `min(coefficients_a, coefficients_b)` products of two chunks,
      and it must stay below `P` or the answer wraps and is silently wrong.

    Fixing the chunk width at 16 bits - one half-word, the obvious choice -
    leaves the transform length rounding up to a power of two on its own, and
    the rounding is pure waste. At 10 400 words a 16-bit cut needs 41 599
    coefficients and so a transform of 65 536, where 25 bits needs 26 623 and
    fits in 32 768: the same product, half the transform. Letting the width
    float lands the coefficient count just under a power of two instead, which
    is worth a factor of two whenever the fixed width overshoots and nothing
    when it does not.

    The search runs the width up while the magnitude bound holds. That bound
    fails monotonically - the coefficient count falls like `1/chunk_bits` while
    the square of a chunk grows like `4^chunk_bits` - so the first failure ends
    it.

    Args:
        bits_a: Bit length of the first operand, rounded up to whole words.
        bits_b: Bit length of the second operand, rounded up to whole words.

    Returns:
        The plan to hand to `_multiply_planned()`.
    """
    var best_bits = 1
    var best_a = bits_a
    var best_b = bits_b

    for chunk_bits in range(1, 33):
        var count_a = (bits_a + chunk_bits - 1) // chunk_bits
        var count_b = (bits_b + chunk_bits - 1) // chunk_bits
        var terms = UInt128(min(count_a, count_b))
        var chunk_max = UInt128((UInt64(1) << UInt64(chunk_bits)) - 1)
        if terms * chunk_max * chunk_max >= UInt128(NTT_PRIME):
            break
        best_bits = chunk_bits
        best_a = count_a
        best_b = count_b

    var needed = best_a + best_b - 1
    var log_length = 0
    while (1 << log_length) < needed:
        log_length += 1

    return _TransformPlan(
        best_bits, best_a, best_b, log_length, 1 << log_length
    )


# ===----------------------------------------------------------------------=== #
# Twiddle tables
# ===----------------------------------------------------------------------=== #


def build_twiddles(
    log_length: Int, mut forward: List[UInt64], mut inverse: List[UInt64]
):
    """Fills the per-level twiddle tables for a transform of `2^log_length`.

    Both transforms walk one level at a time, and within a level the twiddle
    index advances by one per butterfly. Storing each level's twiddles
    contiguously therefore turns what would be a strided gather into a linear
    scan. The levels have sizes `L/2, L/4, ..., 1`, so the concatenation fits
    in `L` entries with one to spare.

    Only the top-level powers `w^k` are chained; every lower level is a stride
    subsample of that one, because `w_(L/2)^j = w_L^(2j)`. Chaining each level
    separately would multiply the serial dependency, and the chain is the one
    part of the build that cannot be overlapped.

    Args:
        log_length: Base-two logarithm of the transform length.
        forward: Destination for the decimation-in-frequency twiddles.
        inverse: Destination for the decimation-in-time twiddles.
    """
    var length = 1 << log_length
    var half = length >> 1
    var root = mod_power(_NTT_GENERATOR, (NTT_PRIME - 1) >> UInt64(log_length))

    # `root^k` for `k < half`, generated in blocks rather than as one chain.
    # Chaining every power makes the build latency-bound on `mod_mul()` for
    # `half` steps in a row; splitting it into blocks of about `sqrt(half)`
    # leaves only `sqrt(half)` steps on the chain and makes the rest - one
    # independent multiply per entry - throughput-bound instead.
    var powers = List[UInt64](capacity=half if half > 0 else 1)
    powers.resize(unsafe_uninit_length=half if half > 0 else 1)
    var power_scratch = powers.unsafe_ptr()
    if half > 0:
        var block = 1
        while block * block < half:
            block <<= 1

        var current: UInt64 = 1
        var head = min(block, half)
        for j in range(head):
            power_scratch[unsafe_offset=j] = current
            current = mod_mul(current, root)

        var step = current  # root^block
        var start = step
        var base = block
        while base < half:
            var count = min(block, half - base)
            for j in range(count):
                power_scratch[unsafe_offset=base + j] = mod_mul(
                    start, power_scratch[unsafe_offset=j]
                )
            start = mod_mul(start, step)
            base += block

    forward.resize(unsafe_uninit_length=length)
    inverse.resize(unsafe_uninit_length=length)
    var power_ptr = powers.unsafe_ptr()
    var forward_ptr = forward.unsafe_ptr()
    var inverse_ptr = inverse.unsafe_ptr()

    # Forward level `l` halves a block of `length >> l`, so its twiddles are
    # `w^(j << l)` and there are `length >> (l + 1)` of them. The levels before
    # it have used `length - (length >> l)` entries.
    for level in range(log_length):
        var offset = length - (length >> level)
        var count = length >> (level + 1)
        for j in range(count):
            forward_ptr[unsafe_offset=offset + j] = power_ptr[
                unsafe_offset=j << level
            ]

    # Inverse level `l` joins blocks of `2 << l`, so its twiddles are the
    # conjugates `w^(-(j << (log_length - 1 - l)))` and there are `1 << l` of
    # them. `w^(-k) = w^(L - k) = -w^(L/2 - k)`, which is where the negation
    # comes from; the table of positive powers is the only one stored.
    for level in range(log_length):
        var offset = (1 << level) - 1
        var count = 1 << level
        var shift = log_length - 1 - level
        for j in range(count):
            var k = j << shift
            if k == 0:
                inverse_ptr[unsafe_offset=offset + j] = UInt64(1)
            else:
                inverse_ptr[unsafe_offset=offset + j] = (
                    NTT_PRIME - power_ptr[unsafe_offset=half - k]
                )


# ===----------------------------------------------------------------------=== #
# The transforms
# ===----------------------------------------------------------------------=== #


def transform_forward[
    o: Origin[mut=True]
](
    values: Pointer[UInt64, o],
    length: Int,
    log_length: Int,
    twiddles: Pointer[UInt64, _],
):
    """Decimation-in-frequency transform: natural order in, bit-reversed out.

    Pairing this with a decimation-in-time inverse is what lets both skip the
    bit-reversal permutation entirely - the pointwise product in the middle
    does not care what order the points are in, as long as both operands agree.

    The last level is peeled off because its only twiddle is `1`, and a
    multiplication by one over `length / 2` butterflies is not free.
    """
    var block = length
    var level = 0
    while block > 2:
        var half = block >> 1
        var offset = length - (length >> level)
        var start = 0
        while start < length:
            for j in range(half):
                var low = values[unsafe_offset=start + j]
                var high = values[unsafe_offset=start + j + half]
                values[unsafe_offset=start + j] = mod_add(low, high)
                values[unsafe_offset=start + j + half] = mod_mul(
                    mod_sub(low, high), twiddles[unsafe_offset=offset + j]
                )
            start += block
        block = half
        level += 1

    if length >= 2:
        var start = 0
        while start < length:
            var low = values[unsafe_offset=start]
            var high = values[unsafe_offset=start + 1]
            values[unsafe_offset=start] = mod_add(low, high)
            values[unsafe_offset=start + 1] = mod_sub(low, high)
            start += 2


def transform_inverse[
    o: Origin[mut=True]
](
    values: Pointer[UInt64, o],
    length: Int,
    log_length: Int,
    twiddles: Pointer[UInt64, _],
):
    """Decimation-in-time transform: bit-reversed order in, natural out.

    Undoes `transform_forward()` up to the factor of `length` that a
    forward-then-inverse pair leaves behind, which the final scaling removes.
    The first level is peeled off for the same reason the forward transform
    peels its last: the twiddle there is `1`.
    """
    if length >= 2:
        var start = 0
        while start < length:
            var low = values[unsafe_offset=start]
            var high = values[unsafe_offset=start + 1]
            values[unsafe_offset=start] = mod_add(low, high)
            values[unsafe_offset=start + 1] = mod_sub(low, high)
            start += 2

    var block = 4
    var level = 1
    while block <= length:
        var half = block >> 1
        var offset = (1 << level) - 1
        var start = 0
        while start < length:
            for j in range(half):
                var low = values[unsafe_offset=start + j]
                var high = mod_mul(
                    values[unsafe_offset=start + j + half],
                    twiddles[unsafe_offset=offset + j],
                )
                values[unsafe_offset=start + j] = mod_add(low, high)
                values[unsafe_offset=start + j + half] = mod_sub(low, high)
            start += block
        block <<= 1
        level += 1

    var scale = mod_power(UInt64(length) % NTT_PRIME, NTT_PRIME - 2)
    for k in range(length):
        values[unsafe_offset=k] = mod_mul(values[unsafe_offset=k], scale)


# ===----------------------------------------------------------------------=== #
# Packing magnitudes into coefficients and back
# ===----------------------------------------------------------------------=== #


def _pack[
    o: Origin[mut=True]
](
    destination: Pointer[UInt64, o],
    words: ImmSpan[UInt64, _],
    count: Int,
    chunk_bits: Int,
):
    """Cuts `words` into `count` chunks of `chunk_bits` bits each, LSB first.

    A chunk starts at an arbitrary bit offset, so the read takes the two words
    straddling it and shifts. `_plan()` never returns a width above 32, so a
    chunk never spans more than two words however the offset falls.
    """
    var word_count = len(words)
    var source = words.unsafe_ptr()
    var mask = (UInt64(1) << UInt64(chunk_bits)) - 1
    for i in range(count):
        var bit = i * chunk_bits
        var index = bit >> 6
        var shift = bit & 63
        var low = source[unsafe_offset=index] if index < word_count else UInt64(
            0
        )
        var high = source[
            unsafe_offset=index + 1
        ] if index + 1 < word_count else UInt64(0)
        # A shift of a whole word is undefined, and at offset zero there is
        # nothing above to pull down anyway.
        var value = low >> UInt64(shift)
        if shift != 0:
            value |= high << UInt64(64 - shift)
        destination[unsafe_offset=i] = value & mask


def _unpack(
    coefficients: Pointer[UInt64, _],
    count: Int,
    chunk_bits: Int,
    word_count: Int,
) -> Magnitude:
    """Reassembles `sum(coefficients[k] * 2^(k * chunk_bits))` into words.

    The coefficients overlap once `chunk_bits` is not a multiple of the step,
    and each is far wider than its own chunk - it is a sum of products, not a
    chunk - so this is a carry propagation rather than a concatenation.

    The walk steps 32 bits at a time even though the words are 64, which is
    what keeps the accumulator inside 128 bits: the coefficients landing on
    one step number about `32 / chunk_bits`, each below `2^62` and shifted by
    at most 31. Stepping a whole word instead would shift by up to 63 and
    take twice as many of them, and the accumulator would no longer fit.
    """
    var result = Magnitude(capacity=word_count)
    result.resize(unsafe_uninit_length=word_count)
    var destination = result.unsafe_ptr()
    var half_count = word_count << 1

    var accumulator = UInt128(0)
    var next_half = 0
    for k in range(count):
        var bit = k * chunk_bits
        var index = bit >> 5
        var shift = bit & 31
        while next_half < index and next_half < half_count:
            var piece = UInt64(accumulator & 0xFFFF_FFFF)
            if next_half & 1 == 0:
                destination[unsafe_offset=next_half >> 1] = piece
            else:
                destination[unsafe_offset=next_half >> 1] |= piece << 32
            accumulator >>= 32
            next_half += 1
        if next_half >= half_count:
            break
        accumulator += UInt128(coefficients[unsafe_offset=k]) << UInt128(shift)

    while next_half < half_count:
        var piece = UInt64(accumulator & 0xFFFF_FFFF)
        if next_half & 1 == 0:
            destination[unsafe_offset=next_half >> 1] = piece
        else:
            destination[unsafe_offset=next_half >> 1] |= piece << 32
        accumulator >>= 32
        next_half += 1

    var length = word_count
    while length > 1 and result[length - 1] == 0:
        length -= 1
    while len(result) > length:
        result.shrink(len(result) - 1)
    return result^


# ===----------------------------------------------------------------------=== #
# Entry point
# ===----------------------------------------------------------------------=== #


def _bit_length(words: ImmSpan[UInt64, _]) -> Int:
    """Returns the bit length of a magnitude, or zero for a zero magnitude."""
    var top = len(words)
    while top > 0 and words[top - 1] == 0:
        top -= 1
    if top == 0:
        return 0
    return top * 64 - Int(count_leading_zeros(words[top - 1]))


comptime CUTOFF_NTT: Int = 1024
"""Below this many words the transform is never considered.

A floor, not the crossover: `should_multiply_ntt()` decides the crossover from
the cost models, and it never chooses the transform anywhere near here. This
only keeps the planning arithmetic off the path of the small multiplications
that dominate the recursion of every other algorithm.
"""

comptime _NTT_RELATIVE_COST: Float64 = 0.34
"""Cost of one `L * log2(L)` transform step against one `n^1.465` Toom-3 step.

It was 1.10 while a word was 32 bits. Both terms are written over word counts,
and only one of them still means the same thing at 64: the transform's `L`
comes from the *bit* length, which a wider word leaves alone, while Toom-3's
`n^1.465` is over words, and the same value now has half as many. So the
constant had to be re-fitted rather than reasoned about, and the crossover
moved from about 8 000 words to about 2 300.

Measured against Toom-3 on the same operands, Apple Silicon arm64, best of
three (microseconds):

    words     2048   2304   2560   3072   3584    4096    8192   16384
    Toom-3     545    645    681    955   1234    1562    3845   11353
    transform  581    589    596    595   1220    1221    2610    5780

The transform is flat inside a transform length and steps when `L` doubles,
which is why the winner alternates rather than crossing once -- and why the
answer has to come from comparing the two models rather than from a word
count. Every size above wants `_NTT_RELATIVE_COST` below its own
`toom3_cost / (L * log2 L)`: 0.309 at 2048 (where Toom-3 wins, so the constant
must be at least that) and 0.368 at 2304 (where the transform does). 0.34 sits
between them, which gets every measured size right except 3584, where it picks
Toom-3 and gives up 1.1%. A tie going to Toom-3 is the right way round, since
it allocates far less. Adjust if benchmarking on another target shows better.
"""


def should_multiply_ntt(len_a: Int, len_b: Int) -> Bool:
    """Reports whether the transform is the cheaper way to form this product.

    A flat word count cannot answer this. The transform length has to be a
    power of two, so its cost climbs in steps while Toom-3's climbs smoothly,
    and the winner alternates: the transform loses at 2 048 words, wins from
    2 304 to 3 072, loses again at 3 584 where `L` has just doubled, and wins
    everywhere above. What settles it is comparing the two cost models
    directly.

    Toom-3's `n^1.465` is written over the operand area so that it still means
    something when the operands differ in size - `(len_a * len_b)^0.7325` is
    exactly `n^1.465` when they do not.

    Args:
        len_a: Word count of the first operand.
        len_b: Word count of the second operand.

    Returns:
        True if the transform should be used.
    """
    if len_a < CUTOFF_NTT or len_b < CUTOFF_NTT:
        return False

    var plan = _plan(len_a * 64, len_b * 64)
    if plan.log_length > MAX_TRANSFORM_LOG:
        return False

    var transform_cost = (
        Float64(plan.length) * Float64(plan.log_length) * _NTT_RELATIVE_COST
    )
    var toom3_cost = (Float64(len_a) * Float64(len_b)) ** 0.7325
    return transform_cost < toom3_cost


def multiply_magnitudes_ntt(
    a: ImmSpan[UInt64, _], b: ImmSpan[UInt64, _]
) -> Magnitude:
    """Multiplies two magnitudes through a number-theoretic transform.

    The caller guarantees both operands are non-empty and non-zero.
    `should_multiply_ntt()` answers whether this is the cheaper way to form a
    given product, and rejects any size whose transform length would exceed
    `MAX_TRANSFORM_LOG`; correctness here does not depend on going through it,
    only cost does.

    Args:
        a: First magnitude (little-endian UInt64 words).
        b: Second magnitude (little-endian UInt64 words).

    Returns:
        The product magnitude as a new word list.
    """
    var plan = _plan(_bit_length(a), _bit_length(b))
    var length = plan.length

    var forward_twiddles = List[UInt64]()
    var inverse_twiddles = List[UInt64]()
    build_twiddles(plan.log_length, forward_twiddles, inverse_twiddles)

    var left = List[UInt64](capacity=length)
    left.resize(unsafe_uninit_length=length)
    var right = List[UInt64](capacity=length)
    right.resize(unsafe_uninit_length=length)
    var left_ptr = left.unsafe_ptr()
    var right_ptr = right.unsafe_ptr()

    unsafe_memset_zero(ptr=left_ptr, count=length)
    unsafe_memset_zero(ptr=right_ptr, count=length)
    _pack(left_ptr, a, plan.coefficients_a, plan.chunk_bits)
    _pack(right_ptr, b, plan.coefficients_b, plan.chunk_bits)

    var forward_ptr = forward_twiddles.unsafe_ptr()
    var inverse_ptr = inverse_twiddles.unsafe_ptr()
    transform_forward(left_ptr, length, plan.log_length, forward_ptr)
    transform_forward(right_ptr, length, plan.log_length, forward_ptr)
    for i in range(length):
        left_ptr[unsafe_offset=i] = mod_mul(
            left_ptr[unsafe_offset=i], right_ptr[unsafe_offset=i]
        )
    transform_inverse(left_ptr, length, plan.log_length, inverse_ptr)

    return _unpack(
        left_ptr,
        plan.coefficients_a + plan.coefficients_b - 1,
        plan.chunk_bits,
        len(a) + len(b),
    )
