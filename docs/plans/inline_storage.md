# Inline storage for `BigUInt`

> Written 2026-08-27, mid-work. If the session ended before this was finished,
> everything needed to continue is here.

## The finding

A small `BigUInt` operation is **97% allocation**. Measured in Mojo, best of
nine, `-D ASSERT=none`:

```
add_inplace 4w += 1w (no alloc):   1.2 ns
add         4w +  1w (allocates): 40.0 ns
```

The same shape shows up as a flat cost that does not depend on size at all:

| operands | `BigUInt.add` |
| -------- | ------------- |
| 1w + 1w  | 36.7 ns       |
| 4w + 4w  | 49.3 ns       |
| 16w + 16w| 55.0 ns       |
| 64w + 64w| 67.2 ns       |

About 36 ns of fixed cost, then roughly 0.5 ns per word. The fixed part is
`List[UInt32]` allocating the result buffer, through
`pop.aligned_alloc` -- not even plain `malloc`.

## Why it matters

CPython's `decimal` embeds the coefficient in the object:
`_decimal.c` gives `PyDecObject` a `data[_Py_DEC_MINALLOC]` array, four
64-bit words, which is 76 decimal digits. So at the default precision of 28
digits **libmpdec allocates nothing at all**, and we allocate twice per
operation.

That is the whole gap at small sizes. From Python at 28 digits, after the
binding work of 2026-08-27:

| | decimo | decimal |
| --- | --- | --- |
| `a + b` | 120 ns | 43 ns |
| `a * b` | 128 ns | 49 ns |
| `a < b` | 39 ns | 18 ns |

`a < b` allocates nothing and is the closest of the three. Take 38 ns of
allocation out of `a + b` and it lands near 82 ns, which is about twice
`decimal` -- the target.

## The change

Replace `BigUInt.words: List[UInt32]` with a `WordList` that keeps up to
`INLINE_WORDS` words inside the struct and only reaches for the heap beyond
that. Four words is 36 decimal digits, which covers the default precision of
28 with room to spare; eight is worth considering if the struct size turns out
not to matter.

### The API to mirror

846 references to `.words` across `src/`, but only these methods are used:

| method         | uses |
| -------------- | ---- |
| `unsafe_ptr()` | 75   |
| `append()`     | 49   |
| `shrink()`     | 14   |
| `resize()`     | 12   |
| `clear()`      | 11   |
| `copy()`       | 10   |
| `_data`        | 3    |
| `unsafe_set()` | 2    |

Plus `len()`, `[]`, `[] =`, iteration, and the constructors
`List[UInt32](capacity=)`, `List[UInt32](unsafe_uninit_length=)` and
construction from a literal list.

If `WordList` matches those, most of the 846 sites compile unchanged. The ones
that will not are the constructors in `biguint.mojo` that take or return
`List[UInt32]` -- around lines 172-400.

### Inline or heap: pick the branch, not the self-pointer

Two ways to answer `unsafe_ptr()`:

1. A branch on capacity: `if capacity <= INLINE_WORDS` return the address of
   the inline array, else the heap pointer. One well-predicted branch, and
   `unsafe_ptr()` is nearly always hoisted out of the loop that uses it.
2. A `_data` field that always points at whichever storage is live. No branch,
   but the struct is then self-referential, and every move has to repair the
   pointer. Mojo calls `__moveinit__` so it is expressible, but a missed
   relocation is a silent memory bug.

**Take the branch.** The cost is ~0.3 ns on a call that happens once per loop,
and the failure mode of the other one is corruption rather than slowness.

### Order of work

1. `src/decimo/biguint/wordlist.mojo` -- the type, with the API above.
2. Switch `BigUInt.words` and fix `biguint.mojo`'s constructors.
3. Compile; work through the errors elsewhere.
4. `bash tests/test.sh all` -- 1071 tests must stay green.
5. Measure: the `add` sweep above, then `docs/benchmarks.md` at every size,
   then the Python comparison.

### What could go wrong

- **Large sizes regressing.** `unsafe_ptr()` gains a branch, and the hot
  kernels in `biguint/arithmetics.mojo` call it constantly. Check the 100k
  and 10^6 digit rows of `benchmarks.md`, not just the small ones.
- **`_data` (3 uses).** Direct field access that has no meaning for inline
  storage; those sites need `unsafe_ptr()` instead.
- **Struct size.** `BigUInt` grows by 16 bytes with four inline words. It is
  returned by value everywhere, so watch the large-size benchmarks for a
  copying regression.

## Then what

With the allocation gone, the remaining gap at 28 digits is the Python call
itself: about 34 ns to enter and leave, 14 ns to read the context precision
(a named `std.ffi._Global`, which hashes its name -- the indexed variant
skips that but wants one of a few reserved indices, and squatting on one in a
published package would collide later), and roughly 20 ns to allocate the
result `PyObject`. The last of those needs the value embedded in the
`PyObject` rather than allocated beside it, which the bindings cannot do yet.
