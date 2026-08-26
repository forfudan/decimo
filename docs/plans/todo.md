# TODO

This is a to-do list for Decimo.

- [ ] When Mojo supports **global variables**, implement a type `Context` and a
      global variable `context` for the `Decimal` class to store the precision
      of the decimal number and other configurations. This will allow users to
      set the precision globally, rather than having to set it for each function
      of the `Decimal` class.
- [ ] When Mojo supports **enum types**, implement an enum type for the rounding
      mode.
- [ ] Implement a complex number class `BigComplex` that uses `Decimal` for the
      real and imaginary parts. This will allow users to perform high-precision
      complex number arithmetic.
- [ ] Implement different methods for adding decimo types with `Int` types so
      that an implicit conversion is not required.
- [x] (20260825) Use debug mode to check for unnecessary zero words before all
      arithmetic operations. `BigUInt.assert_invariant()` and
      `BigInt.assert_invariant()` check that the words are non-empty and carry
      no leading zero word. They are `debug_assert`, so they cost nothing in a
      normal build and run in the test suite.
      `remove_leading_empty_words()` carries the check as a post-condition,
      which covers all thirty repair sites at once.
- [ ] Check the `floor_divide()` function of `BigUInt`. Currently, the speed of
      division between similar-sized numbers are okay, but the speed of 2n-by-n,
      4n-by-n, and 8n-by-n divisions decreases disproportionally. This is likely
      due to the segmentation of the dividend in the Burnikel-Ziegler algorithm.
      (20260826: still open, but `docs/benchmarks.md` now measures 2n-by-n
      division for `BigInt` at every size, so the shape is visible. The
      base-10^9 transform also helped indirectly — Burnikel-Ziegler reaches
      multiplication underneath, and `BigUInt` division at 100 000 digits went
      16.53 ms to 13.74 ms with no change of its own.)
- [x] Consider using `Decimal` as the struct name instead of `BigDecimal`, and
      use `comptime BigDecimal = Decimal` to create an alias for the `Decimal`
      struct. This just switches the alias and the struct name, but it may be
      more intuitive to use `Decimal` as the struct name since it is more
      consistent with Python's `decimal.Decimal`. Moreover, hovering over
      `Decimal` will show the docstring of the struct, which is more intuitive
      than hovering over `BigDecimal` to see the docstring of the struct.
- [x] (PR #127, #128, #131) Make all default constructor "safe", which means
      that the words are checked and normalized to ensure that there are no zero
      words and that the number is in a valid state. This will help prevent bugs
      and ensure that all `BigUInt` instances are in a consistent state. Also
      allow users to create "unsafe" `BigUInt` instances if they want to, but
      there must be a key-word only argument, e.g., `raw_words`.

- [x] (#31) The `exp()` function performs slower than Python's counterpart in
      specific cases. Detailed investigation reveals the bottleneck stems from
      multiplication operations between decimals with significant fractional
      components. These operations currently rely on UInt256 arithmetic, which
      introduces performance overhead. Optimization of the `multiply()` function
      is required to address these performance bottlenecks, particularly for
      high-precision decimal multiplication with many digits after the decimal
      point. Internally, also use `Decimal` instead of `BigDecimal` or `BDec` to
      be consistent.
- [x] Implement different methods for augmented arithmetic assignments to
      improve memory-efficiency and performance.
- [x] Implement a method `remove_leading_zeros` for `BigUInt`, which removes the
      zero words from the most significant end of the number.
- [x] Use debug mode to check for uninitialized `BigUInt` before all arithmetic
      operations. This will help ensure that there are no uninitialized
      `BigUInt`.

## Roadmap for Decimo

- [x] Re-implement some methods of `BigUInt` to improve the performance, since
      it is the building block of `BigDecimal` and `BigInt10`.
- [x] Refine the methods of `BigDecimal` to improve the performance.
- [x] Implement the big **binary** integer type (`BigInt`) using base-2^32
      internal representation. The new `BigInt` (alias `BInt`) replaces the
      previous base-10^9 implementation (now `BigInt10`) and delivers
      significantly improved performance.