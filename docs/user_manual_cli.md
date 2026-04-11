# Decimo CLI Calculator — User Manual <!-- omit from toc -->

> `decimo` — A native arbitrary-precision command-line calculator powered by Decimo and ArgMojo.

- [Overview](#overview)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Expression Syntax](#expression-syntax)
  - [Numbers](#numbers)
  - [Operators](#operators)
  - [Operator Precedence](#operator-precedence)
  - [Functions](#functions)
  - [Constants](#constants)
- [CLI Options](#cli-options)
  - [Precision (`--precision`, `-P`)](#precision---precision--p)
  - [Scientific Notation (`--scientific`, `-S`)](#scientific-notation---scientific--s)
  - [Engineering Notation (`--engineering`, `-E`)](#engineering-notation---engineering--e)
  - [Pad to Precision (`--pad`)](#pad-to-precision---pad)
  - [Digit Separator (`--delimiter`, `-D`)](#digit-separator---delimiter--d)
  - [Rounding Mode (`--rounding-mode`, `-R`)](#rounding-mode---rounding-mode--r)
- [Input Modes](#input-modes)
  - [Expression Mode (Default)](#expression-mode-default)
  - [Pipe Mode (stdin)](#pipe-mode-stdin)
  - [File Mode (`-F`)](#file-mode--f)
- [Shell Integration](#shell-integration)
  - [Quoting Expressions](#quoting-expressions)
  - [Negative Expressions](#negative-expressions)
  - [Using noglob](#using-noglob)
  - [Shell Completions](#shell-completions)
- [Performance](#performance)
- [Examples](#examples)
  - [Basic Arithmetic](#basic-arithmetic)
  - [High-Precision Calculations](#high-precision-calculations)
  - [Mathematical Functions](#mathematical-functions)
  - [Output Formatting](#output-formatting)
  - [Rounding Modes](#rounding-modes)
- [Error Messages](#error-messages)
- [Full `--help` Reference](#full---help-reference)

## Overview

`decimo` is a command-line calculator that supports:

- **Arbitrary-precision arithmetic** — no limit on the number of digits.
- **High-precision mathematical functions** — `sqrt`, `ln`, `exp`, `sin`, `cos`, `tan`, and more.
- **Mathematical constants** — `pi` and `e` to any number of digits.
- **Output formatting** — scientific, engineering, digit separators, trailing zero padding.
- **Multiple rounding modes** — half-even (banker's), half-up, half-down, up, down, ceiling, floor.

It compiles to a **single native binary** with zero runtime dependencies.

## Installation

Build the CLI from source:

```bash
cd /path/to/decimo
mojo build -I src -I src/cli src/cli/main.mojo -o decimo
```

Then move the binary to a directory in your `$PATH`:

```bash
mv decimo /usr/local/bin/
```

## Quick Start

```bash
# Basic arithmetic
decimo "1 + 2 * 3"
# → 7

# High-precision division
decimo "1/3" -P 100
# → 0.3333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333333

# Square root of 2 to 50 digits
decimo "sqrt(2)" -P 50
# → 1.4142135623730950488016887242096980785696718753770

# 1000 digits of pi
decimo "pi" -P 1000

# Large integer exponentiation
decimo "2^256"
# → 115792089237316195423570985008687907853269984665640564039457584007913129639936
```

## Expression Syntax

### Numbers

- **Integers:** `42`, `-7`, `1000000`
- **Decimals:** `3.14`, `0.001`, `.5`
- **Negative numbers:** `-3`, `-3.14`, `(-5 + 2)`
- **Negative expressions:** `-3*pi`, `-3*pi*(sin(1))`
- **Unary minus:** `2 * -3`, `sqrt(-1 + 2)`

Negative numbers and many expressions starting with `-` can be passed directly as the positional argument. See [Negative Expressions](#negative-expressions) for details.

### Operators

| Operator | Description    | Example       | Result      |
| -------- | -------------- | ------------- | ----------- |
| `+`      | Addition       | `2 + 3`       | `5`         |
| `-`      | Subtraction    | `10 - 4`      | `6`         |
| `*`      | Multiplication | `6 * 7`       | `42`        |
| `/`      | True division  | `1 / 3`       | `0.3333...` |
| `^`      | Power          | `2 ^ 10`      | `1024`      |
| `**`     | Power (alias)  | `2 ** 10`     | `1024`      |
| `(`, `)` | Grouping       | `(2 + 3) * 4` | `20`        |

> **Note:** Division always produces a decimal result. `7 / 2` gives `3.5`, not `3`.

### Operator Precedence

From lowest to highest:

| Precedence | Operators  | Associativity |
| :--------: | ---------- | :-----------: |
|  1 (low)   | `+`, `-`   |     Left      |
|     2      | `*`, `/`   |     Left      |
|     3      | `^` / `**` |     Right     |
|  4 (high)  | unary `-`  |     Right     |

Right-associativity of `^` means `2^3^2` = `2^(3^2)` = `2^9` = `512`, not `(2^3)^2` = `64`.

### Functions

All functions use the CLI's precision setting (default 50, configurable with `-P`).

**Single-argument functions:**

| Function   | Description         | Example               |
| ---------- | ------------------- | --------------------- |
| `sqrt(x)`  | Square root         | `sqrt(2)`             |
| `cbrt(x)`  | Cube root           | `cbrt(27)` → `3`      |
| `abs(x)`   | Absolute value      | `abs(-5)` → `5`       |
| `ln(x)`    | Natural logarithm   | `ln(e)` → `1`         |
| `log10(x)` | Base-10 logarithm   | `log10(1000)` → `3`   |
| `exp(x)`   | Exponential (e^x)   | `exp(1)` → `2.718...` |
| `sin(x)`   | Sine (radians)      | `sin(pi/2)` → `1`     |
| `cos(x)`   | Cosine (radians)    | `cos(0)` → `1`        |
| `tan(x)`   | Tangent (radians)   | `tan(pi/4)` → `1`     |
| `cot(x)`   | Cotangent (radians) | `cot(pi/4)` → `1`     |
| `csc(x)`   | Cosecant (radians)  | `csc(pi/2)` → `1`     |

**Multi-argument functions:**

| Function       | Description             | Example             |
| -------------- | ----------------------- | ------------------- |
| `root(x, n)`   | Nth root of x           | `root(27, 3)` → `3` |
| `log(x, base)` | Logarithm with any base | `log(8, 2)` → `3`   |

Functions can be nested:

```bash
decimo "sqrt(abs(1.1 * -12 - 23/17))"
decimo "ln(exp(1))"   # → 1
```

### Constants

| Constant | Description                 |
| -------- | --------------------------- |
| `pi`     | π (3.14159...)              |
| `e`      | Euler's number (2.71828...) |

Constants are computed to the requested precision:

```bash
decimo "pi" -P 100        # 100 digits of π
decimo "e" -P 500         # 500 digits of e
decimo "2 * pi * 6371"    # Circumference using π
```

## CLI Options

### Precision (`--precision`, `-P`)

Number of significant digits in the result. Default: **50**.

```bash
decimo "1/7" -P 10       # 0.1428571429
decimo "1/7" -P 100      # 100 significant digits
decimo "1/7" -P 200      # 200 significant digits
```

### Scientific Notation (`--scientific`, `-S`)

Output in scientific notation (e.g., `1.23E+10`).

```bash
decimo "123456789 * 987654321" -S
# → 1.21932631112635269E+17
```

### Engineering Notation (`--engineering`, `-E`)

Output in engineering notation (exponent is always a multiple of 3).

```bash
decimo "123456789 * 987654321" -E
# → 121.932631112635269E+15
```

> `--scientific` and `--engineering` are mutually exclusive.

### Pad to Precision (`--pad`)

Pad trailing zeros so the fractional part has exactly `precision` digits after the decimal point.

When used together with `--precision`, the `precision` value is treated as the number of fractional digits for padding purposes, not as a strict limit on total significant digits. As a result, the formatted number can have more than `precision` significant digits.

```bash
decimo "1.5" --pad -P 10
# → 1.5000000000 (10 fractional digits, 11 significant digits)
```

### Digit Separator (`--delimiter`, `-D`)

Insert a character every 3 digits for readability.

```bash
decimo "2^64" -D _
# → 18_446_744_073_709_551_616

decimo "pi" -P 30 -D _
# → 3.141_592_653_589_793_238_462_643_383_28
```

### Rounding Mode (`--rounding-mode`, `-R`)

Choose how the final result is rounded. Default: **half-even** (banker's rounding).

| Mode        | Description                         |
| ----------- | ----------------------------------- |
| `half-even` | Round to nearest even (default)     |
| `half-up`   | Round half away from zero           |
| `half-down` | Round half toward zero              |
| `up`        | Always round away from zero         |
| `down`      | Always round toward zero (truncate) |
| `ceiling`   | Round toward +∞                     |
| `floor`     | Round toward −∞                     |

```bash
decimo "1/6" -P 5 -R half-up       # 0.16667
decimo "1/6" -P 5 -R half-even     # 0.16667
decimo "1/6" -P 5 -R down          # 0.16666
decimo "1/6" -P 5 -R up            # 0.16667
```

## Input Modes

`decimo` accepts input in three ways: a single expression on the command line, piped stdin, or a file.

| Mode       | Invocation              | When used                                          |
| ---------- | ----------------------- | -------------------------------------------------- |
| Expression | `decimo "EXPR"`         | A positional argument is provided as an expression |
| Pipe       | `echo "EXPR" \| decimo` | No positional argument and stdin is not a TTY      |
| File       | `decimo -F FILE.dm`     | The `-F`/`--file` option is used                   |

If no expression is given and stdin is a TTY (interactive terminal), `decimo` prints an error and exits.

### Expression Mode (Default)

Pass a single expression as the positional argument:

```bash
decimo "1/3" -P 100
```

This is the most common usage. See [Expression Syntax](#expression-syntax) for what you can write.

### Pipe Mode (stdin)

When no positional argument is provided and stdin is piped, `decimo` reads all of stdin and evaluates each non-empty, non-comment line:

```bash
# Single expression
echo "sqrt(2)" | decimo -P 30
# → 1.41421356237309504880168872421

# Multiple expressions (one per line)
printf '1/3\nsqrt(2)\npi' | decimo -P 20
# → 0.33333333333333333333
# → 1.4142135623730950488
# → 3.1415926535897932385

# Lines starting with '#' are comments; blank lines are skipped
printf '# constants\npi\n\ne' | decimo -P 10
# → 3.141592654
# → 2.718281828
```

All CLI options (`-P`, `-S`, `-E`, `-D`, `-R`, `--pad`) apply to every line.

If any expression fails, `decimo` prints the error for that line, continues evaluating the remaining lines, and exits with code 1.

### File Mode (`-F`)

Use the `-F` (or `--file`) flag to evaluate expressions from a file, one per line:

```bash
decimo -F expressions.dm -P 50
```

Example file (`expressions.dm`):

```text
# Basic arithmetic
1 + 2
100 * 12 - 23/17

# High-precision constants
pi
e

# Functions
sqrt(2)
ln(10)
```

Comments start with `#`. Inline comments are also supported (e.g. `1+2 # add`). Leading whitespace before `#` is allowed. Blank lines and whitespace-only lines are skipped.

If the specified file does not exist or cannot be read, `decimo` reports an error and exits.

## Shell Integration

### Quoting Expressions

The shell interprets `*`, `(`, `)`, and other characters before `decimo` sees them. **Always wrap expressions in quotes:**

```bash
# ✓ Correct: quoted
decimo "2 * (3 + 4)"

# ✗ Wrong: shell may glob or split
decimo 2 * (3 + 4)
```

### Negative Expressions

Most expressions starting with a hyphen (`-`) are treated as positional arguments, not as option flags:

```bash
# Negative number
decimo "-3.14"
# → -3.14

# Negative expression
decimo "-3*2"
# → -6

# Complex negative expression
decimo "-3*pi*(sin(1))"
# → -7.930677192244368536658197969…

# Options can appear before or after the expression
decimo -P 10 "-3*pi"
decimo "-3*pi" -P 10
```

Because all short option names are uppercase (`-P`, `-S`, `-E`, `-D`, `-R`), expressions like `-e`, `-sin(1)`, and `-pi` are never mistaken for flags:

```bash
# Euler's number, negated
decimo "-e"
# → -2.71828…

# Negative sine
decimo "-sin(1)"
# → -0.84147…

# Negative pi
decimo "-pi"
# → -3.14159…
```

The `--` separator still works if you prefer explicit positional parsing:

```bash
decimo -- "-e"
```

### Using noglob

On zsh, you can use `noglob` to prevent shell interpretation:

```bash
noglob decimo 2*(3+4)
```

Or set up a permanent alias:

```bash
# Add to ~/.zshrc:
alias decimo='noglob decimo'

# Then use without quotes:
decimo 2*(3+4)
```

### Shell Completions

`decimo` can generate completion scripts for **Bash**, **Zsh**, and **Fish**. Tab-completion will suggest option names, rounding mode values, and file paths.

**Zsh** — add to `~/.zshrc`:

```zsh
eval "$(decimo --completions zsh)"
```

**Bash** — add to `~/.bashrc`:

```bash
eval "$(decimo --completions bash)"
```

**Fish** — run once:

```sh
decimo --completions fish | source
# Or persist:
decimo --completions fish > ~/.config/fish/completions/decimo.fish
```

After reloading your shell, pressing Tab after `decimo -` will show all available options, and pressing Tab after `--rounding-mode` will list the seven available modes.

## Performance

`decimo` compiles to a single native binary. For most expressions, end-to-end latency is dominated by process startup rather than computation. The benchmark suite verifies both **correctness** (results agree with `bc` and `python3` to 15 significant digits) and **performance** (wall-clock timing).

Typical latencies (measured on Apple M1 Max, macOS):

| Expression          | Precision | `decimo` | `bc -l` | `python3` | Match |
| ------------------- | :-------: | -------: | ------: | --------: | :---: |
| `1 + 1`             |    50     |    ~6 ms |   ~4 ms |    ~18 ms |   ✓   |
| `100*12 - 23/17`    |    50     |    ~6 ms |   ~4 ms |    ~21 ms |   ✓   |
| `sqrt(2)`           |    50     |    ~5 ms |   ~4 ms |    ~21 ms |   ✓   |
| `ln(2)`             |    50     |    ~5 ms |   ~4 ms |    ~41 ms |   ✓   |
| `sin(1)`            |    50     |    ~6 ms |   ~4 ms |    ~41 ms |   ✓   |
| `pi`                |    50     |    ~6 ms |   ~4 ms |    ~41 ms |   ✓   |
| `sqrt(2)`           |   1000    |    ~6 ms |   ~5 ms |    ~22 ms |   ✓   |
| `pi`                |   1000    |   ~49 ms |  ~13 ms |    ~40 ms |   ✓   |
| pipe: 5 mixed exprs |    50     |    ~8 ms |     N/A |       N/A |       |

Tokenizer and parser overhead is negligible — trivial (`1+1`) and moderate (`sqrt(2)`) expressions complete in ~5 ms. Computation time only becomes visible for expensive operations at very high precision (e.g., computing π to 1000 digits).

`decimo` is **3–4× faster than `python3`** and comparable to `bc` (a lightweight BSD utility).

To run the full benchmark (correctness + performance, all 3 tools):

```bash
bash benches/cli/bench_cli.sh
```

## Examples

### Basic Arithmetic

```bash
decimo "100 * 12 - 23/17"
# → 1198.647058823529411764705882352941176470588235294118

decimo "(1 + 2) * (3 + 4)"
# → 21

decimo "2 ^ 256"
# → 115792089237316195423570985008687907853269984665640564039457584007913129639936
```

### High-Precision Calculations

```bash
# 200 digits of 1/7
decimo "1/7" -P 200

# π to 1000 digits
decimo "pi" -P 1000

# e to 500 digits
decimo "e" -P 500

# sqrt(2) to 100 digits
decimo "sqrt(2)" -P 100
```

### Mathematical Functions

```bash
# Trigonometry
decimo "sin(pi/6)" -P 50       # → 0.5
decimo "cos(pi/3)" -P 50       # → 0.5
decimo "tan(pi/4)" -P 50       # → 1

# Logarithms
decimo "ln(2)" -P 100
decimo "log10(1000)"            # → 3
decimo "log(256, 2)"            # → 8

# Nested functions
decimo "sqrt(abs(1.1 * -12 - 23/17))" -P 30
decimo "exp(ln(100))" -P 30     # → 100

# Cube root
decimo "cbrt(27)"               # → 3
decimo "root(1000000, 6)"       # → 10
```

### Output Formatting

```bash
# Scientific notation
decimo "123456789.987654321" -S
# → 1.23456789987654321E+8

# Engineering notation
decimo "123456789.987654321" -E
# → 123.456789987654321E+6

# Digit separators
decimo "2^100" -D _
# → 1_267_650_600_228_229_401_496_703_205_376

# Pad trailing zeros
decimo "1/4" -P 20 --pad
# → 0.25000000000000000000
```

### Rounding Modes

```bash
# Compare rounding of 2.5 to 0 decimal places:
decimo "2.5 + 0" -P 1 -R half-even   # → 2 (banker's: round to even)
decimo "2.5 + 0" -P 1 -R half-up     # → 3 (traditional)
decimo "2.5 + 0" -P 1 -R down        # → 2 (truncate)
decimo "2.5 + 0" -P 1 -R ceiling     # → 3 (toward +∞)
decimo "2.5 + 0" -P 1 -R floor       # → 2 (toward −∞)
```

## Error Messages

The calculator provides clear error diagnostics with position indicators:

```bash
$ decimo "1 + * 2"
Error: missing operand for '+'
  1 + * 2
    ^

$ decimo "sqrt(-1)"
Error: sqrt() is undefined for negative numbers (got -1)
  sqrt(-1)
  ^^^^

$ decimo "1 / 0"
Error: division by zero
  1 / 0
    ^

$ decimo "hello + 1"
Error: unknown identifier 'hello'
  hello + 1
  ^^^^^

$ decimo "2 * (3 + 4"
Error: unmatched '('
  2 * (3 + 4
      ^
```

## Full `--help` Reference

```txt
Arbitrary-precision CLI calculator powered by Decimo.

Tip: If your expression contains *, ( or ), quote it: decimo "2 * (3 + 4)"
Tip: Or use noglob: alias decimo='noglob decimo' (add to ~/.zshrc)
Tip: Pipe expressions: echo '1/3' | decimo -P 100
Tip: Evaluate a file: decimo -F expressions.dm -P 50

Usage: decimo [OPTIONS] [EXPR]

Arguments:
  expr    Math expression to evaluate
          (e.g. 'sqrt(2)')

Options:
  -P, --precision <N>
          Number of significant digits (default: 50)
  -S, --scientific
          Output in scientific notation (e.g. 1.23E+10)
  -E, --engineering
          Output in engineering notation (exponent multiple of 3)
  --pad
          Pad trailing zeros to the specified precision
  -D, --delimiter <CHAR>
          Digit-group separator inserted every 3 digits (e.g. '_' gives 1_234.567_89)
  -R, --rounding-mode <MODE>
          Rounding mode for the final result (default: half-even)
          {half-even,half-up,half-down,up,down,ceiling,floor}
  -F, --file <PATH>
          Evaluate expressions from a file (one per line)
  -h, --help
          Show this help message
  -V, --version
          Show version
```
