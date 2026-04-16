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

"""
REPL settings for the Decimo CLI calculator.

Bundles all display and computation options (precision, formatting, rounding
mode) into a single `Settings` struct and provides a one-line parser that
matches option names by their long name, short name, and aliases — mirroring
the CLI flag definitions from `DecimoArgs`.

The parser is the core: split by whitespace, scan each token, match
it against known names, and consume a following value for options.  Flags
(scientific, engineering, pad) toggle on each use — repeat to turn off.

    `:p 100 s d`  →  precision=100, scientific=True, rounding=down

Name mapping (mirrors DecimoArgs, case-insensitive inside the REPL):

    Options (consume next token as value):
        precision   p                          → Int
        delimiter                              → String
        rounding-mode  r  rm  round            → RoundingMode name

    Flags (toggle on/off each time they appear):
        scientific  s   sci                    → Bool
        engineering e   eng                    → Bool
        pad                                    → Bool

    Standalone rounding modes (set directly, no `r` prefix needed):
        he  hu  hd  u  d  c  f  b
        half-even  half-up  half-down  up  down  ceiling  floor  bankers

Rounding-mode values (accepted after `r` or standalone):
    half-even  half_even  he  b  bankers  (default, banker's rounding)
    half-up    half_up    hu
    half-down  half_down  hd
    up  u
    down  d
    ceiling  ceil  c
    floor  f
"""

from decimo.rounding_mode import RoundingMode


# ===----------------------------------------------------------------------=== #
# Settings struct
# ===----------------------------------------------------------------------=== #


struct Settings(Copyable, Movable, Writable):
    """Mutable bundle of all REPL computation and display options."""

    var precision: Int
    """Number of significant digits for computation results."""
    var scientific: Bool
    """Whether to display results in scientific notation."""
    var engineering: Bool
    """Whether to display results in engineering notation."""
    var pad: Bool
    """Whether to zero-pad results to the full precision."""
    var delimiter: String
    """Digit-group delimiter string (empty means no grouping)."""
    var rounding_mode: RoundingMode
    """The rounding mode for final results."""

    fn __init__(
        out self,
        precision: Int = 50,
        scientific: Bool = False,
        engineering: Bool = False,
        pad: Bool = False,
        delimiter: String = "",
        rounding_mode: RoundingMode = RoundingMode.half_even(),
    ):
        """Creates a new Settings with the given options.

        Args:
            precision: Number of significant digits (default 50).
            scientific: Whether to use scientific notation.
            engineering: Whether to use engineering notation.
            pad: Whether to zero-pad results.
            delimiter: Digit-group delimiter string.
            rounding_mode: The rounding mode to apply.
        """
        self.precision = precision
        self.scientific = scientific
        self.engineering = engineering
        self.pad = pad
        self.delimiter = delimiter
        self.rounding_mode = rounding_mode

    fn write_to[W: Writer](self, mut writer: W):
        """Writes a human-readable summary of the settings.

        Parameters:
            W: The writer type.

        Args:
            writer: The writer instance.
        """
        writer.write("Precision: ", self.precision, ".")
        if self.scientific:
            writer.write(" Scientific notation.")
        elif self.engineering:
            writer.write(" Engineering notation.")
        if self.pad:
            writer.write(" Zero-padded.")
        if self.delimiter:
            writer.write(" Delimiter: '", self.delimiter, "'.")
        if not (self.rounding_mode == RoundingMode.half_even()):
            writer.write(" Rounding: ", self.rounding_mode, ".")


# ===----------------------------------------------------------------------=== #
# Settings parser (core of 4.7)
# ===----------------------------------------------------------------------=== #


