# ===----------------------------------------------------------------------=== #
# Decimo CLI Calculator
#
# A native arbitrary-precision command-line calculator powered by
# Decimo (BigDecimal) and ArgMojo (CLI parsing).
#
# Usage:
#   mojo run -I src -I src/cli src/cli/main.mojo "100 * 12 - 23/17" -P 50
#   ./decimo "100 * 12 - 23/17" -P 50
#   echo "1+2" | mojo run -I src -I src/cli src/cli/main.mojo
#   mojo run -I src -I src/cli src/cli/main.mojo -F expressions.dm -P 100
# ===----------------------------------------------------------------------=== #

from std.sys import exit

from argmojo import Parsable, Option, Flag, Positional, Command
from decimo.rounding_mode import RoundingMode
from calculator.tokenizer import tokenize
from calculator.parser import parse_to_rpn
from calculator.evaluator import evaluate_rpn, final_round
from calculator.display import print_error
from calculator.io import (
    stdin_is_tty,
    read_stdin,
    split_into_lines,
    filter_expression_lines,
    read_file_text,
)
from calculator.repl import run_repl


struct DecimoArgs(Parsable):
    var expr: Positional[
        String,
        help="Math expression to evaluate (e.g. 'sqrt(2)', '1/3 + pi')",
        required=False,
    ]
    var file: Option[
        String,
        long="file",
        short="F",
        help="Evaluate expressions from a file (one per line)",
        default="",
        value_name="PATH",
        group="Input",
    ]
    var precision: Option[
        Int,
        long="precision",
        short="P",
        help="Number of significant digits",
        default="50",
        value_name="N",
        has_range=True,
        range_min=1,
        range_max=1_000_000_000,  # One billion digits is more than sufficient
        group="Computation",
    ]
    var scientific: Flag[
        long="scientific",
        short="S",
        help="Output in scientific notation (e.g. 1.23E+10)",
        group="Formatting",
    ]
    var engineering: Flag[
        long="engineering",
        short="E",
        help="Output in engineering notation (exponent multiple of 3)",
        group="Formatting",
    ]
    var pad: Flag[
        long="pad",
        help="Pad trailing zeros to the specified precision",
        group="Formatting",
    ]
    var delimiter: Option[
        String,
        long="delimiter",
        short="D",
        help="Digit-group separator inserted every 3 digits (e.g. '_' gives 1_234.567_89)",
        default="",
        value_name="CHAR",
        group="Formatting",
    ]
    var rounding_mode: Option[
        String,
        long="rounding-mode",
        short="R",
        help="Rounding mode for the final result",
        default="half-even",
        choices="half-even,half-up,half-down,up,down,ceiling,floor",
        value_name="MODE",
        group="Computation",
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
    cmd.usage("decimo [OPTIONS] [EXPR]")
    cmd.mutually_exclusive(["scientific", "engineering"])
    # Allow expressions starting with '-' (e.g. "-3*pi*(sin(1))") to be
    # treated as positional values rather than option flags.
    for i in range(len(cmd.args)):
        if cmd.args[i].name == "expr":
            cmd.args[i]._allow_hyphen_values = True
            break
    cmd.add_tip(
        'If your expression contains *, ( or ), quote it: decimo "2 * (3 + 4)"'
    )
    cmd.add_tip("Or use noglob: alias decimo='noglob decimo' (add to ~/.zshrc)")
    cmd.add_tip("Pipe expressions: echo '1/3' | decimo -P 100")
    cmd.add_tip("Evaluate a file: decimo -F expressions.dm -P 50")
    var args = DecimoArgs.parse_from_command(cmd^)

    var precision = args.precision.value
    var scientific = args.scientific.value
    var engineering = args.engineering.value
    var pad = args.pad.value
    var delimiter = args.delimiter.value
    var rounding_mode = _parse_rounding_mode(args.rounding_mode.value)

    # ── Mode detection ─────────────────────────────────────────────────────
    # 1. --file flag provided        → file mode
    # 2. Positional expr provided    → expression mode (one-shot)
    # 3. No expr, stdin is piped     → pipe mode
    # 4. No expr, stdin is a TTY     → error (no input)

    var has_file = len(args.file.value) > 0
    var has_expr = len(args.expr.value) > 0

    if has_file and has_expr:
        # Ambiguous: both --file and a positional expression were given.
        print_error("cannot use both -F/--file and a positional expression")
        exit(1)
    elif has_file:
        # ── File mode ────────────────────────────────────────────────────
        _run_file_mode(
            args.file.value,
            precision,
            scientific,
            engineering,
            pad,
            delimiter,
            rounding_mode,
        )
    elif has_expr:
        # ── Expression mode (one-shot) ───────────────────────────────────
        try:
            _evaluate_and_print(
                args.expr.value,
                precision,
                scientific,
                engineering,
                pad,
                delimiter,
                rounding_mode,
                show_expr_on_error=True,
            )
        except:
            exit(1)
    elif not stdin_is_tty():
        # ── Pipe mode ────────────────────────────────────────────────────
        _run_pipe_mode(
            precision,
            scientific,
            engineering,
            pad,
            delimiter,
            rounding_mode,
        )
    else:
        # ── REPL mode ───────────────────────────────────────────────────
        # No expression, no file, no pipe — launch interactive session.
        run_repl(
            precision,
            scientific,
            engineering,
            pad,
            delimiter,
            rounding_mode,
        )


# ===----------------------------------------------------------------------=== #
# Mode implementations
# ===----------------------------------------------------------------------=== #


def _run_pipe_mode(
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
) raises:
    """Read expressions from stdin (one per line) and evaluate each."""
    var text = read_stdin()
    if len(text) == 0:
        return

    var expressions = filter_expression_lines(split_into_lines(text))
    var had_error = False

    for i in range(len(expressions)):
        try:
            _evaluate_and_print(
                expressions[i],
                precision,
                scientific,
                engineering,
                pad,
                delimiter,
                rounding_mode,
                show_expr_on_error=True,
            )
        except:
            had_error = True
            # Continue processing remaining lines

    if had_error:
        exit(1)


def _run_file_mode(
    path: String,
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
) raises:
    """Reads expressions from a file (one per line) and evaluates each."""
    var text: String
    try:
        text = read_file_text(path)
    except e:
        print_error("cannot read file '" + path + "': " + String(e))
        exit(1)
        return  # Unreachable, but keeps the compiler happy

    var expressions = filter_expression_lines(split_into_lines(text))
    var had_error = False

    for i in range(len(expressions)):
        try:
            _evaluate_and_print(
                expressions[i],
                precision,
                scientific,
                engineering,
                pad,
                delimiter,
                rounding_mode,
                show_expr_on_error=True,
            )
        except:
            had_error = True
            # Continue processing remaining lines

    if had_error:
        exit(1)


# ===----------------------------------------------------------------------=== #
# Core evaluation and formatting
# ===----------------------------------------------------------------------=== #


def _evaluate_and_print(
    expr: String,
    precision: Int,
    scientific: Bool,
    engineering: Bool,
    pad: Bool,
    delimiter: String,
    rounding_mode: RoundingMode,
    show_expr_on_error: Bool = False,
) raises:
    """Tokenize, parse, evaluate, and print one expression.

    On error, displays a coloured diagnostic and raises to signal failure
    to the caller.
    """
    try:
        var tokens = tokenize(expr)
        var rpn = parse_to_rpn(tokens^)

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
            if show_expr_on_error:
                _display_calc_error(String(eval_err), expr)
            else:
                print_error(String(eval_err))
            raise eval_err^

    except parse_err:
        if show_expr_on_error:
            _display_calc_error(String(parse_err), expr)
        else:
            print_error(String(parse_err))
        raise parse_err^


def _display_calc_error(error_msg: String, expr: String):
    """Parses a calculator error message and displays it with colours
    and a caret indicator.

    The calculator engine produces errors in two forms:

    1. `Error at position N: <description>`  — with position info.
    2. `<description>`  — without position info.

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
    """Pads (or adds) trailing zeros so the fractional part has exactly
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
    """Converts a CLI rounding-mode name (hyphenated) to a RoundingMode value.
    """
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
