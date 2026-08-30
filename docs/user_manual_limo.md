# Limo — Developer Manual <!-- omit from toc -->

> A lightweight line editor for the decimo REPL, written in Mojo.
> Location: `src/cli/limo/`

- [Overview](#overview)
- [Quick Start](#quick-start)
- [Package Structure](#package-structure)
- [Supported Keybindings](#supported-keybindings)
- [Module Reference: terminal.mojo](#module-reference-terminalmojo)
  - [Background: What Is a Terminal Driver?](#background-what-is-a-terminal-driver)
  - [Background: Cooked Mode vs Raw Mode](#background-cooked-mode-vs-raw-mode)
  - [Constants — File Descriptors](#constants--file-descriptors)
  - [Constants — Terminal Flags](#constants--terminal-flags)
  - [Constants — Control Character Indices](#constants--control-character-indices)
  - [Struct: TermIOS](#struct-termios)
  - [FFI Functions — Talking to the OS](#ffi-functions--talking-to-the-os)
  - [FFI Signature Convention (Alignment with argmojo)](#ffi-signature-convention-alignment-with-argmojo)
  - [Raw Mode Control Functions](#raw-mode-control-functions)
  - [I/O Primitive Functions](#io-primitive-functions)
  - [ANSI Escape Helper Functions](#ansi-escape-helper-functions)
- [Module Reference: line\_editor.mojo](#module-reference-line_editormojo)
  - [Action Constants](#action-constants)
  - [Struct: LineEditor](#struct-lineeditor)
  - [The Main Loop: read\_line()](#the-main-loop-read_line)
  - [Escape Sequence Parsing](#escape-sequence-parsing)
  - [Screen Redraw Algorithm](#screen-redraw-algorithm)
  - [Buffer Manipulation Functions](#buffer-manipulation-functions)
  - [History Navigation Functions](#history-navigation-functions)
- [Integration with Decimo REPL](#integration-with-decimo-repl)
- [Terminology Reference](#terminology-reference)
- [Phase Roadmap](#phase-roadmap)

## Overview

Limo (**li**ne + **mo**jo) is a minimal, zero-dependency line-editing library
that gives the decimo REPL arrow-key navigation, Emacs-style keyboard shortcuts,
and input history. It is inspired by
[linenoise](https://github.com/antirez/linenoise) (a ~1,100-line C line editor
by Salvatore Sanfilippo) and adapted from
[termo](https://github.com/forfudan/termo) (a Mojo terminal control library by
the same author).

Limo lives inside the decimo repository at `src/cli/limo/` and is compiled as a
Mojo package that the calculator REPL imports. In the future it may be extracted
into its own standalone repository.

**Design goals:**

- **Minimal** — two modules plus an `__init__`, about 1,000 lines in total.
- **No dependencies** — only uses Mojo's standard library and libc FFI calls.
- **Focused** — single-line editing only. No multi-line, no TUI, no screen
  buffer.
- **Reusable** — any Mojo CLI tool could import limo for interactive input.

## Quick Start

```mojo
from limo import LineEditor

var editor = LineEditor()
while True:
    var line = editor.read_line("prompt> ")
    if not line:
        break  # User pressed Ctrl-D on an empty line (EOF)
    print("You typed:", line.value())
```

That's the entire public API. Call `read_line()` in a loop. It returns
`Optional[String]` — a `String` on Enter, or `None` on EOF.

## Package Structure

```txt
src/cli/limo/
├── __init__.mojo          # Re-exports LineEditor (the only public symbol)
├── terminal.mojo          # Raw mode, byte reading, ANSI escape sequences
└── line_editor.mojo       # LineEditor struct: editing, history, key dispatch
```

- `__init__.mojo` is the public door. Users write `from limo import LineEditor`
  without knowing about the internal files.
- `terminal.mojo` handles the low-level conversation with the operating system's
  terminal driver (detailed below).
- `line_editor.mojo` implements the user-facing `LineEditor` struct that ties
  everything together.

## Supported Keybindings

Standard Emacs-style keybindings, matching readline/linenoise defaults:

| Key / Sequence     | Bytes            | Action                                           |
| ------------------ | ---------------- | ------------------------------------------------ |
| **Printable char** | `0x20`–`0x7E`    | Insert character at cursor                       |
| **Enter**          | `0x0A` or `0x0D` | Accept the line                                  |
| **Backspace**      | `0x7F`           | Delete character before cursor                   |
| **Delete**         | `ESC [ 3 ~`      | Delete character at cursor                       |
| **Left arrow**     | `ESC [ D`        | Move cursor left one character                   |
| **Right arrow**    | `ESC [ C`        | Move cursor right one character                  |
| **Home**           | `ESC [ H`        | Move cursor to beginning of line                 |
| **End**            | `ESC [ F`        | Move cursor to end of line                       |
| **Up arrow**       | `ESC [ A`        | Previous history entry                           |
| **Down arrow**     | `ESC [ B`        | Next history entry                               |
| **Ctrl+A**         | `0x01`           | Move cursor to beginning of line (= Home)        |
| **Ctrl+E**         | `0x05`           | Move cursor to end of line (= End)               |
| **Ctrl+B**         | `0x02`           | Move cursor left (= Left arrow)                  |
| **Ctrl+F**         | `0x06`           | Move cursor right (= Right arrow)                |
| **Ctrl+K**         | `0x0B`           | Kill (delete) from cursor to end of line         |
| **Ctrl+U**         | `0x15`           | Kill from beginning of line to cursor            |
| **Ctrl+W**         | `0x17`           | Delete the word before the cursor                |
| **Ctrl+D**         | `0x04`           | EOF if line is empty; otherwise delete at cursor |
| **Ctrl+L**         | `0x0C`           | Clear screen and redraw the current line         |
| **Ctrl+C**         | `0x03`           | Discard the current line (returns empty `""`)    |

## Module Reference: terminal.mojo

This module handles the low-level conversation with the operating system's
terminal driver. The next two sections give the background needed to read it.

### Background: What Is a Terminal Driver?

When you type in a terminal app (Terminal.app, iTerm2, etc.), your keystrokes
don't go directly to your program. They pass through a component in the OS
kernel called the **terminal driver** (also called the "tty driver" or "line
discipline").

The terminal driver sits between the physical input (keyboard) and your
program's stdin. It can buffer input, echo characters, interpret special keys
(Ctrl+C to kill, Ctrl+Z to suspend), and do newline/carriage-return translation
— all before your program ever sees a byte.

```txt
┌──────────┐     ┌──────────────────┐     ┌──────────────┐
│ Keyboard │ ──> │ Terminal Driver  │ ──> │ Your Program │
│          │     │ (in the kernel)  │     │ (stdin)      │
└──────────┘     └──────────────────┘     └──────────────┘
                  ↑ configurable via
                  termios settings
```

The terminal driver's behavior is controlled by a data structure called
**termios** (short for "terminal I/O settings"). By reading and writing this
structure, we can change how the driver processes input and output.

### Background: Cooked Mode vs Raw Mode

The terminal driver has two main modes:

**Cooked mode** (also called "canonical mode") is the default:

- Input is **line-buffered** — your program only receives input after the user
  presses Enter. Until then, the driver holds the characters in an internal
  buffer.
- Characters are **echoed** automatically — when you type `a`, the driver sends
  `a` to the screen before your program even knows about it.
- **Special keys are interpreted** — Ctrl+C sends SIGINT (kills your program),
  Ctrl+Z sends SIGTSTP (suspends it), Ctrl+D signals end-of-file.

This is fine for simple programs that just read whole lines. But for a line
editor, we need **raw mode**:

- Input is **unbuffered** — every single keypress is delivered to our program
  immediately, without waiting for Enter.
- **No automatic echo** — we control exactly what appears on screen.
- **No signal interpretation** — Ctrl+C is just byte `0x03` that we handle
  ourselves (we use it to discard the current line, not to kill the program).

Limo enters raw mode at the start of `read_line()` and restores the original
settings when it returns. If something goes wrong, the cleanup still runs
(best-effort, non-raising) so the user's terminal doesn't get stuck in raw mode.

### Constants — File Descriptors

```mojo
comptime STDIN_FILENO:  Int32 = 0   # Standard input  (keyboard)
comptime STDOUT_FILENO: Int32 = 1   # Standard output  (normal output)
comptime STDERR_FILENO: Int32 = 2   # Standard error   (error/diagnostic output)
```

On Unix systems, every running program is born with three open I/O channels,
identified by integer numbers called **file descriptors**:

- **0 (stdin):** Where keyboard input comes from.
- **1 (stdout):** Where normal output goes (e.g., calculation results).
- **2 (stderr):** Where error messages and diagnostics go.

Limo writes the prompt to stderr and calculation results to stdout. This way, if
you pipe the output (`decimo "1+2" > result.txt`), only the answer goes to the
file, not the prompt.

```mojo
comptime TCSAFLUSH: Int32 = 2
```

When changing terminal settings, `TCSAFLUSH` tells the OS: "Apply the new
settings AND throw away any unread input still sitting in the buffer." This
prevents leftover typed characters from leaking through when we switch modes.

### Constants — Terminal Flags

The terminal driver's behavior is controlled by four groups of **bit flags** —
each flag is a single on/off switch represented as a bit in an integer. We use
bitwise AND (`&`) to turn flags off and bitwise OR (`|`) to turn them on.

**Input flags** (`c_iflag`) — control how incoming bytes are processed:

| Flag     | Limo turns it... | What it does when ON                                        |
| -------- | ---------------- | ----------------------------------------------------------- |
| `IGNBRK` | OFF              | Ignore the BREAK condition (serial line signal)             |
| `BRKINT` | OFF              | Send SIGINT on BREAK condition                              |
| `PARMRK` | OFF              | Mark parity/framing errors in input stream                  |
| `ISTRIP` | OFF              | Strip the 8th bit (reduce characters to 7-bit ASCII)        |
| `INLCR`  | OFF              | Translate newline (`\n`) to carriage return (`\r`) on input |
| `IGNCR`  | OFF              | Ignore carriage return on input                             |
| `ICRNL`  | OFF              | Translate carriage return to newline on input               |
| `IXON`   | OFF              | Enable Ctrl+S/Ctrl+Q software flow control                  |

**Output flags** (`c_oflag`):

| Flag    | Limo turns it... | What it does when ON                                |
| ------- | ---------------- | --------------------------------------------------- |
| `OPOST` | OFF              | Enable output post-processing (e.g., `\n` → `\r\n`) |

**Control flags** (`c_cflag`) — serial port settings (mostly historical):

| Flag     | Limo sets it to... | What it does                                        |
| -------- | ------------------ | --------------------------------------------------- |
| `CSIZE`  | Cleared            | Bit mask for character size (5/6/7/8 bits per byte) |
| `CS8`    | ON                 | Set character size to 8 bits (full byte)            |
| `PARENB` | OFF                | Disable parity checking                             |

**Local flags** (`c_lflag`) — the most important group for raw mode:

| Flag     | Limo turns it... | What it does when ON                                    |
| -------- | ---------------- | ------------------------------------------------------- |
| `ECHO`   | OFF              | Echo typed characters back to screen automatically      |
| `ECHONL` | OFF              | Echo newline even if ECHO is off                        |
| `ICANON` | OFF              | Enable canonical (line-buffered) mode                   |
| `ISIG`   | OFF              | Enable signal generation (Ctrl+C → SIGINT, etc.)        |
| `IEXTEN` | OFF              | Enable extended input processing (Ctrl+V literal input) |

When `make_raw()` turns all of these off, we get raw mode: every keypress
arrives immediately, nothing is echoed, and no signals are generated.

### Constants — Control Character Indices

```mojo
comptime VMIN:  Int = 16   # Index into c_cc[] array
comptime VTIME: Int = 17   # Index into c_cc[] array
```

The termios struct contains an array called `c_cc[]` (control characters) with
20 entries. Each entry configures a different aspect of terminal behavior. The
two we care about:

- **VMIN = 1** means "a read() call should return after receiving at least 1
  byte."
- **VTIME = 0** means "no timeout — wait indefinitely for that byte."

Together, these give us **blocking single-byte reads**: the program waits until
the user presses a key, then immediately gets that one byte.

### Struct: TermIOS

`TermIOS` is a Mojo wrapper for the C `struct termios`. Since Mojo can't
directly use C structs, we store the raw bytes in a `List[UInt8]` and provide
getter/setter methods to read and write the individual fields.

On **macOS arm64**, the C `struct termios` is exactly **72 bytes** laid out as:

| Byte Offset | Size     | C Field Name | Limo Accessor                             | Purpose                                         |
| ----------- | -------- | ------------ | ----------------------------------------- | ----------------------------------------------- |
| 0           | 8 bytes  | `c_iflag`    | `get_iflag()`/`set_iflag()`               | Input flags (how incoming bytes are processed)  |
| 8           | 8 bytes  | `c_oflag`    | `get_oflag()`/`set_oflag()`               | Output flags (how outgoing bytes are processed) |
| 16          | 8 bytes  | `c_cflag`    | `get_cflag()`/`set_cflag()`               | Control flags (serial port settings)            |
| 24          | 8 bytes  | `c_lflag`    | `get_lflag()`/`set_lflag()`               | Local flags (echo, canonical mode, signals)     |
| 32          | 20 bytes | `c_cc[20]`   | `get_control_char()`/`set_control_char()` | Control characters array                        |
| 52          | 4 bytes  | *(padding)*  | *(not accessed)*                          | Alignment padding                               |
| 56          | 8 bytes  | `c_ispeed`   | *(not accessed)*                          | Input baud rate                                 |
| 64          | 8 bytes  | `c_ospeed`   | *(not accessed)*                          | Output baud rate                                |

**Key methods:**

- **`make_raw()`** — Flips all the right bits to enter raw mode. This is
  equivalent to the C function `cfmakeraw()`. It turns off echo, canonical mode,
  signal generation, input/output processing, enables 8-bit characters, and sets
  VMIN=1, VTIME=0 for blocking single-byte reads.
- **`copy()`** — Deep-copies the entire 72-byte settings buffer. We need this
  because we save the *original* settings before modifying a copy for raw mode.

**Internal helpers** (prefixed with `_`, not part of the public API):

- `_read_u64(offset)` — Reads 8 bytes at a byte offset as a `UInt64`. Used
  internally by the flag getters.
- `_write_u64(offset, value)` — Writes a `UInt64` at a byte offset. Used
  internally by the flag setters.

### FFI Functions — Talking to the OS

To read and write terminal settings, we need to call C library functions from
Mojo. This is done via Mojo's `external_call` mechanism (Foreign Function
Interface / FFI), which lets you call any C function by name.

The private FFI functions in terminal.mojo (all prefixed with `_`):

| Function                                            | What it does                                                                                                                                     |
| --------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------ |
| `_tcgetattr(file_descriptor, settings)`             | Asks the OS: "What are the current terminal settings for this file descriptor?" Fills in the `settings` struct.                                  |
| `_tcsetattr(file_descriptor, action, settings)`     | Tells the OS: "Apply these new terminal settings to this file descriptor." Raises on failure.                                                    |
| `_tcsetattr_raw(file_descriptor, action, settings)` | Same as `_tcsetattr` but returns the error code as an integer instead of raising. Needed for cleanup paths where exceptions can't be propagated. |
| `_isatty(file_descriptor)`                          | Asks the OS: "Is this file descriptor connected to a real terminal?" Returns `False` if stdin is a pipe (e.g., `echo "1+2" \| decimo`).          |

### FFI Signature Convention (Alignment with argmojo)

Limo shares two POSIX C functions with argmojo via `external_call`:
`tcgetattr` and `tcsetattr`. The **argmojo** package
([forfudan/argmojo](https://github.com/forfudan/argmojo)) also calls the same
three C functions in its `utils.mojo` for interactive password input.

In Mojo, `external_call["func_name", ReturnType, ArgType1, ArgType2, ...]`
generates an LLVM IR declaration for the named C function. When two Mojo
packages both call `external_call` with the **same C function name**, LLVM
merges them into a single declaration — so the type lists **must** be identical.
If package A declares `tcgetattr(Int32, UnsafePointer) -> Int32` and package B
declares `tcgetattr(Int, Int) -> Int`, LLVM sees two conflicting declarations
for the same global symbol `@tcgetattr` and refuses to compile. Mojo namespaces
are irrelevant here — `external_call` bypasses them and produces a flat C-level
symbol.

The solution is simple: **use the same signature as argmojo**. Both libraries
pass all integer and pointer arguments as `Int` (which is `i64` on 64-bit
platforms). Pointers are cast to `Int` via `Int(ptr)`. This is the convention
adopted by argmojo and followed by limo:

| C function  | Mojo `external_call` signature (shared by argmojo and limo)                                       |
| ----------- | ------------------------------------------------------------------------------------------------- |
| `tcgetattr` | `external_call["tcgetattr", Int, Int, Int](fd, ptr)`                                              |
| `tcsetattr` | `external_call["tcsetattr", Int, Int, Int, Int](fd, act, ptr)`                                    |
| `read`      | `external_call["read", Int](fd, buf, count)` — return type only, since the stdlib declares `read` |

Because LLVM sees identical declarations from both packages, the merge is clean
and there is no conflict.

> **Note for library authors:** If you write a Mojo package that calls
> `tcgetattr` or `tcsetattr` via `external_call`, use the `Int`-only signatures
> above to stay compatible with both argmojo and limo. For `read`, `write` and
> `isatty` the Mojo standard library already declares the symbol, so give the
> return type only (`isatty` takes `Int32`) and let the arguments be inferred.

### Raw Mode Control Functions

These are the public functions that `line_editor.mojo` uses to manage raw mode:

**`enable_raw_mode() raises -> TermIOS`**

The main entry point for raw mode. The steps are:

1. Checks that stdin is actually a terminal (not a pipe or file).
2. Creates an empty `TermIOS` and asks the OS to fill it with the current
   settings.
3. Makes a copy of those original settings.
4. Calls `make_raw()` on the copy to configure it for raw mode.
5. Applies the raw settings to the terminal.
6. Returns the *original* settings (so they can be restored later).

**`disable_raw_mode(original_settings) raises`**

Restores the terminal to the given settings. Called when everything went well
and we can propagate errors normally.

**`disable_raw_mode_nothrow(original_settings)`**

Same as above, but doesn't raise on error — it silently ignores failures. This
is used at the end of `read_line()` where we *must* restore the terminal even if
something else went wrong. (If the terminal gets stuck in raw mode, the user's
shell becomes unusable — no echo, no line buffering, no Ctrl+C.)

### I/O Primitive Functions

**`read_byte() raises -> UInt8`**

Reads one byte from stdin using the POSIX `read(2)` syscall. In raw mode, this
returns immediately after one keypress. The byte value tells you what was
pressed — for example:

- `65` = the letter `A`
- `27` = the ESC key (start of an escape sequence)
- `13` = Enter (carriage return)
- `127` = Backspace
- `3` = Ctrl+C
- `4` = Ctrl+D

Returns `UInt8`. Raises on EOF (e.g., when stdin is closed).

**`write_stdout(data: String)`**

Writes a string to stdout (file descriptor 1) using the POSIX `write()` system
call. Best-effort — errors are silently ignored. Used for buffer content and
ANSI escape sequences.

**`write_stderr(data: String)`**

Same but writes to stderr (file descriptor 2). Used for the prompt, so that
stdout remains clean for piping results.

### ANSI Escape Helper Functions

These write special byte sequences that the terminal interprets as **commands**
rather than visible characters. All modern terminals (Terminal.app, iTerm2,
VS Code terminal, etc.) understand these "VT100 escape codes."

An escape sequence always starts with `ESC [` (bytes `0x1B 0x5B`), sometimes
called "CSI" (Control Sequence Introducer). What follows determines the command.

| Function                   | Escape Sequence Written | What It Does                                  |
| -------------------------- | ----------------------- | --------------------------------------------- |
| `cursor_move_left(count)`  | `ESC[{count}D`          | Moves the cursor left by `count` columns      |
| `cursor_move_right(count)` | `ESC[{count}C`          | Moves the cursor right by `count` columns     |
| `clear_line_from_cursor()` | `ESC[K`                 | Erases from cursor position to end of line    |
| `clear_screen()`           | `ESC[2J` + `ESC[H`      | Clears the entire screen, cursor to top-left  |
| `move_to_column_zero()`    | `\r` (carriage return)  | Moves cursor to the start of the current line |

These are used by the line editor to update what the user sees after each
keystroke.

## Module Reference: line_editor.mojo

This module contains the user-facing `LineEditor` struct. It reads keystrokes
one by one, classifies each into an **action**, and dispatches to the
appropriate handler.

### Action Constants

Each raw keypress (or multi-byte escape sequence) is first classified into one
of 18 named actions. This separates "what key was pressed" from "what should
happen" — for example, both the Left arrow key (ESC `[` `D`) and Ctrl+B (`0x02`)
map to the same `_ACT_LEFT` action.

```txt
_ACT_INSERT          = 0    # Printable character — insert into buffer
_ACT_ACCEPT          = 1    # Enter — accept the line
_ACT_EOF             = 2    # Ctrl-D on empty line — end of file
_ACT_CANCEL          = 3    # Ctrl-C — discard line
_ACT_LEFT            = 4    # Move cursor left
_ACT_RIGHT           = 5    # Move cursor right
_ACT_HOME            = 6    # Move cursor to start of line
_ACT_END             = 7    # Move cursor to end of line
_ACT_BACKSPACE       = 8    # Delete character before cursor
_ACT_DELETE          = 9    # Delete character at cursor
_ACT_DELETE_OR_EOF   = 10   # Ctrl-D: delete if buffer has text, EOF if empty
_ACT_KILL_TO_END     = 11   # Ctrl-K: delete from cursor to end
_ACT_KILL_TO_START   = 12   # Ctrl-U: delete from start to cursor
_ACT_KILL_WORD_BACK  = 13   # Ctrl-W: delete previous word
_ACT_HISTORY_UP      = 14   # Up arrow: previous history entry
_ACT_HISTORY_DOWN    = 15   # Down arrow: next history entry
_ACT_CLEAR_SCREEN    = 16   # Ctrl-L: clear screen and redraw
_ACT_IGNORE          = 17   # Unrecognized key — do nothing
```

These are module-private (`_`-prefixed) compile-time constants, not part of the
public API.

### Struct: LineEditor

The only public symbol in the limo package. It holds:

- `_history: List[String]` — All previously entered lines, oldest first.
- `_max_history: Int` — Maximum number of history entries (default 1000). When
  the cap is exceeded, the oldest entry is evicted.

**Public methods:**

| Method                                          | Description                                                                |
| ----------------------------------------------- | -------------------------------------------------------------------------- |
| `__init__(max_history: Int = 1000)`             | Creates a new editor with configurable history cap.                        |
| `read_line(prompt: String) -> Optional[String]` | Displays prompt, reads a line with editing support. Returns `None` on EOF. |
| `add_history(line: String)`                     | Manually adds a line to history (e.g., loaded from file).                  |
| `clear_history()`                               | Removes all history entries.                                               |
| `get_history() -> List[String]`                 | Returns a copy of the history buffer.                                      |
| `set_max_history(max: Int)`                     | Changes the history cap; evicts oldest entries if needed.                  |

### The Main Loop: read_line()

This is the core function. The flow is:

1. **Enter raw mode** — calls `enable_raw_mode()`, saves the original terminal
   settings in `original_settings`.
2. **Initialize state:**
   - `buffer: List[UInt8]` — an empty byte buffer for the line being edited.
   - `cursor: Int = 0` — the cursor position (byte offset into the buffer).
   - `history_index: Int = -1` — `-1` means "not browsing history right now."
   - `saved_line: String = ""` — saves the in-progress line when the user
     starts browsing history (so pressing Down all the way restores it).
3. **Draw the initial prompt** — writes `decimo>` in bold green to stderr.
4. **Main loop — repeat until done:**
   1. Call `read_byte()` to get one byte from the keyboard.
   2. **Classify** the byte into an action (see the action table above). If the
      byte is ESC (`0x1B`), read additional bytes to identify the full escape
      sequence (arrow keys, Home, End, Delete).
   3. **Dispatch** the action — call the appropriate handler function.
   4. After most edits, call `_redraw()` to update what the user sees.
5. **Restore terminal** — calls `disable_raw_mode_nothrow(original_settings)` to
   put the terminal back to normal, even if an error occurred during editing.
6. **Return** the result — a `String` on Enter/Ctrl+C, or `None` on EOF.

**What each action does:**

| Action                     | Behavior                                                                                               |
| -------------------------- | ------------------------------------------------------------------------------------------------------ |
| Accept (Enter)             | Converts the buffer to a `String`, adds it to history (unless empty or duplicate), returns the string. |
| Cancel (Ctrl+C)            | Returns an empty string `""`. The REPL treats this as "discard and re-prompt."                         |
| EOF (Ctrl+D on empty)      | Returns `None`. The REPL treats this as "exit."                                                        |
| Delete/Ctrl+D on non-empty | Deletes the character at the cursor position.                                                          |
| Insert                     | Inserts the typed character into the buffer at the cursor position and advances the cursor.            |
| Backspace                  | Removes the character before the cursor and moves the cursor back.                                     |
| Left / Right               | Moves the cursor one position, with bounds checking.                                                   |
| Home / End                 | Jumps the cursor to position 0 or to the end of the buffer.                                            |
| Kill to end (Ctrl+K)       | Truncates the buffer at the cursor — everything after the cursor is deleted.                           |
| Kill to start (Ctrl+U)     | Deletes everything from position 0 up to the cursor.                                                   |
| Kill word (Ctrl+W)         | Deletes backward: first skips spaces, then skips non-spaces. This removes one "word."                  |
| History Up / Down          | Navigates through previously entered lines (see history section below).                                |
| Clear screen (Ctrl+L)      | Clears the entire terminal screen, then redraws the prompt and current buffer.                         |

### Escape Sequence Parsing

When you press an arrow key, the terminal doesn't send a single byte — it sends
a **multi-byte escape sequence**. For example:

| Key pressed | Bytes sent by the terminal | Hex values    |
| ----------- | -------------------------- | ------------- |
| Up arrow    | `ESC [ A`                  | `1B 5B 41`    |
| Down arrow  | `ESC [ B`                  | `1B 5B 42`    |
| Right arrow | `ESC [ C`                  | `1B 5B 43`    |
| Left arrow  | `ESC [ D`                  | `1B 5B 44`    |
| Home        | `ESC [ H`                  | `1B 5B 48`    |
| End         | `ESC [ F`                  | `1B 5B 46`    |
| Delete      | `ESC [ 3 ~`                | `1B 5B 33 7E` |

The `_parse_escape()` method handles this: after the main loop reads the initial
ESC byte (`0x1B`), it calls `_parse_escape()` which reads one or two more bytes
to identify the full sequence. It returns the appropriate action constant
(`_ACT_LEFT`, `_ACT_HISTORY_UP`, etc.) or `_ACT_IGNORE` for unrecognized
sequences.

### Screen Redraw Algorithm

After any buffer modification (insert, delete, history navigation), we need to
update what the user sees. The `_redraw()` method does this with a 5-step
algorithm (same approach as linenoise):

```txt
Step 1: Write \r (carriage return) — move cursor to column 0
Step 2: Write the prompt (bold green, to stderr)
Step 3: Write the entire buffer contents (to stdout)
Step 4: Write ESC[K — clear any leftover characters from a previous longer line
Step 5: Move cursor back to the correct position within the buffer
```

It redraws the entire line every time, which is fine for single-line input
where the buffer is rarely more than a few hundred characters.

### Buffer Manipulation Functions

These are module-level (non-method) helper functions that operate on the byte
buffer. They're kept separate from the `LineEditor` struct to keep the dispatch
logic clean.

| Function                                 | What it does                                                                                                                                                                                          |
| ---------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_buffer_to_string(buffer)`              | Converts `List[UInt8]` to `String` by copying the bytes and interpreting them as UTF-8.                                                                                                               |
| `_action_insert(buffer, cursor, byte)`   | Inserts a byte at the cursor position. If cursor is at the end, simply appends (fast path). Otherwise shifts all bytes after the cursor right by one, then writes the new byte. Advances cursor by 1. |
| `_action_backspace(buffer, cursor)`      | Removes the byte at `cursor - 1` by shifting all subsequent bytes left by one. Decrements cursor by 1.                                                                                                |
| `_action_delete(buffer, cursor)`         | Removes the byte at `cursor` by shifting all subsequent bytes left by one. Cursor stays in place.                                                                                                     |
| `_action_kill_to_start(buffer, cursor)`  | Copies bytes from `[cursor, end)` to `[0, ...)`, then truncates the buffer. Sets cursor to 0.                                                                                                         |
| `_action_kill_word_back(buffer, cursor)` | Scans backward from cursor: first skips spaces (byte `0x20`), then skips non-spaces. Removes the range of bytes found. Useful for deleting a word at a time.                                          |

### History Navigation Functions

Limo maintains a simple list of previously entered lines. When the user presses
Up/Down arrow:

| Function                                        | What it does                                                                                                                                                                                                |
| ----------------------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `_action_history_up(...)`                       | **First press:** saves the current in-progress line into `saved_line`, then loads the most recent history entry into the buffer. **Subsequent presses:** moves to older entries. Stops at the oldest entry. |
| `_action_history_down(...)`                     | Moves to newer history entries. When the user goes past the newest entry, restores the `saved_line` (whatever they were typing before pressing Up).                                                         |
| `_set_buffer_from_string(buffer, cursor, text)` | Replaces the entire buffer with the bytes of a string and moves the cursor to the end. Used when loading a history entry.                                                                                   |

**History behavior details:**

- Non-empty lines are automatically added to history when Enter is pressed.
- Consecutive duplicate lines are suppressed (typing `1+2` three times in a row
  only stores it once).
- History is capped at `max_history` entries (default 1000). When the cap is
  exceeded, the oldest entry is removed.
- History is currently in-memory only — it is lost when the REPL exits.
  File-based history persistence is planned for Phase 2.

## Integration with Decimo REPL

The change to `src/cli/calculator/repl.mojo` is minimal. Before limo:

```mojo
# Old approach — no editing, no history
from .io import read_line

def run_repl(...):
    while True:
        write_prompt("decimo> ")
        var line = read_line()
        ...
```

After limo:

```mojo
# New approach — full line editing and history
from limo import LineEditor

def run_repl(...):
    var editor = LineEditor()
    while True:
        var line = editor.read_line("decimo> ")
        if not line:
            break  # EOF (Ctrl-D)
        ...
```

The old `read_line()` in `io.mojo` still exists for pipe/file mode (where stdin
is not a terminal and raw mode is not used).

## Terminology Reference

Limo intentionally uses descriptive names instead of the traditional C/termios
abbreviations. If you're reading termios documentation or C source code
alongside limo, this table maps between the two naming conventions:

| C / termios term   | Limo name                                 | What it means                                                                                                                                                                                      |
| ------------------ | ----------------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `fd`               | `file_descriptor`                         | An integer ID that the operating system uses to track an open I/O channel (file, terminal, pipe, socket, etc.). stdin=0, stdout=1, stderr=2.                                                       |
| `ios` or `termios` | `settings`                                | The `struct termios` data structure that holds all terminal driver configuration (flags, control characters, baud rates).                                                                          |
| `rc`               | `return_code`                             | The integer returned by a C system call to indicate success (0) or failure (non-zero).                                                                                                             |
| `c_cc`             | `control_char`                            | An entry in the control characters array (`c_cc[]`) of the termios struct. Each entry configures a different terminal behavior (e.g., VMIN, VTIME). The "cc" stands for "control characters."      |
| `c_iflag`          | input flags                               | Bit flags controlling how incoming bytes are processed (newline translation, flow control, etc.).                                                                                                  |
| `c_oflag`          | output flags                              | Bit flags controlling how outgoing bytes are processed (post-processing, newline mapping).                                                                                                         |
| `c_cflag`          | control flags                             | Bit flags for serial port control (character size, parity). Mostly historical.                                                                                                                     |
| `c_lflag`          | local flags                               | Bit flags for local terminal behavior (echo, canonical mode, signal generation).                                                                                                                   |
| `TCSAFLUSH`        | *(kept as-is)*                            | A constant passed to `tcsetattr()` meaning "apply settings after draining output and flushing (discarding) unread input."                                                                          |
| `VMIN`             | *(kept as-is)*                            | Index into `c_cc[]`. Sets the minimum number of bytes for a read to succeed.                                                                                                                       |
| `VTIME`            | *(kept as-is)*                            | Index into `c_cc[]`. Sets the read timeout in tenths of a second.                                                                                                                                  |
| `cfmakeraw`        | `make_raw()`                              | A C function (and our method) that configures a termios struct for raw mode.                                                                                                                       |
| `isatty`           | *(kept as-is)*                            | A C function that checks whether a file descriptor refers to a terminal device.                                                                                                                    |
| `ioctl`            | *(kept as-is)*                            | A general-purpose system call for device-specific control operations. Not used by limo (which calls `tcgetattr`/`tcsetattr` directly), but relevant background when reading termios documentation. |
| `TIOCGETA`         | *(kept as-is)*                            | An ioctl request code meaning "get terminal attributes" (macOS-specific, equivalent to `tcgetattr`). Not used by limo.                                                                             |
| `TIOCSETAF`        | *(kept as-is)*                            | An ioctl request code meaning "set terminal attributes with flush" (macOS-specific, equivalent to `tcsetattr` with `TCSAFLUSH`). Not used by limo.                                                 |
| `buf`              | `buffer`                                  | The `List[UInt8]` byte array holding the line currently being edited.                                                                                                                              |
| `orig`             | `original_cursor`                         | The saved cursor position before a multi-character deletion (e.g., kill-word-back).                                                                                                                |
| `hist_idx`         | `history_index`                           | The current position in the history list during Up/Down navigation. `-1` means "not browsing history."                                                                                             |
| `b1`, `b2`, `b3`   | `first_byte`, `second_byte`, `third_byte` | The successive bytes of a multi-byte escape sequence (e.g., arrow keys send 3 bytes).                                                                                                              |
| `CSI`              | *(explained inline)*                      | Control Sequence Introducer — the two-byte prefix `ESC [` (`0x1B 0x5B`) that starts most ANSI escape sequences.                                                                                    |

## Phase Roadmap

Limo is developed in phases. See `docs/plans/line_editor.md` for the full task
list with status checkboxes.

**Phase 1 (current) — Core Line Editor:**
All essential editing features are implemented: arrow keys, Home/End, Backspace,
Delete, Ctrl shortcuts, history navigation, and screen redraw. The decimo REPL
has full readline-style editing.

**Phase 2 (planned) — Polish:**
History persistence (save/load to file), word-level movement (Alt+B/Alt+F),
transpose characters (Ctrl+T), UTF-8 multi-byte input, CJK display width,
terminal resize handling.

**Phase 3 (future) — Advanced Features:**
Reverse history search (Ctrl+R), tab completion (callback-based), syntax
highlighting, hints/suggestions, customizable key bindings.