def parse_settings(input: String, mut settings: Settings) raises:
    """Parses a one-line settings string and apply changes to `settings`.

    Splits by whitespace, scans tokens left-to-right. Each token is
    matched against known option/flag names (case-insensitive). Options
    consume the next token as their value; flags toggle their Bool value
    each time they appear.

    Raises on unknown tokens or missing values.

    This is enlightened by and is a simplified version of ArgMojo's parser.

    Args:
        input: The settings string (without the leading `:`).
        settings: The Settings struct to modify in place.
    """
    var tokens = _split_whitespace(input)
    var n = len(tokens)
    if n == 0:
        return

    var i = 0
    while i < n:
        var token = to_lower(tokens[i])

        # == Options (consume next token as value) ========================
        if _is_precision_name(token):
            i += 1
            if i >= n:
                raise Error("expected a value after '" + tokens[i - 1] + "'")
            var val = _parse_int(tokens[i], "precision")
            if val < 1:
                raise Error("precision must be >= 1, got " + String(val))
            settings.precision = val

        elif _is_delimiter_name(token):
            i += 1
            if i >= n:
                raise Error("expected a value after '" + tokens[i - 1] + "'")
            var dval = to_lower(tokens[i])
            if dval == "off" or dval == "none" or dval == '""' or dval == "''":
                settings.delimiter = ""
            else:
                settings.delimiter = tokens[i]

        elif _is_rounding_mode_name(token):
            i += 1
            if i >= n:
                raise Error(
                    "expected a rounding mode after '" + tokens[i - 1] + "'"
                )
            settings.rounding_mode = _parse_rounding_mode(to_lower(tokens[i]))

        # == Flags (toggle; enforce mutual exclusion) =====================
        elif _is_scientific_name(token):
            if settings.scientific:
                settings.scientific = False
            else:
                settings.scientific = True
                settings.engineering = False  # mutually exclusive

        elif _is_engineering_name(token):
            if settings.engineering:
                settings.engineering = False
            else:
                settings.engineering = True
                settings.scientific = False  # mutually exclusive

        elif _is_pad_name(token):
            settings.pad = not settings.pad

        # == Standalone rounding modes (no `r` prefix needed) ============
        elif _is_standalone_rounding_mode(token):
            settings.rounding_mode = _parse_rounding_mode(token)

        else:
            raise Error("unknown setting: '" + tokens[i] + "'")

        i += 1


def format_settings_confirmation(settings: Settings) -> String:
    """Returns a human-readable summary of the current settings.

    Args:
        settings: The current settings to format.

    Returns:
        A formatted string describing the active settings.
    """
    return String(settings)


# ===----------------------------------------------------------------------=== #
# Inline settings detection (4.8)
# ===----------------------------------------------------------------------=== #


def split_inline_settings(
    line: String,
) -> Optional[Tuple[String, String]]:
    """Detects inline settings in a REPL line.

    If the line contains a `:` that is not at position 0, splits at the
    last `:` into (expression, settings_string).

    Args:
        line: The REPL input line to examine.

    Returns:
        A tuple of (expression, settings_string) if inline settings are
        found, or None if there are no inline settings.

    Examples:
        `"2*sqrt(1.23):p 100"` →  `("2*sqrt(1.23)", "p 100")`.
        `"1+2"` →  None.
        `":p 100"` →  None (pure meta-command, handled elsewhere).
    """
    var bytes = StringSlice(line).as_bytes()
    var n = len(bytes)

    if n == 0:
        return None

    # Skip leading whitespace
    var start = 0
    while start < n and (bytes[start] == 32 or bytes[start] == 9):
        start += 1

    # If line starts with ':', it's a pure meta-command, not inline
    if start < n and bytes[start] == 58:  # ':'
        return None

    # Find the last ':' — it cannot appear in math expressions,
    # so no need to track parentheses.
    var colon_pos = -1
    var j = n - 1
    while j > start:
        if bytes[j] == 58:  # ':'
            colon_pos = j
            break
        j -= 1

    if colon_pos <= start:
        return None

    # Build expression and settings strings
    var expr_bytes = List[UInt8](capacity=colon_pos)
    for k in range(colon_pos):
        expr_bytes.append(bytes[k])
    var expr = String(unsafe_from_utf8=expr_bytes^)

    var settings_start = colon_pos + 1
    var settings_bytes = List[UInt8](capacity=n - settings_start)
    for k in range(settings_start, n):
        settings_bytes.append(bytes[k])
    var settings_str = String(unsafe_from_utf8=settings_bytes^)

    return (expr^, settings_str^)


# ===----------------------------------------------------------------------=== #
# Name matching — mirrors DecimoArgs CLI definitions
# ===----------------------------------------------------------------------=== #


fn _is_precision_name(token: String) -> Bool:
    """Match: precision, p."""
    return token == "precision" or token == "p"


fn _is_delimiter_name(token: String) -> Bool:
    """Match: delimiter."""
    return token == "delimiter"


