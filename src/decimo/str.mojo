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

"""String parsing and manipulation functions."""

from std.algorithm import vectorize

from decimo.errors import ValueError


def rjust(s: String, width: Int, fillchar: String = " ") -> String:
    """Right-justifies a string by padding with a fill character on the left.

    Args:
        s: The string to right-justify.
        width: The minimum total width of the resulting string.
        fillchar: The character used for padding (defaults to space).

    Returns:
        The right-justified string, or the original string if it is already at least `width` characters.
    """
    var n = len(s)
    if n >= width:
        return s
    return fillchar * (width - n) + s


def ljust(s: String, width: Int, fillchar: String = " ") -> String:
    """Left-justifies a string by padding with a fill character on the right.

    Args:
        s: The string to left-justify.
        width: The minimum total width of the resulting string.
        fillchar: The character used for padding (defaults to space).

    Returns:
        The left-justified string, or the original string if it is already at least `width` characters.
    """
    var n = len(s)
    if n >= width:
        return s
    return s + fillchar * (width - n)


# ============================================================================
# Numeric string parser for BigDecimal: parse_numeric_string()
# Cold raise helpers for parse_numeric_string()
#
# Each helper carries the `String.format(...)` allocation that would otherwise
# bloat the parser body. Marked `@no_inline` so they never participate in
# inlining decisions for the hot scan loop -- this is the same pattern used
# for `Decimal128.from_uint128`'s raise helpers (see decimal128_enhancement
# Lesson #4: extracting `.format()` raises lets the parent stay small enough
# to be inlined into its callers).
#
# Plain string-literal raises stay inline -- they are zero-cost on the cold
# path and would only add call overhead if extracted.
# ============================================================================


@no_inline
def _raise_invalid_char(c: UInt8, value: String) raises -> None:
    # Non-ASCII bytes (>127) are typically a stray UTF-8 lead/continuation
    # byte; surfacing them via `chr()` produces garbled output that is not
    # actionable. Include the raw byte value (hex) AND the original input so
    # users can diagnose encoding issues. Mirrors Decimal128.from_string.
    if c > 127:
        raise ValueError(
            message=String(
                "Invalid non-ASCII byte {} in numeric string: {}"
            ).format(hex(Int(c)), value),
            function="parse_numeric_string()",
        )
    raise ValueError(
        message=String(
            "Invalid character in the string of the number: {}"
        ).format(chr(Int(c))),
        function="parse_numeric_string()",
    )


