# Decimo CLI Calculator (`decimo`)

> A native arbitrary-precision command-line calculator powered by Decimo and
> ArgMojo.


> [!NOTE]
> **This document can be closed (reviewed 2026-08-26).** The calculator is
> built (`pixi run buildcli`), shipped, and covered by 58 integration tests.
> One item from the implementation table is outstanding and minor: the `:vars`
> meta-command. Kept as the design record.

## Motivation

Decimo provides arbitrary-precision decimal arithmetic in Mojo, but currently
lacks a quick way for users to interact with it outside of writing Mojo
programs. A CLI calculator would:

- Serve as the primary demo/showcase for Decimo's capabilities.
- Provide a practical tool that outperforms `bc` (limited precision) and
  `python3 -c` (slow startup) for ad-hoc calculations.
- Act as a real-world integration test for both
  [Decimo](https://github.com/forfudan/decimo) and
  [ArgMojo](https://github.com/forfudan/argmojo).
- Compile to a single native binary with zero dependencies.

## Feature Comparison

Rows are sorted by implementation priority for `decimo` (top = implement first).

| #   | Core feature               | decimo | bc  | dc  | qalc | calc (apcalc) | python3 -c | expr | octave-cli | Phase |
| --- | -------------------------- | ------ | --- | --- | ---- | ------------- | ---------- | ---- | ---------- | ----- |
| 1   | Basic arithmetic           | ✓      | ✓   | ✓   | ✓    | ✓             | ✓          | ✓    | ✓          | 1     |
| 2   | High-precision decimals    | ✓      | ✓   | ✓   | ✓    | ✓             | ✗          | ✗    | ✗          | 1     |
| 3   | Large integers (arbitrary) | ✓      | ✓   | ✓   | ✓    | ✓             | ✓          | ✗    | ✗          | 1     |
| 4   | Pipeline/Batch scripting   | ✓      | ✓   | ✓   | ✓    | ✓             | ✓          | ✓    | ✓          | 1     |
| 5   | Built-in math functions    | ✓      | ✓   | ✗   | ✓    | ✓             | ✓          | ✗    | ✓          | 2     |
| 6   | Interactive REPL           | ✓      | ✓   | ✓   | ✓    | ✓             | ✗          | ✗    | ✓          | 4     |
| 7   | Variables/State            | ✓      | ✓   | ✓   | ✓    | ✓             | ✓          | ✗    | ✓          | 4     |
| 8   | Unit conversion            | ✗      | ✗   | ✗   | ✓    | ✗             | ✗          | ✗    | ✗          | 6     |
| 9   | Matrix/Linear algebra      | ✗      | ✗   | ✗   | ✗    | ✓             | ✗          | ✗    | ✓          | 6     |
| 10  | Symbolic computation       | ✗      | ✗   | ✗   | △    | ✗             | ✗          | ✗    | ✗          | 6     |

**Priority rationale:**

1. **Basic arithmetic + High-precision + Large integers + Pipeline** (Phase 1) —
   These are the raison d'être of `decimo`. Decimo already provides
   arbitrary-precision `BigDecimal`; wiring up tokenizer → parser → evaluator
   gives immediate value. Pipeline/batch is nearly free once one-shot works
   (just loop over stdin lines).
2. **Built-in math functions** (Phase 2) — `sqrt`, `ln`, `exp`, `sin`, `cos`,
   `tan`, `root` already exist in the Decimo API. Adding them mostly means
   extending the tokenizer/parser to recognize function names.
3. **Polish & ArgMojo integration** (Phase 3) — Error diagnostics, edge-case
   handling, and exploiting ArgMojo v0.5.0 features (shell completions, argument
   groups, numeric range validation, etc.). Mostly CLI UX refinement.
4. **Interactive REPL** (Phase 4) — Requires a read-eval-print loop, `ans`
   tracking, named variable storage, session-level precision management. No
   subcommands — mode is determined by invocation context (same as `bc`,
   `python3`, `calc`).
5. **User-defined functions & mini-interpreter** (Phase 5) — Reusable named
   functions (`f(x) = expr`), library files (`-L`), interactive-after-load
   (`-I`), `~/.decimorc`. Statement-grammar features (block bodies, loops,
   arrays) gated on demand to avoid scope creep into a Python competitor.
6. **Future enhancements** (Phase 6) — Binary distribution, CJK full-width
   detection, response files, unit conversion, matrix, symbolic. Out of scope
   for now.

## Usage Design

`decimo` supports two modes of operation:

### Mode 1: One-Shot (Expression Mode)

Pass the expression as a single quoted string. This avoids shell interpretation
of `*`, `(`, `)`, etc. All other arguments are flags or options parsed by
ArgMojo.

```bash
# Basic arithmetic
decimo "100 * 12 - 23/17"
# → 1198.647058823529411764705882352941176470588235294118

# Control precision
decimo "sqrt(2)" --precision 100
decimo "1/3" -p 200

# Output formatting
decimo "pi" --sci                    # Scientific notation
decimo "1/7" --eng                   # Engineering notation
decimo "1.5" --pad-to-precision      # Pad trailing zeros

# Functions
decimo "ln(2) + exp(1)"
decimo "sin(pi/4)"
decimo "2 ^ 256"
decimo "root(27, 3)"                 # Cube root

# Built-in constants
decimo "pi" -p 1000
decimo "e" -p 500

# Help
decimo --help
decimo --version
```

Best for: quick one-off calculations from the command line.

### Mode 2: Pipe and File Input

Read expressions from stdin or a file — one expression per line, one result per
line.

```bash
# Pipe a single expression
echo "1+2" | decimo
# → 3

# Pipe multiple expressions
printf "1/3\nsqrt(2)\npi" | decimo -p 50
# → 0.33333333333333333333333333333333333333333333333333
# → 1.4142135623730950488016887242096980785696718753769
# → 3.1415926535897932384626433832795028841971693993751

# Read from a file (one expression per line)
cat expressions.txt | decimo
decimo < expressions.txt

# Evaluate a script file (.dm)
decimo -F file.dm
```

Example `expressions.dm`:

```bash
# Compute some constants
pi
e
sqrt(2)

# Some arithmetic
100 * 12 - 23/17
2 ^ 256
```

Features:

- Lines starting with `#` are treated as comments and ignored.
- Blank lines are skipped.
- Each line is evaluated independently; results are printed one per line.
- Flags like `--precision` apply to all expressions.

Best for: scripting, piping, batch calculations, reproducible computation files.

### Mode 3: Interactive REPL

Run `decimo` with no expression (or with `-i`) to enter an interactive session.
Type an expression, press Enter, get the result, and continue.

```bash
$ decimo
decimo> 1 + cos(3.43)
0.05738090582281618981744744369505543455
decimo> sqrt(2)
1.41421356237309504880168872420969807857
decimo> ans * 2
2.82842712474619009760337744841939615714
decimo> x = 100 / 7
14.28571428571428571428571428571428571429
decimo> x ^ 2
204.08163265306122448979591836734693877551
decimo> exit
```

Features:

- `ans` — automatically holds the previous result.
- Variable assignment — `x = <expr>` stores a named value for later use.
- Precision — set once with `decimo -p 100` or change mid-session with
  `:precision 100`.
- Quit — `exit`, `quit`, or Ctrl-D.

Best for: interactive exploration, multi-step calculations, experimenting with
precision.

## Architecture

```txt
┌─────────────┐     ┌──────────┐     ┌────────────┐     ┌──────────┐     ┌──────────┐
│    Shell    │---->│ ArgMojo  │---->│ Tokenizer  │---->│  Parser  │---->│ Evaluator│
│   (argv)    │     │ (CLI)    │     │            │     │ (Shunt.) │     │ (Decimo) │
└─────────────┘     └──────────┘     └────────────┘     └──────────┘     └──────────┘
       │                  │                │                  │                │
  "100*2+1"         extract expr      [100,*,2,+,1]    RPN: [100,2,*,1,+]  BigDecimal
  --precision 50    + flags/options                                          → "201"
```

### Layer 1: ArgMojo — CLI Argument Parsing

ArgMojo handles the outer CLI structure via its struct-based declarative API
(`Parsable` trait).

```mojo
from argmojo import Parsable, Option, Flag, Positional, Command

struct DecimoArgs(Parsable):
    var expr: Positional[String, help="Math expression to evaluate", required=True]
    var precision: Option[Int, long="precision", short="p", help="Number of significant digits",
        default="50", value_name="N", has_range=True, range_min=1, range_max=1000000000, group="Computation"]
    var scientific: Flag[long="scientific", short="s", help="Output in scientific notation", group="Formatting"]
    var engineering: Flag[long="engineering", short="e", help="Output in engineering notation", group="Formatting"]
    var pad: Flag[long="pad", short="P", help="Pad trailing zeros to the specified precision", group="Formatting"]
    var delimiter: Option[String, long="delimiter", short="d", help="Digit-group separator",
        default="", value_name="CHAR", group="Formatting"]
    var rounding_mode: Option[String, long="rounding-mode", short="r", help="Rounding mode",
        default="half-even", choices="half-even,half-up,half-down,up,down,ceiling,floor",
        value_name="MODE", group="Computation"]
```

### Layer 2: Tokenizer — Lexical Analysis

Convert the expression string into a stream of tokens.

Token types:

- **Number**: integer or decimal literal (`123`, `3.14`, `.5`, `1e10`)
- **Operator**: `+`, `-`, `*`, `/`, `^` (or `**`)
- **Left paren / Right paren**: `(`, `)`
- **Function**: `sqrt`, `ln`, `log`, `exp`, `sin`, `cos`, `tan`, `root`, `abs`
- **Constant**: `pi`, `e`
- **Comma**: `,` (for multi-argument functions like `root(x, n)`)

Edge cases to handle:

- Unary minus: `-3`, `(-5+2)`, `2*-3`
- Implicit multiplication (future): `2pi`, `3(4+5)`

### Layer 3: Parser — Shunting-Yard Algorithm

Convert infix tokens to Reverse Polish Notation (RPN) using Dijkstra's
shunting-yard algorithm.

Operator precedence and associativity:

| Precedence | Operators | Associativity |
| :--------: | --------- | :-----------: |
|  1 (low)   | `+`, `-`  |     Left      |
|     2      | `*`, `/`  |     Left      |
|     3      | `^`       |     Right     |
|  4 (high)  | unary `-` |     Right     |

Functions are pushed onto the operator stack and popped when their closing `)`
is encountered.

### Layer 4: Evaluator — Decimo Computation

Walk the RPN queue with a `BigDecimal` stack:

- **Number token** → push `BigDecimal(token_str)` onto stack.
- **Constant token** → push precomputed value (e.g., `compute_pi(precision)`).
- **Binary operator** → pop two operands, compute, push result.
- **Unary operator** → pop one operand, compute, push result.
- **Function** → pop argument(s), call corresponding Decimo function, push
  result.

Mapping to Decimo API:

| Expression  | Decimo call                       |
| ----------- | --------------------------------- |
| `a + b`     | `a + b`                           |
| `a - b`     | `a - b`                           |
| `a * b`     | `a * b`                           |
| `a / b`     | `a.true_divide(b, precision)`     |
| `a ^ b`     | `power(a, b, precision)`          |
| `sqrt(a)`   | `sqrt(a, precision)`              |
| `root(a,n)` | `root(a, n, precision)`           |
| `ln(a)`     | `ln(a, precision)`                |
| `log(a)`    | `log10(a, precision)`             |
| `exp(a)`    | `exp(a, precision)`               |
| `sin(a)`    | `sin(a, precision)`               |
| `cos(a)`    | `cos(a, precision)`               |
| `tan(a)`    | `tan(a, precision)`               |
| `abs(a)`    | `abs(a)`                          |
| `pi`        | `compute_pi(precision)`           |
| `e`         | `exp(BigDecimal("1"), precision)` |

### Layer 5: Output Formatting

Format the final `BigDecimal` result based on CLI flags:

- Default: plain decimal string (strip trailing zeros).
- `--sci`: scientific notation (`1.23E+10`).
- `--eng`: engineering notation (exponent is multiple of 3).
- `--pad-to-precision`: keep trailing zeros up to the specified precision.

## Implementation Steps

### Phase 1: MVP — Four Operations

1. Set up project structure (new repo or subdirectory under Decimo).
2. Implement the tokenizer for numbers and `+ - * /` operators.
3. Implement the shunting-yard parser with parentheses support.
4. Implement the RPN evaluator using `BigDecimal`.
5. Wire up ArgMojo for `expr`, `--precision`, and `--help`.
6. Handle unary minus.
7. Test with basic expressions.

| #   | Task                                             | Status | Notes                                                                                        |
| --- | ------------------------------------------------ | :----: | -------------------------------------------------------------------------------------------- |
| 1.1 | Project structure (src/cli/, calculator module)  |   ✓    |                                                                                              |
| 1.2 | Tokenizer (numbers, `+ - * /`, parens)           |   ✓    |                                                                                              |
| 1.3 | Shunting-yard parser (infix → RPN)               |   ✓    |                                                                                              |
| 1.4 | RPN evaluator using `BigDecimal`                 |   ✓    |                                                                                              |
| 1.5 | ArgMojo wiring (`expr`, `--precision`, `--help`) |   ✓    |                                                                                              |
| 1.6 | Unary minus                                      |   ✓    |                                                                                              |
| 1.7 | Basic expression tests                           |   ✓    | 4 test files                                                                                 |
| 1.8 | Pipeline / stdin input (`echo "1+2" \| decimo`)  |   ✓    | Pipe mode: reads stdin when no positional arg and stdin is not a TTY                         |
| 1.9 | File input (`decimo -F file.dm`)                 |   ✓    | File mode via `-F/--file` flag: reads files line by line, skips comments (#) and blank lines |

### Phase 2: Power and Functions

1. Add `^` operator with right associativity.
2. Add function call parsing (`sqrt(...)`, `ln(...)`, etc.).
3. Add multi-argument function support (`root(x, n)`).
4. Add built-in constants (`pi`, `e`).
5. Add output formatting flags (`--scientific` or `-s`, `--engineering` or `-e`,
   `--pad-to-precision` or `-P`).

| #    | Task                                                              | Status | Notes                                           |
| ---- | ----------------------------------------------------------------- | :----: | ----------------------------------------------- |
| 2.1  | `^` operator (right-associative, `**` alias)                      |   ✓    |                                                 |
| 2.2  | Single-arg functions: `sqrt`, `cbrt`, `ln`, `log10`, `exp`, `abs` |   ✓    |                                                 |
| 2.3  | Trig functions: `sin`, `cos`, `tan`, `cot`, `csc`                 |   ✓    | `cot` and `csc` are extras beyond original plan |
| 2.4  | Multi-arg functions: `root(x, n)`, `log(x, base)`                 |   ✓    | `log(x, base)` is an extra                      |
| 2.5  | Constants: `pi`, `e`                                              |   ✓    |                                                 |
| 2.6  | `--scientific` / `-s`                                             |   ✓    |                                                 |
| 2.7  | `--engineering` / `-e`                                            |   ✓    |                                                 |
| 2.8  | `--pad` / `-P` (trailing zeros)                                   |   ✓    |                                                 |
| 2.9  | `--delimiter` / `-d` (digit grouping)                             |   ✓    | Extra feature beyond original plan              |
| 2.10 | `--rounding-mode` / `-r`                                          |   ✓    | 7 modes; extra feature beyond original plan     |

### Phase 3: Polish & ArgMojo Deep Integration

> ArgMojo v0.5.0 is installed via pixi. Reference:
> <https://github.com/forfudan/argmojo> ·
> [User Manual](https://github.com/forfudan/argmojo/wiki)

1. Error messages: clear diagnostics for malformed expressions (e.g.,
   "Unexpected token '*' at position 5").
2. Edge cases: division by zero, negative sqrt, overflow, empty expression.
3. Upgrade to ArgMojo v0.5.0 and adopt declarative API.
4. Exploit ArgMojo v0.5.0 features: shell completions, numeric validation, help
   readability, argument groups.
5. Performance: ensure the tokenizer/parser overhead is negligible compared to
   BigDecimal computation.
6. Documentation and examples in README (include shell completion setup).
7. Build and distribute as a single binary.

| #    | Task                                                            | Status | Notes                                                                                      |
| ---- | --------------------------------------------------------------- | :----: | ------------------------------------------------------------------------------------------ |
| 3.1  | Error messages with position info + caret display               |   ✓    | Colored stderr: red `Error:`, green `^` caret                                              |
| 3.2  | Edge cases (div-by-zero, negative sqrt, empty expression, etc.) |   ✓    | 27 error-handling tests                                                                    |
| 3.3  | ArgMojo v0.5.0 declarative API migration                        |   ✓    | `Parsable` struct, `add_tip()`, `mutually_exclusive()`, `choices`, `--version` all working |
| 3.4  | Built-in features (free with ArgMojo v0.5.0)                    |   ✓    | Typo suggestions, `NO_COLOR`, CJK full-width correction, prefix matching, `--` stop marker |
| 3.5  | Shell completion (`--completions bash\|zsh\|fish`)              |   ✓    | Built-in — zero code; needs documentation in user manual and README                        |
| 3.6  | `allow_negative_numbers()` to allow pure negative numbers       |   ✓    | Superseded by 3.15 `allow_hyphen=True`; removed in favour of the more general approach     |
| 3.7  | Numeric range on `precision`                                    |   ✓    | `has_range=True, range_min=1, range_max=1000000000`; rejects `--precision 0` or `-5`       |
| 3.8  | Value names for help readability                                |   ✓    | `--precision <N>`, `--delimiter <CHAR>`, `--rounding-mode <MODE>`                          |
| 3.9  | Argument groups in help output                                  |   ✓    | `Computation` and `Formatting` groups in `--help`                                          |
| 3.10 | Custom usage line                                               |   ✓    | `Usage: decimo [OPTIONS] <EXPR>`                                                           |
| 3.11 | `Parsable.run()` override                                       |   ✗    | Move eval logic into `DecimoArgs.run()` for cleaner separation                             |
| 3.12 | Performance validation                                          |   ✓    | `benches/cli/bench_cli.sh`; 47 correctness checks + timing vs `bc` and `python3`           |
| 3.13 | Documentation (user manual for CLI)                             |   ✓    | `docs/user_manual_cli.md`; includes shell completions setup and performance data           |
| 3.14 | Allow negative expressions                                      |   ✓    | `allow_hyphen=True` on `Positional`; `decimo "-3*pi*(sin(1))"` works                       |
| 3.15 | Make short names upper cases to avoid expression collisions     |   ✓    | `-P`, `-S`, `-E`, `-R`; `--pad`, `--delimiter` have no short name                          |
| 3.16 | Define `allow_hyphen_values` in declarative API                 |   ✗    | When argmojo supports it (expected in v0.6.0)                                              |

### Phase 4: Interactive REPL

No subcommands — mode is determined by invocation context (same as `bc`,
`python3`, `calc`):

| Invocation                         | Mode     |
| ---------------------------------- | -------- |
| `decimo "expr"`                    | One-shot |
| `echo "expr" \| decimo`            | Pipe     |
| `decimo -F file.dm`                | File     |
| `decimo` (no args, stdin is a TTY) | REPL     |

Design rationale: subcommands (`decimo eval`, `decimo repl`) create collision
risk with expression identifiers (e.g. `log`, `exp`) and multi-arg function
names. Every comparable tool (`bc`, `dc`, `calc`, `qalc`, `python3`) uses the
same zero-subcommand pattern.

**REPL features:**

1. Read-eval-print loop: read a line, evaluate, print result, repeat.
2. `ans` — automatically holds the previous result.
3. Variable assignment — `x = <expr>` stores a named value.
4. Meta-commands with `:` prefix — avoids collision with expressions.
5. Error recovery — display error and continue, don't crash the session.
6. Exit via `exit`, `quit`, or Ctrl-D.

```bash
$ decimo
decimo> 100 * 12
1200
decimo> ans - 23/17
1198.647058823529411764705882352941176470588235294118
decimo> x = sqrt(2)
1.41421356237309504880168872420969807856967187537694
decimo> x ^ 2
2
decimo> :precision 100
Precision set to 100
decimo> 1/0
Error: division by zero
decimo> exit
```

| #    | Task                                       | Status | Notes                                                                       |
| ---- | ------------------------------------------ | :----: | --------------------------------------------------------------------------- |
| 4.1  | No-args + TTY → launch REPL                |   ✓    | Replace "no expression" error with REPL auto-launch when terminal detected  |
| 4.2  | Read-eval-print loop                       |   ✓    | `read_line()` via `getchar()`; one expression per line                      |
| 4.3  | Custom prompt (`decimo>`)                  |   ✓    | Coloured prompt to stderr so results can be piped                           |
| 4.4  | `ans` variable (previous result)           |   ✓    | Stored in `Dict[String, Decimal]`; updated after each successful evaluation |
| 4.5  | Variable assignment (`x = expr`)           |   ✓    | `name = expr` detection in REPL; protected names (pi, e, functions, ans)    |
| 4.6  | Meta-commands (`:precision N`, etc.)       |   ✓    | `:` prefix avoids collision; settings names + aliases (`:vars` not yet)     |
| 4.7  | One-line quick setting                     |   ✓    | `:p 100 s r down` sets precision, scientific, and rounding in one line      |
| 4.8  | Same-line temp precision setting           |   ✓    | `2*sqrt(1.23):p 100 s r down` — temp override via `:` separator             |
| 4.9  | Print settings (`:`)                       |   ✓    | Bare `:` displays full settings block; shown after every `:...` change      |
| 4.10 | Variable listing (`:v`, `:vars`, `$`)      |   ✓    | `:v` / `:vars` or bare `$` lists `ans` first, then user variables           |
| 4.11 | Help command (`?`)                         |   ✓    | `?` / `:help` / `:h` / `:?`; colourful output with section headings         |
| 4.12 | Better header banner                       |   ✓    | Compact: title + "Type ? for help, : for settings, :q to quit."             |
| 4.13 | Everything in the REPL is case-insensitive |   ✓    | `to_lower()` applied to all input before processing (pre-tokenizer stage)   |
| 4.14 | Graceful exit (`exit`, `quit`, Ctrl-D)     |   ✓    |                                                                             |
| 4.15 | Error recovery (don't crash session)       |   ✓    | Catch exceptions per-line, display error, continue loop                     |
| 4.16 | `:100` in REPL settings to set precision   |   ✓    | Shortcut of `:p 100`. Any all-digit token is treated as precision           |
| 4.17 | Add `--about`/`--info` flag and in REPL    |   ✓    | Display version, build info, links to docs/repo, etc, for both CLI and REPL |
| 4.18 | Line editing (left/right, backspace, del)  |   ✓    | Implemented via `limo` package; see `docs/plans/line_editor.md`             |
| 4.19 | Input history (up/down arrow navigation)   |   ✓    | Implemented via `limo` package; see `docs/plans/line_editor.md`             |

將所有的設定放在一行，這個靈感主要來自於 argmojo，其實就是把 CLI
的選項直接放到了 REPL
的表達式行中。這個想法我個人是很喜歡的，因為它簡潔明瞭，避免了多行設定的冗長。

### Phase 5: User-Defined Functions & Mini-Interpreter

Reuse a stored expression as a named function — `bc`'s killer feature for
ratios, statistical formulas, and personal libraries (`~/.bcrc` workflows).
Today's parser is purely *expression-oriented* (shunting-yard → RPN). User
functions promote the language one rung up the ladder toward a mini
interpreter, so each rung is gated on demand to avoid scope creep.

```bash
# Define inline in the REPL
decimo> tax(x) = x * 0.05
decimo> total(p, q) = p + tax(p) + q
decimo> total(100, 20)
125

# Or load a library file and drop into REPL
$ decimo -L ~/myfuncs.decimo -I
decimo> :funcs
tax(x), total(p, q), bmi(w, h)
```

**File format** (`.dm` or `.decimo`): one definition per line, `#` comments,
blank lines skipped — same conventions as the existing `-F` script format.

**Trade-offs:**

1. **Single-line `f(x) = expr` vs block `def f(x) { ... }`** — single-line
   keeps the existing expression grammar. Block bodies fork it into a
   *statement* grammar (locals, `return`, `;`/newline separators) and double
   the parser/evaluator surface. Start single-line; promote to blocks only
   if real demand appears.
2. **Disambiguation with variables** — REPL already has `x = expr`. Function
   defs `f(x) = expr` are unambiguous because the LHS contains parens; reuse
   `=` rather than introducing `def` / `fn`.
3. **`-F` vs `-L`** — `-F file.dm` already executes and prints each line.
   Library files (definitions only, silent load) need different semantics →
   add `-L/--load`. Both must compose with `-I/--interactive`.
4. **File extension** — `.dm` already in use. Add `.decimo` as an explicit
   alias for clarity. Avoid `.txt` (too generic, no editor support).
5. **Recursion depth** — cap at e.g. 1000 frames with a friendly error to
   prevent native stack overflow.
6. **Scope** — function parameters shadow globals; assignments inside a
   function are local by default (bc rule). No closures.
7. **Case-insensitivity** — REPL is case-insensitive; function names follow
   suit. Guard against shadowing built-ins (`sin`, `pi`, …).
8. **Loops/arrays gate** — only ship if recursion + functions + ternary
   prove insufficient for actual user requests. Otherwise users should reach
   for `python3`, whose unique value (full scripting) `decimo` is not trying
   to compete with. `decimo`'s niche is *fast startup + arbitrary precision*.

| #    | Task                                                  | Status | Notes                                                                                   |
| ---- | ----------------------------------------------------- | :----: | --------------------------------------------------------------------------------------- |
| 5.1  | Single-line user functions `f(x) = expr`              |   ✗    | Tokenizer + statement-vs-expression dispatcher; LHS-paren disambiguates from `x = expr` |
| 5.2  | Multi-arg + recursion `g(x, y) = …`                   |   ✗    | Recursion-depth cap (≈1000) with friendly error                                         |
| 5.3  | Local parameter scope, no closures                    |   ✗    | Params shadow globals; assignments inside a def are local by default (bc rule)          |
| 5.4  | `-L/--load <file>` to load a library (silent eval)    |   ✗    | Accepts `.dm` and `.decimo`; only definitions printed silently                          |
| 5.5  | `-I/--interactive` enters REPL after `-F`/`-L`        |   ✗    | `decimo -L lib.dm -I`; composes with existing `-F`                                      |
| 5.6  | Auto-load `~/.decimorc`                               |   ✗    | Skippable via `--no-rc`; load order: rc → `-L` → `-F` → REPL                            |
| 5.7  | `:funcs` / `:f` — list user-defined functions in REPL |   ✗    | Mirrors `:vars` / `$`                                                                   |
| 5.8  | `if(cond, then, else)` ternary expression             |   ✗    | Small grammar addition, no statement layer; enables piecewise functions                 |
| 5.9  | (Research) Block bodies `def f(x) { … }` + `return`   |   ✗    | Statement grammar; decide after 5.1–5.8 land based on real demand                       |
| 5.10 | (Research) `while` / `for` loops                      |   ✗    | Significant grammar/runtime jump; gate on demand recursion can't satisfy                |
| 5.11 | (Research) Arrays `a[0]`, `len(a)`                    |   ✗    | Largest change (mutable storage, indexing grammar); defer until 5.9–5.10 settled        |

### Phase 6: Future Enhancements

1. Build and distribute as a single binary (Homebrew, GitHub Releases, etc.) —
   defer until REPL is stable so first-run experience is complete.
2. Detect full-width digits/operators for CJK users while parsing.
3. Response files (`@expressions.txt`) — when Mojo compiler bug is fixed, use
   ArgMojo's `cmd.response_file_prefix("@")`.

| #   | Task                                        | Status | Notes                                                                             |
| --- | ------------------------------------------- | :----: | --------------------------------------------------------------------------------- |
| 6.1 | Full-width digit/operator detection for CJK |   ✗    | Tokenizer-level handling for CJK users                                            |
| 6.2 | Full-width to half-width normalization      |   ✗    | Pre-tokenizer normalization step to convert full-width chars to ASCII equivalents |
| 6.3 | Build and distribute as single binary       |   ✗    | Defer until REPL is stable; Homebrew, GitHub Releases, `curl \| sh` installer     |
| 6.4 | Response files (`@expressions.txt`)         |   ✗    | Blocked on Mojo compiler bug; `cmd.response_file_prefix("@")` ready when fixed    |
| 6.5 | Re-evaluate limo/argmojo FFI alignment      |   ✗    | Check if Mojo resolves `external_call` signature conflicts; see `line_editor.md`  |

## Design Decisions

### All Numbers Are `BigDecimal`

All numeric literals and computation results are stored as `BigDecimal`, not
integers. This means:

- `1 + 2` → `BigDecimal("3")`, displayed as `3` (no trailing `.0`).
- `1 / 3` → `BigDecimal` with full precision, not integer `0`.
- `2 ^ 256` → exact integer result stored as `BigDecimal` with scale 0.

This is the natural choice for a calculator: users expect `7 / 2` to be `3.5`,
not `3`. Integer-only results are displayed without a decimal point (scale 0
values are printed as plain integers), so the experience is seamless.

### Mode Detection

`decimo` automatically detects its mode based on how it is invoked:

| Invocation                            | Mode                              |
| ------------------------------------- | --------------------------------- |
| `decimo "expr"`                       | One-shot: evaluate and exit       |
| `echo "expr" \| decimo`               | Pipe: read stdin line by line     |
| `decimo -F file.dm`                   | File: read and evaluate each line |
| `decimo` (no args, terminal is a TTY) | REPL: interactive session         |

## Notes

- In one-shot mode, the expression is a single quoted string to prevent shell
  globbing and special character issues.
- Division uses `true_divide` (not integer division) by default, matching
  calculator user expectations.
- Precision applies to intermediate computations as well (via
  `working_precision`), not just the final display.
- File and pipe modes evaluate each line independently. Use the REPL for
  stateful multi-line sessions with variables.