fn _is_rounding_mode_name(token: String) -> Bool:
    """Match: rounding-mode, r, rm, round, rounding_mode."""
    return (
        token == "rounding-mode"
        or token == "r"
        or token == "rm"
        or token == "round"
        or token == "rounding_mode"
    )


fn _is_scientific_name(token: String) -> Bool:
    """Match: scientific, s, sci."""
    return token == "scientific" or token == "s" or token == "sci"


fn _is_engineering_name(token: String) -> Bool:
    """Match: engineering, e, eng."""
    return token == "engineering" or token == "e" or token == "eng"


fn _is_pad_name(token: String) -> Bool:
    """Match: pad."""
    return token == "pad"


fn _is_standalone_rounding_mode(token: String) -> Bool:
    """Match standalone rounding mode shortcuts: he, hu, hd, u, d, c, f, b,
    and their full names."""
    return (
        token == "he"
        or token == "hu"
        or token == "hd"
        or token == "u"
        or token == "d"
        or token == "c"
        or token == "f"
        or token == "b"
        or token == "half-even"
        or token == "half_even"
        or token == "half-up"
        or token == "half_up"
        or token == "half-down"
        or token == "half_down"
        or token == "up"
        or token == "down"
        or token == "ceiling"
        or token == "ceil"
        or token == "floor"
        or token == "bankers"
    )


# ===----------------------------------------------------------------------=== #
# Value parsers
# ===----------------------------------------------------------------------=== #


def _parse_int(s: String, name: String) raises -> Int:
    """Parse a string as an integer value for a named setting."""
    try:
        return Int(s)
    except:
        raise Error(
            "invalid value for " + name + ": '" + s + "' (expected integer)"
        )


def _parse_rounding_mode(s: String) raises -> RoundingMode:
    """Parse a rounding-mode name (case-insensitive, hyphen/underscore OK).

    Accepted names:
        half-even  half_even  he  (default)
        half-up    half_up    hu
        half-down  half_down  hd
        up  u
        down
        ceiling  ceil  c
        floor  f
    """
    if (
        s == "half-even"
        or s == "half_even"
        or s == "he"
        or s == "b"
        or s == "bankers"
    ):
        return RoundingMode.half_even()
    elif s == "half-up" or s == "half_up" or s == "hu":
        return RoundingMode.half_up()
    elif s == "half-down" or s == "half_down" or s == "hd":
        return RoundingMode.half_down()
    elif s == "up" or s == "u":
        return RoundingMode.up()
    elif s == "down" or s == "d":
        return RoundingMode.down()
    elif s == "ceiling" or s == "ceil" or s == "c":
        return RoundingMode.ceiling()
    elif s == "floor" or s == "f":
        return RoundingMode.floor()
    else:
        raise Error(
            "unknown rounding mode: '"
            + s
            + "'. Expected: half-even (he/b), half-up (hu), half-down (hd),"
            " up (u), down (d), ceiling (c), floor (f)"
        )


# ===----------------------------------------------------------------------=== #
# String utilities
# ===----------------------------------------------------------------------=== #


fn _split_whitespace(s: String) -> List[String]:
    """Split a string by whitespace, returning non-empty tokens."""
    var result = List[String]()
    var bytes = StringSlice(s).as_bytes()
    var n = len(bytes)
    var i = 0

    while i < n:
        # Skip whitespace
        while i < n and (bytes[i] == 32 or bytes[i] == 9):
            i += 1
        if i >= n:
            break
        # Collect token
        var start = i
        while i < n and bytes[i] != 32 and bytes[i] != 9:
            i += 1
        # Build token string
        var token_bytes = List[UInt8](capacity=i - start)
        for j in range(start, i):
            token_bytes.append(bytes[j])
        result.append(String(unsafe_from_utf8=token_bytes^))

    return result^


fn to_lower(s: String) -> String:
    """Convert a string to lowercase (ASCII only).

    Args:
        s: The input string.

    Returns:
        A new string with all ASCII uppercase letters converted to lowercase.
    """
    var bytes = StringSlice(s).as_bytes()
    var n = len(bytes)
    var result = List[UInt8](capacity=n)
    for i in range(n):
        var c = bytes[i]
        if c >= 65 and c <= 90:  # A-Z
            result.append(c + 32)
        else:
            result.append(c)
    return String(unsafe_from_utf8=result^)
