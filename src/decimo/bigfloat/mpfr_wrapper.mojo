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

"""Low-level FFI bindings to the MPFR C wrapper (libdecimo_gmp_wrapper).

This module provides thin Mojo wrappers around the C functions in
`gmp_wrapper.c`. The C wrapper uses `dlopen`/`dlsym` to load MPFR lazily
at runtime, so this code compiles and links without MPFR headers or libraries.

The C wrapper manages a pool of `mpfr_t` handles. Each handle is identified
by an `Int32` index. The Mojo side never touches raw `mpfr_t` pointers.

All functions here are internal — users interact with `BigFloat`, not these.
"""

from std.ffi import external_call, c_int, c_char

# ===----------------------------------------------------------------------=== #
# Availability check
# ===----------------------------------------------------------------------=== #


fn mpfrw_available() -> Bool:
    """Checks if MPFR is available on this system.

    First call triggers the lazy load attempt. Result is cached in C.

    Returns:
        True if the C wrapper successfully loaded libmpfr via dlopen.
    """
    var result = external_call["mpfrw_available", c_int]()
    return result != 0


# ===----------------------------------------------------------------------=== #
# Handle lifecycle
# ===----------------------------------------------------------------------=== #


fn mpfrw_init(prec_bits: Int) -> Int32:
    """Allocates an MPFR handle with the given precision in bits.

    Args:
        prec_bits: Precision in bits for the MPFR value.

    Returns:
        A handle index (>= 0) on success, or -1 if the pool is full
        or MPFR is unavailable.
    """
    return external_call["mpfrw_init", Int32](Int32(prec_bits))


fn mpfrw_clear(handle: Int32):
    """Frees an MPFR handle, returning it to the pool.

    Args:
        handle: MPFR handle index to free.
    """
    external_call["mpfrw_clear", NoneType](handle)


# ===----------------------------------------------------------------------=== #
# String conversion
#
# C returns malloc'd char* which Mojo can't represent as UnsafePointer[c_char]
# in return position (origin parameter can't be inferred). So we pass raw
# addresses as Int and reconstruct UnsafePointer at the call site.
# ===----------------------------------------------------------------------=== #


fn mpfrw_set_str(
    handle: Int32, s: UnsafePointer[c_char, _], length: Int32
) -> Int32:
    """Sets the MPFR handle value from a decimal string.

    Args:
        handle: MPFR handle index.
        s: Pointer to a decimal string (e.g. "-3.14159").
        length: Length of the string (for safety, not relying on null terminator).

    Returns:
        0 on success, non-zero on parse error.
    """
    return external_call["mpfrw_set_str", Int32](handle, s, length)


fn mpfrw_get_str(handle: Int32, digits: Int32) -> Int:
    """Exports the MPFR handle value as a decimal string.

    Args:
        handle: MPFR handle index.
        digits: Number of significant decimal digits to export.

    Returns:
        Raw address of a null-terminated C string (malloc'd).
        Caller must free it with `mpfrw_free_str`.
    """
    return external_call["mpfrw_get_str", Int](handle, digits)


fn mpfrw_free_str(addr: Int):
    """Frees a string returned by `mpfrw_get_str`.

    Args:
        addr: Raw address returned by `mpfrw_get_str`.
    """
    external_call["mpfrw_free_str", NoneType](addr)


# ===----------------------------------------------------------------------=== #
# Raw digit export (fast BigFloat → BigDecimal)
# ===----------------------------------------------------------------------=== #


fn mpfrw_get_raw_digits(
    handle: Int32, digits: Int32, out_exp: UnsafePointer[Int, _]
) -> Int:
    """Exports MPFR value as raw digit string via mpfr_get_str.

    Returns a pointer to a null-terminated pure digit string (no dot, no
    exponent notation). Negative values have a ``-`` prefix. The decimal
    exponent is written to ``out_exp``.

    Meaning: raw = ``"31415..."`` with exp = 1 → value = 0.31415… × 10^1.

    The digit string is allocated by MPFR and must be freed with
    ``mpfrw_free_raw_str``.

    Args:
        handle: MPFR handle index.
        digits: Number of significant decimal digits to export.
        out_exp: Pointer to an Int; receives the decimal exponent.

    Returns:
        Raw address of the digit string, or 0 on failure.
    """
    return external_call["mpfrw_get_raw_digits", Int](handle, digits, out_exp)


