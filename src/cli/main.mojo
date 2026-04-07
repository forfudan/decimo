# ===----------------------------------------------------------------------=== #
# Decimo CLI Calculator
#
# A native arbitrary-precision command-line calculator powered by
# Decimo (BigDecimal) and ArgMojo (CLI parsing).
#
# Usage:
#   mojo run -I src -I src/cli src/cli/main.mojo "100 * 12 - 23/17" -p 50
#   ./decimo "100 * 12 - 23/17" -p 50
# ===----------------------------------------------------------------------=== #

from std.sys import exit

from argmojo import Parsable, Option, Flag, Positional, Command
from decimo.rounding_mode import RoundingMode
from calculator.tokenizer import tokenize
from calculator.parser import parse_to_rpn
from calculator.evaluator import evaluate_rpn, final_round
from calculator.display import print_error


struct DecimoArgs(Parsable):
    var expr: Positional[
        String,
        help="Math expression to evaluate (e.g. 'sqrt(abs(1.1*-12-23/17))')",
        required=True,
    ]
    var precision: Option[
        Int,
        long="precision",
        short="p",
        help="Number of significant digits",
        default="50",
    ]
    var scientific: Flag[
        long="scientific",
        short="s",
        help="Output in scientific notation (e.g. 1.23E+10)",
    ]
    var engineering: Flag[
        long="engineering",
        short="e",
        help="Output in engineering notation (exponent multiple of 3)",
    ]
    var pad: Flag[
        long="pad",
        short="P",
        help="Pad trailing zeros to the specified precision",
    ]
    var delimiter: Option[
        String,
        long="delimiter",
        short="d",
        help="Digit-group separator inserted every 3 digits (e.g. '_' gives 1_234.567_89)",
        default="",
    ]
    var rounding_mode: Option[
        String,
        long="rounding-mode",
        short="r",
        help="Rounding mode for the final result",
        default="half-even",
        choices="half-even,half-up,half-down,up,down,ceiling,floor",
    ]

    @staticmethod
    def description() -> String:
        return "Arbitrary-precision CLI calculator powered by Decimo."

    @staticmethod
    def version() -> String:
        return "0.1.0"

    @staticmethod
    def name() -> String:
        return "decimo"


def main():
    try:
        _run()
    except e:
        # Should not reach here — _run() handles all expected errors.
        # This is a last-resort safety net that still avoids the ugly
        # "Unhandled exception caught during execution:" message.
        print_error(String(e))
        exit(1)


def _run() raises:
    var cmd = DecimoArgs.to_command()
    cmd.mutually_exclusive(["scientific", "engineering"])
    cmd.add_tip(
        'If your expression contains *, ( or ), quote it: decimo "2 * (3 + 4)"'
    )
    cmd.add_tip("Or use noglob: alias decimo='noglob decimo' (add to ~/.zshrc)")
    var args = DecimoArgs.parse_from_command(cmd^)

    var expr = args.expr.value
    var precision = args.precision.value
    var scientific = args.scientific.value
    var engineering = args.engineering.value
    var pad = args.pad.value
    var delimiter = args.delimiter.value
    var rounding_mode = _parse_rounding_mode(args.rounding_mode.value)

    # ── Phase 1: Tokenize & parse ──────────────────────────────────────────
    try:
        var tokens = tokenize(expr)
        var rpn = parse_to_rpn(tokens^)

        # ── Phase 2: Evaluate ────────────────────────────────────────────
        # Syntax was fine — any error here is a math error (division by
        # zero, negative sqrt, …).  No glob hint needed.
        try:
            var value = final_round(
                evaluate_rpn(rpn^, precision), precision, rounding_mode
            )

            if scientific:
                print(value.to_string(scientific=True, delimiter=delimiter))
            elif engineering:
                print(value.to_string(engineering=True, delimiter=delimiter))
            elif pad:
                print(
                    _pad_to_precision(
                        value.to_string(force_plain=True), precision
                    )
                )
            else:
                print(value.to_string(delimiter=delimiter))
        except eval_err:
            _display_calc_error(String(eval_err), expr)
            exit(1)

    except parse_err:
        _display_calc_error(String(parse_err), expr)
        exit(1)


def _display_calc_error(error_msg: String, expr: String):
    """Parse a calculator error message and display it with colours
    and a caret indicator.

    The calculator engine produces errors in two forms:

    1. ``Error at position N: <description>``  — with position info.
    2. ``<description>``  — without position info.

    This function detects form (1), extracts the position, and calls
    `print_error(description, expr, position)` so the user sees a
    visual caret under the offending column.  For form (2) it falls
    back to a plain coloured error.
    """
    comptime PREFIX = "Error at position "

    if error_msg.startswith(PREFIX):
        # Find the colon after the position number.
        var after_prefix = len(PREFIX)
        var colon_pos = -1
        for i in range(after_prefix, len(error_msg)):
            if error_msg[byte=i] == ":":
                colon_pos = i
                break

        if colon_pos > after_prefix:
            # Extract position number and description.
            var pos_str = String(error_msg[byte=after_prefix:colon_pos])
            var description = String(
                error_msg[byte = colon_pos + 2 :]
            )  # skip ": "

            try:
                var pos = Int(pos_str)
                print_error(description, expr, pos)
                return
            except:
                pass  # fall through to plain display

    # Fallback: no position info — just show the message.
    print_error(error_msg)


def _pad_to_precision(plain: String, precision: Int) -> String:
    """Pad (or add) trailing zeros so the fractional part has exactly
    `precision` digits.
    """
    if precision <= 0:
        return plain

    var dot_pos = -1
    for i in range(len(plain)):
        if plain[byte=i] == ".":
            dot_pos = i
            break

    if dot_pos < 0:
        # No decimal point — add one with `precision` zeros
        return plain + "." + "0" * precision

    var frac_len = len(plain) - dot_pos - 1
    if frac_len >= precision:
        return plain

    return plain + "0" * (precision - frac_len)


def _parse_rounding_mode(name: String) -> RoundingMode:
    """Convert a CLI rounding-mode name (hyphenated) to a RoundingMode value."""
    if name == "half-even":
        return RoundingMode.half_even()
    elif name == "half-up":
        return RoundingMode.half_up()
    elif name == "half-down":
        return RoundingMode.half_down()
    elif name == "up":
        return RoundingMode.up()
    elif name == "down":
        return RoundingMode.down()
    elif name == "ceiling":
        return RoundingMode.ceiling()
    elif name == "floor":
        return RoundingMode.floor()
    else:
        # ArgMojo's choices validation should prevent this.
        return RoundingMode.half_even()