def parse_numeric_string(
    value: String,
) raises -> Tuple[List[UInt8], Int, Bool]:
    """Parse the string of a number into normalized parts.

    Uses a two-pass architecture for performance:
    - Pass 1: Structural scan to validate characters, locate sign, decimal
      point, and exponent, and count digits.
    - Pass 2: SIMD-accelerated extraction of significant digit values.

    For contiguous digit regions (the common case), Pass 2 uses SIMD to
    batch-subtract ASCII '0' (48) from 16 bytes at a time, which is
    significantly faster than byte-by-byte processing for large numbers.

    Args:
        value: The string representation of a number.

    Returns:
        A tuple of:
        - Normalized coefficient as List[UInt8] which represents an integer.
          Each element is a digit value 0-9.
        - Scale of the number (number of decimal digits, adjusted by
          exponent).
        - Sign of the number (True if negative).

    Notes:

    Only the following characters are allowed in the input string:
    - Digits 0-9.
    - Decimal point ".". It can only appear once.
    - Negative sign "-". It can only appear before the first digit.
    - Positive sign "+". It can only appear before the first digit or after
        exponent "e" or "E".
    - Exponential notation "e" or "E". It can only appear once after the
        digits.
    - Space " ". It can appear anywhere in the string; it is ignored.
    - Comma ",". It can appear anywhere between digits; it is ignored.
    - Underscore "_". It can appear anywhere between digits; it is ignored.

    Examples:
    ```console
    parse_numeric_string("123")             -> ([1,2,3], 0, False)
    parse_numeric_string("123.456")         -> ([1,2,3,4,5,6], 3, False)
    parse_numeric_string("123.456e3")       -> ([1,2,3,4,5,6], 0, False)
    parse_numeric_string("123.456e-3")      -> ([1,2,3,4,5,6], 6, False)
    parse_numeric_string("123.456e+10")     -> ([1,2,3,4,5,6], -7, False)
    parse_numeric_string("0.00123456")      -> ([1,2,3,4,5,6], 8, False)
    parse_numeric_string("-123")            -> ([1,2,3], 0, True)
    ```
    End of examples.

    Raises:
        ValueError: If the string is empty, contains invalid characters, or
            has malformed numeric syntax.
    """

    # [Mojo Miji]
    # The syntax of numeric values in EBNF form is as follows:
    #     number ::= integer | real
    #     integer ::= (sign | epsilon) digit ((separator | epsilon) digit)*
    #     real ::= integer exponent | decimal (exponent | epsilon)
    #     decimal ::= (sign | epsilon) ((digit ((separator | epsilon) digit)*) | epsilon) '.' (digit ((separator | epsilon) digit)* | epsilon)
    #     # At least one digit must appear either before or after the decimal point.
    #     exponent ::= ('e' | 'E') (sign | epsilon) digit ((separator | epsilon) digit)*
    #     sign ::= '+' | '-'
    #     digit ::= '0' | '1' | '2' | '3' | '4' | '5' | '6' | '7' | '8' | '9'
    #     separator ::= ' ' | ',' | '_'
    #     # Separator characters are ignored by the parser. In particular:
    #     # - Space ' ' may appear anywhere in the string and is ignored.
    #     # - Comma ',' and underscore '_' may appear anywhere between digits and are ignored.

    var value_bytes = StringSlice(value).as_bytes()
    var n = len(value_bytes)

    if n == 0:
        raise ValueError(
            message="Empty string.",
            function="parse_numeric_string()",
        )

    var ptr = value_bytes.unsafe_ptr()

    # ==================================================================
    # Pass 1: Structural scan and validation
    #
    # Scans every byte to:
    # - Validate characters and structural constraints.
    # - Locate sign, decimal point ('.'), and exponent ('e'/'E').
    # - Count total mantissa digits, digits after decimal, and leading
    #   zeros (for determining significant digit count).
    # - Record byte positions of the first non-zero digit and the last
    #   mantissa digit (for efficient extraction in pass 2).
    # ==================================================================

    var sign: Bool = False
    var sign_read: Bool = False
    var decimal_point_pos: Int = -1
    var exponent_pos: Int = -1
    var total_mantissa_digits: Int = 0
    var digits_after_decimal: Int = 0
    var first_nonzero_byte_pos: Int = -1
    var leading_zeros: Int = 0
    var last_mantissa_digit_byte_pos: Int = -1
    var in_exponent: Bool = False
    var exponent_sign_read: Bool = False
    var last_was_separator: Bool = False

    for i in range(n):
        var c = ptr[i]

        # Check digits first (most common case for performance)
        if c >= 48 and c <= 57:  # '0'-'9'
            last_was_separator = False

            if in_exponent:
                # Once we see a digit in the exponent, no more signs allowed.
                exponent_sign_read = True
                continue

            sign_read = True
            total_mantissa_digits += 1
            last_mantissa_digit_byte_pos = i

            if decimal_point_pos != -1:
                digits_after_decimal += 1

            if c != 48 and first_nonzero_byte_pos == -1:
                first_nonzero_byte_pos = i
                leading_zeros = total_mantissa_digits - 1

        # If the char is " ", skip it (does not affect separator flag)
        elif c == 32:
            pass

        # If the char is "," or "_", skip it
        elif c == 44 or c == 95:
            last_was_separator = True

        # If the char is "."
        elif c == 46:
            last_was_separator = False
            if in_exponent:
                raise ValueError(
                    message="Decimal point cannot appear in the exponent part.",
                    function="parse_numeric_string()",
                )
            if decimal_point_pos != -1:
                raise ValueError(
                    message="Decimal point can only appear once.",
                    function="parse_numeric_string()",
                )
            decimal_point_pos = i
            sign_read = True

        # If the char is "e" or "E"
        elif c == 101 or c == 69:
            last_was_separator = True
            if in_exponent:
                raise ValueError(
                    message="Exponential notation can only appear once.",
                    function="parse_numeric_string()",
                )
            if total_mantissa_digits == 0:
                raise ValueError(
                    message="Exponential notation must follow a number.",
                    function="parse_numeric_string()",
                )
            exponent_pos = i
            in_exponent = True

        # If the char is "-"
        elif c == 45:
            last_was_separator = True
            if in_exponent:
                if exponent_sign_read:
                    raise ValueError(
                        message=(
                            "Exponent sign can only appear once,"
                            " before exponent digits."
                        ),
                        function="parse_numeric_string()",
                    )
                exponent_sign_read = True
            else:
                if sign_read:
                    raise ValueError(
                        message=(
                            "Minus sign can only appear once at the beginning."
                        ),
                        function="parse_numeric_string()",
                    )
                sign = True
                sign_read = True

        # If the char is "+"
        elif c == 43:
            last_was_separator = True
            if in_exponent:
                if exponent_sign_read:
                    raise ValueError(
                        message=(
                            "Exponent sign can only appear once,"
                            " before exponent digits."
                        ),
                        function="parse_numeric_string()",
                    )
                exponent_sign_read = True
            else:
                if sign_read:
                    raise ValueError(
                        message=(
                            "Plus sign can only appear once at the beginning."
                        ),
                        function="parse_numeric_string()",
                    )
                sign_read = True

        else:
            _raise_invalid_char(c, value)

    if last_was_separator:
        raise ValueError(
            message="Unexpected end character in the string of the number.",
            function="parse_numeric_string()",
        )

    if total_mantissa_digits == 0:
        raise ValueError(
            message="No digits found in the string of the number.",
            function="parse_numeric_string()",
        )

    # ==================================================================
    # Parse exponent value (separate from pass 1 to keep the main loop
    # tight; exponents are always short so this adds negligible cost)
    # ==================================================================

    var raw_exponent: Int = 0
    var exponent_is_negative: Bool = False

    if exponent_pos != -1:
        for i in range(exponent_pos + 1, n):
            var c = ptr[i]
            if c >= 48 and c <= 57:
                raw_exponent = raw_exponent * 10 + Int(c - 48)
            elif c == 45:
                exponent_is_negative = True
            # '+', ' ', ',', '_' are skipped

    # ==================================================================
    # Compute scale
    # ==================================================================

    var scale: Int = digits_after_decimal
    if raw_exponent != 0:
        if exponent_is_negative:
            # Negative exponent increases scale
            # e.g. 123.456e-3 -> scale = 3 + 3 = 6
            scale += raw_exponent
        else:
            # Positive exponent decreases scale
            # e.g. 1.234e8 -> scale = 3 - 8 = -5
            scale -= raw_exponent

    # ==================================================================
    # Pass 2: Extract significant mantissa digits
    #
    # The significant digits start at the first non-zero digit and end
    # at the last mantissa digit. Depending on whether the extraction
    # range contains separators or a decimal point, one of three paths
    # is taken:
    #
    #   Fast path:   contiguous pure digits      -> SIMD bulk copy
    #   Medium path: two digit runs around '.'   -> two SIMD copies
    #   Slow path:   separators present          -> byte-by-byte
    # ==================================================================

    var significant_count = total_mantissa_digits - leading_zeros
    if significant_count == 0:
        significant_count = 1  # Keep at least one zero

    # Handle all-zeros case (e.g. "0000", "0.00", "+0")
    if first_nonzero_byte_pos == -1:
        var coef = List[UInt8](capacity=1)
        coef.append(0)
        return Tuple(coef^, scale, sign)

    var extract_start = first_nonzero_byte_pos
    var extract_end = last_mantissa_digit_byte_pos + 1

    # Determine if the extraction range is contiguous (no separators).
    # If the byte span equals the expected number of significant digits
    # (plus one for '.' if present in range), the range has no separators.
    var has_decimal_in_range = (
        decimal_point_pos >= extract_start and decimal_point_pos < extract_end
    )
    var expected_byte_count = significant_count + (
        1 if has_decimal_in_range else 0
    )
    var actual_byte_count = extract_end - extract_start
    var is_contiguous = actual_byte_count == expected_byte_count

    var coef = List[UInt8](capacity=significant_count)

    if is_contiguous and not has_decimal_in_range:
        # ---- Fast path ----
        # Pure contiguous digit bytes, no separators, no decimal point.
        # Use vectorize to batch-subtract ASCII '0' (48) using SIMD.
        coef.resize(significant_count, 0)

        @parameter
        def convert_fast[
            simd_width: Int
        ](i: Int) unified {mut coef, read value_bytes, read extract_start}:
            coef.unsafe_ptr().store[width=simd_width](
                i,
                value_bytes.unsafe_ptr().load[width=simd_width](
                    extract_start + i
                )
                - SIMD[DType.uint8, simd_width](48),
            )

        vectorize[16](significant_count, convert_fast)

    elif is_contiguous and has_decimal_in_range:
        # ---- Medium path ----
        # Two contiguous digit runs separated by '.' in between.
        coef.resize(significant_count, 0)
        var before_count = decimal_point_pos - extract_start
        var after_count = extract_end - decimal_point_pos - 1

        # Region before decimal point
        if before_count > 0:

            @parameter
            def convert_before[
                simd_width: Int
            ](i: Int) unified {mut coef, read value_bytes, read extract_start}:
                coef.unsafe_ptr().store[width=simd_width](
                    i,
                    value_bytes.unsafe_ptr().load[width=simd_width](
                        extract_start + i
                    )
                    - SIMD[DType.uint8, simd_width](48),
                )

            vectorize[16](before_count, convert_before)

        # Region after decimal point
        if after_count > 0:

            @parameter
            def convert_after[
                simd_width: Int
            ](i: Int) unified {
                mut coef,
                read value_bytes,
                read decimal_point_pos,
                read before_count,
            }:
                coef.unsafe_ptr().store[width=simd_width](
                    before_count + i,
                    value_bytes.unsafe_ptr().load[width=simd_width](
                        decimal_point_pos + 1 + i
                    )
                    - SIMD[DType.uint8, simd_width](48),
                )

            vectorize[16](after_count, convert_after)

    else:
        # ---- Slow path ----
        # Separators (commas, underscores, spaces) present in the range.
        # Extract digit bytes one by one.
        for i in range(extract_start, extract_end):
            var c = ptr[i]
            if c >= 48 and c <= 57:
                coef.append(c - 48)

    return Tuple(coef^, scale, sign)