fn mpfrw_free_raw_str(addr: Int):
    """Frees a digit string returned by ``mpfrw_get_raw_digits``.

    Args:
        addr: Raw address returned by ``mpfrw_get_raw_digits``.
    """
    external_call["mpfrw_free_raw_str", NoneType](addr)


# ===----------------------------------------------------------------------=== #
# Arithmetic operations
# ===----------------------------------------------------------------------=== #


fn mpfrw_add(result: Int32, a: Int32, b: Int32):
    """Computes result = a + b (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Left operand handle.
        b: Right operand handle.
    """
    external_call["mpfrw_add", NoneType](result, a, b)


fn mpfrw_sub(result: Int32, a: Int32, b: Int32):
    """Computes result = a - b (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Left operand handle.
        b: Right operand handle.
    """
    external_call["mpfrw_sub", NoneType](result, a, b)


fn mpfrw_mul(result: Int32, a: Int32, b: Int32):
    """Computes result = a * b (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Left operand handle.
        b: Right operand handle.
    """
    external_call["mpfrw_mul", NoneType](result, a, b)


fn mpfrw_div(result: Int32, a: Int32, b: Int32):
    """Computes result = a / b (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Dividend handle.
        b: Divisor handle.
    """
    external_call["mpfrw_div", NoneType](result, a, b)


fn mpfrw_neg(result: Int32, a: Int32):
    """Computes result = -a (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Operand handle.
    """
    external_call["mpfrw_neg", NoneType](result, a)


fn mpfrw_abs(result: Int32, a: Int32):
    """Computes result = |a| (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Operand handle.
    """
    external_call["mpfrw_abs", NoneType](result, a)


fn mpfrw_cmp(a: Int32, b: Int32) -> Int32:
    """Compares a and b.

    Args:
        a: Left operand handle.
        b: Right operand handle.

    Returns:
        -1 if a < b, 0 if equal, 1 if a > b. -2 on invalid handle.
    """
    return external_call["mpfrw_cmp", Int32](a, b)


# ===----------------------------------------------------------------------=== #
# Transcendental operations
# ===----------------------------------------------------------------------=== #


fn mpfrw_sqrt(result: Int32, a: Int32):
    """Computes result = sqrt(a) (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Operand handle.
    """
    external_call["mpfrw_sqrt", NoneType](result, a)


fn mpfrw_exp(result: Int32, a: Int32):
    """Computes result = exp(a) (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Operand handle.
    """
    external_call["mpfrw_exp", NoneType](result, a)


fn mpfrw_log(result: Int32, a: Int32):
    """Computes result = ln(a) (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Operand handle.
    """
    external_call["mpfrw_log", NoneType](result, a)


fn mpfrw_sin(result: Int32, a: Int32):
    """Computes result = sin(a) (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Operand handle.
    """
    external_call["mpfrw_sin", NoneType](result, a)


fn mpfrw_cos(result: Int32, a: Int32):
    """Computes result = cos(a) (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Operand handle.
    """
    external_call["mpfrw_cos", NoneType](result, a)


fn mpfrw_tan(result: Int32, a: Int32):
    """Computes result = tan(a) (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Operand handle.
    """
    external_call["mpfrw_tan", NoneType](result, a)


fn mpfrw_pow(result: Int32, a: Int32, b: Int32):
    """Computes result = a^b (MPFR_RNDN).

    Args:
        result: Handle to store the result.
        a: Base handle.
        b: Exponent handle.
    """
    external_call["mpfrw_pow", NoneType](result, a, b)


fn mpfrw_rootn_ui(result: Int32, a: Int32, n: UInt32):
    """Computes result = a^(1/n) (MPFR_RNDN), the n-th root.

    Args:
        result: Handle to store the result.
        a: Operand handle.
        n: Root degree.
    """
    external_call["mpfrw_rootn_ui", NoneType](result, a, n)


fn mpfrw_const_pi(result: Int32):
    """Computes result = π (MPFR_RNDN) to the handle's precision.

    Args:
        result: Handle to store the result.
    """
    external_call["mpfrw_const_pi", NoneType](result)
