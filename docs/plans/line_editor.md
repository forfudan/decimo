# Limo — Line Editor for Mojo 🔥

> Date of initial planning: 2026-04-15
> Author: Yuhao Zhu
> Scope: A lightweight, reusable line-editing library for Mojo REPL applications
> Location: `src/cli/limo/` (internal package, parallel to `src/cli/calculator/`)
> Future: Extract to standalone repo `forfudan/limo` for general-purpose use
>
> The name "limo" = **li**ne + **mo**jo.
> Name availability: not taken on PyPI or conda-forge (checked 2025-07-15).

## 1. Motivation

The decimo REPL (`src/cli/calculator/repl.mojo`) currently reads input via a simple `getchar()` loop in cooked/canonical terminal mode. This means:

- **No line editing** — users cannot move the cursor left/right, jump to Home/End, or delete characters mid-line.
- **No history** — pressing up/down does nothing; users must retype previous expressions from scratch.
- **No hotkeys** — Ctrl+A (beginning of line), Ctrl+E (end of line), Ctrl+K (kill to end), Ctrl+U (kill to beginning), Ctrl+W (delete word backward) — none of these work.

These are table-stakes features for any interactive REPL. Every comparable tool — Python, IPython, bc, calc, qalc — provides them, typically via GNU readline or linenoise.

Mojo has no readline binding. Rather than waiting for one, we can implement a lightweight line editor directly using `tcgetattr`/`tcsetattr` FFI to enter raw terminal mode and handle escape sequences ourselves.

### Why a separate package?

The line-editing problem is **completely general** — it has nothing to do with decimal arithmetic. Decoupling it into `limo` provides:

1. **Clean separation of concerns** — the calculator REPL calls `limo.read_line()` instead of managing terminal state directly.
2. **Reusability** — any Mojo CLI tool (argmojo REPL, database client, shell, etc.) can import limo.
3. **Testability** — terminal I/O logic can be tested independently of the calculator.
4. **Future extraction** — when the API stabilizes, move limo to its own repo and release on conda-forge.

### Relationship to Termo

The author previously built a terminal manipulation library at `/Users/ZHU/Programs/termo/`. Termo is a full terminal control library (raw mode, screen control, input parsing, Unicode width) designed for building terminal UI applications like text editors. Limo is **lighter and more focused**:

| Aspect         | Termo                                      | Limo                                         |
| -------------- | ------------------------------------------ | -------------------------------------------- |
| **Scope**      | Full terminal control (TUI foundation)     | Line editing only (REPL foundation)          |
| **Modules**    | sys_libc, raw_mode, screen, key, width     | terminal, line_editor (2 modules)            |
| **Screen**     | Full cursor control, colors, scroll, clear | Single-line redraw only                      |
| **Input**      | Full KeyEvent/KeyCode parsing              | Subset: arrows, Home/End, backspace, Ctrl+X  |
| **Output**     | ScreenBuffer for flicker-free full-screen  | Direct write for prompt line                 |
| **Target use** | Text editors, TUI apps                     | REPLs, interactive CLIs                      |
| **Code reuse** | Source of truth for FFI and raw mode       | Borrows FFI bindings and raw mode from termo |

Limo **reuses** termo's Phase 1 code (`sys_libc.mojo` TermIOS struct, raw mode enable/disable, byte reading) but does **not** need termo's screen buffer, full color system, or advanced input parsing. It is a purpose-built subset.

## 2. Cross-Library Comparison: Line Editors

| Feature                        | GNU readline         | linenoise    | rustyline         | prompt_toolkit | Proposed limo           |
| ------------------------------ | -------------------- | ------------ | ----------------- | -------------- | ----------------------- |
| **Language**                   | C                    | C            | Rust              | Python         | Mojo                    |
| **Lines of code**              | ~30,000              | ~1,100       | ~15,000           | ~80,000        | Target: ~2000 (Phase 1) |
| **Dependencies**               | ncurses/termcap      | None         | Several crates    | wcwidth        | None (libc FFI only)    |
| **Raw mode**                   | ✓                    | ✓            | ✓                 | ✓              | ✓                       |
| **Left/Right cursor**          | ✓                    | ✓            | ✓                 | ✓              | ✓                       |
| **Home/End**                   | ✓                    | ✓            | ✓                 | ✓              | ✓                       |
| **Backspace/Delete**           | ✓                    | ✓            | ✓                 | ✓              | ✓                       |
| **Up/Down history**            | ✓                    | ✓            | ✓                 | ✓              | ✓                       |
| **Ctrl+A/E (begin/end)**       | ✓                    | ✓            | ✓                 | ✓              | ✓                       |
| **Ctrl+K/U (kill line)**       | ✓                    | ✓            | ✓                 | ✓              | ✓                       |
| **Ctrl+W (delete word)**       | ✓                    | ✗            | ✓                 | ✓              | ✓                       |
| **Ctrl+R (search history)**    | ✓                    | ✗            | ✓                 | ✓              | Phase 3                 |
| **Ctrl+L (clear screen)**      | ✓                    | ✓            | ✓                 | ✓              | ✓                       |
| **Tab completion**             | ✓ (programmable)     | ✓ (callback) | ✓ (callback)      | ✓ (rich)       | Phase 3 (callback)      |
| **Syntax highlighting**        | ✗                    | ✗            | ✓ (`Highlighter`) | ✓ (rich)       | Phase 3                 |
| **Hints/suggestions**          | ✗                    | ✓ (callback) | ✓ (Hinter trait)  | ✓              | Phase 3                 |
| **Multi-line editing**         | ✗                    | ✗            | ✓                 | ✓              | ✗ (not planned)         |
| **History persistence (file)** | ✓ (`~/.history`)     | ✓            | ✓                 | ✓              | Phase 2                 |
| **Kill ring (yank/paste)**     | ✓ (full Emacs-style) | ✗            | ✓                 | ✓              | ✗ (not planned)         |
| **Unicode/CJK width**          | ✓ (via locale)       | ✗            | ✓                 | ✓ (wcwidth)    | Phase 2                 |
| **Customizable key bindings**  | ✓ (.inputrc)         | ✗            | ✓                 | ✓              | Phase 3 (callback)      |
| **Windows support**            | ✗                    | ✗ (fork)     | ✓                 | ✓              | ✗ (macOS/Linux only)    |
| **Platform**                   | POSIX                | POSIX        | Cross-platform    | Cross-platform | macOS arm64 (+ Linux)   |

**Design model:** Limo is closest to **linenoise** — a minimal, single-file, zero-dependency line editor. The key difference is that limo adds Ctrl+W (word delete) and will support history search and tab completion in later phases.

## 3. Architecture

### 3.1 Package Structure

```txt
src/cli/limo/
├── __init__.mojo          # Public API re-exports
├── terminal.mojo          # Raw mode, byte reading, ANSI escape sequences (from termo)
└── line_editor.mojo       # LineEditor struct: editing, history, key dispatch
```

Only **two modules** plus an `__init__.mojo`. This is intentionally minimal.

### 3.2 Module Responsibilities

#### `terminal.mojo` — Terminal Primitives

Adapted from termo's `sys_libc.mojo` + `raw_mode.mojo`. Contains:

- `TermIOS` struct (macOS arm64 termios layout, 72 bytes)
- `enable_raw_mode() -> TermIOS` / `disable_raw_mode(TermIOS)`
- `RawModeGuard` — RAII struct for automatic cleanup
- `read_byte() -> UInt8` — blocking single-byte read from stdin
- `write_to_fd(fd, data)` — write bytes to a file descriptor
- Terminal flag constants (ICANON, ECHO, etc.)
- ANSI escape helpers for single-line use:
  - `cursor_move_left(n)`, `cursor_move_right(n)`
  - `clear_line_from_cursor()`
  - `cursor_move_to_column(col)`

This module does NOT include: ScreenBuffer, full color system, scroll control, alternate screen — those belong in termo.

#### `line_editor.mojo` — The Line Editor

The core user-facing struct. Manages:

- A character buffer (`List[UInt8]`) for the current line
- A cursor position (byte offset into the buffer)
- A history buffer (`List[String]`) with navigation index
- Key dispatch: raw bytes → action (edit, move, history, accept, cancel)

```txt
┌──────────────────────────────────────────────────────────┐
│  decimo>  1 + sqrt(2█) * pi                              │
│           ↑           ↑    ↑                             │
│      prompt_len    cursor  end                           │
│                                                          │
│  Buffer: "1 + sqrt(2) * pi"                              │
│  Cursor: 10 (after '2')                                  │
│  History: ["1+2", "sqrt(2)", "pi * e"]                   │
│  History index: -1 (current line, not navigating)        │
└──────────────────────────────────────────────────────────┘
```

### 3.3 Key Mapping

Standard Emacs-style keybindings (same as readline/linenoise defaults):

| Key / Sequence     | Bytes           | Action                        | Phase |
| ------------------ | --------------- | ----------------------------- | ----- |
| **Printable char** | 0x20–0x7E       | Insert at cursor              | 1     |
| **Enter**          | 0x0A or 0x0D    | Accept line                   | 1     |
| **Backspace**      | 0x7F            | Delete char before cursor     | 1     |
| **Delete**         | ESC `[` `3` `~` | Delete char at cursor         | 1     |
| **Left arrow**     | ESC `[` `D`     | Move cursor left              | 1     |
| **Right arrow**    | ESC `[` `C`     | Move cursor right             | 1     |
| **Home**           | ESC `[` `H`     | Move cursor to beginning      | 1     |
| **End**            | ESC `[` `F`     | Move cursor to end            | 1     |
| **Up arrow**       | ESC `[` `A`     | Previous history entry        | 1     |
| **Down arrow**     | ESC `[` `B`     | Next history entry            | 1     |
| **Ctrl+A**         | 0x01            | Move cursor to beginning      | 1     |
| **Ctrl+E**         | 0x05            | Move cursor to end            | 1     |
| **Ctrl+B**         | 0x02            | Move cursor left (= Left)     | 1     |
| **Ctrl+F**         | 0x06            | Move cursor right (= Right)   | 1     |
| **Ctrl+K**         | 0x0B            | Kill from cursor to end       | 1     |
| **Ctrl+U**         | 0x15            | Kill from beginning to cursor | 1     |
| **Ctrl+W**         | 0x17            | Delete word backward          | 1     |
| **Ctrl+D**         | 0x04            | EOF (if line empty) or delete | 1     |
| **Ctrl+L**         | 0x0C            | Clear screen and redraw       | 1     |
| **Ctrl+C**         | 0x03            | Discard line (print newline)  | 1     |
| **Ctrl+T**         | 0x14            | Transpose chars               | 2     |
| **Ctrl+R**         | 0x12            | Reverse history search        | 3     |
| **Tab**            | 0x09            | Trigger completion callback   | 3     |
| **Alt+B**          | ESC `b`         | Move word backward            | 2     |
| **Alt+F**          | ESC `f`         | Move word forward             | 2     |
| **Alt+D**          | ESC `d`         | Delete word forward           | 2     |
| **Alt+Backspace**  | ESC 0x7F        | Delete word backward (= C-W)  | 2     |

### 3.4 Public API

```mojo
# === limo public API ===

struct LineEditor(Movable):
    """A readline-style line editor with history support.

    Usage:
        var editor = LineEditor()
        while True:
            var line = editor.read_line("prompt> ")
            if not line:
                break  # EOF
            process(line.value())
    """

    def __init__(out self)
    def __init__(out self, max_history: Int)

    def read_line(mut self, prompt: String) raises -> Optional[String]
        """Display prompt, read a line with editing support.

        Returns the edited line on Enter, or None on EOF (Ctrl-D on empty line).
        Automatically adds non-empty lines to history.
        """

    def add_history(mut self, line: String)
        """Manually add a line to history (e.g., loaded from file)."""

    def clear_history(mut self)
        """Clear all history entries."""

    def get_history(self) -> List[String]
        """Return a copy of the history buffer."""

    def set_max_history(mut self, max: Int)
        """Set maximum number of history entries to retain."""

    # Phase 2 additions:
    def load_history(mut self, path: String) raises
        """Load history from a file (one line per entry)."""

    def save_history(self, path: String) raises
        """Save history to a file."""

    # Phase 3 additions:
    def set_completion_callback(mut self, callback: fn(String, Int) -> List[String])
        """Register a tab-completion callback.
        The callback receives (current_line, cursor_position) and returns
        a list of completion candidates."""
```

### 3.5 Integration with Decimo REPL

Before limo (current):

```mojo
# src/cli/calculator/io.mojo
def read_line() -> Optional[String]:
    # Simple getchar() loop — no editing, no history
    ...

# src/cli/calculator/repl.mojo
def run_repl(...):
    while True:
        write_prompt("decimo> ")
        var line = read_line()
        ...
```

After limo:

```mojo
# src/cli/calculator/repl.mojo
from limo import LineEditor

def run_repl(...):
    var editor = LineEditor()
    while True:
        var line = editor.read_line("decimo> ")
        ...
```

The change to `repl.mojo` is minimal — replace `write_prompt()` + `read_line()` with a single `editor.read_line(prompt)` call. The `io.mojo` file's `read_line()` remains for pipe/file mode (which does not use raw terminal mode).

## 4. Implementation Roadmap

### Phase 1: Core Line Editor (MVP)

The essential features that make the REPL usable. After this phase, the decimo REPL has arrow-key navigation, backspace, delete, home/end, history, and Ctrl shortcuts.

| #    | Task                                                   | Status | Notes                                                                                                                            |
| ---- | ------------------------------------------------------ | :----: | -------------------------------------------------------------------------------------------------------------------------------- |
| 1.1  | Create `src/cli/limo/` package structure               |   ✓    | `__init__.mojo`, `terminal.mojo`, `line_editor.mojo`                                                                             |
| 1.2  | Port `TermIOS` struct from termo                       |   ✓    | macOS arm64 layout (72 bytes); adapt to current Mojo version                                                                     |
| 1.3  | Port `enable_raw_mode` / `disable_raw_mode` from termo |   ✓    | Uses tcgetattr/tcsetattr with argmojo-aligned `Int` signatures                                                                   |
| 1.4  | Port `RawModeGuard` (RAII cleanup) from termo          |   —    | Skipped: restore raw mode manually via explicit `disable_raw_mode()` cleanup on all exit/error paths, not `RawModeGuard.__del__` |
| 1.5  | Implement `read_byte()` (blocking, stdin)              |   ✓    | Uses `read(2)` with argmojo-aligned `Int` signatures                                                                             |
| 1.6  | Implement escape sequence detection                    |   ✓    | ESC `[` prefix → parse arrow/Home/End/Delete sequences                                                                           |
| 1.7  | Implement ANSI cursor helpers                          |   ✓    | `cursor_move_left`, `cursor_move_right`, `clear_line_from_cursor`                                                                |
| 1.8  | Implement `LineEditor` struct with buffer + cursor     |   ✓    | `List[UInt8]` buffer, `Int` cursor pos, `Int` prompt display width                                                               |
| 1.9  | Character insertion at cursor position                 |   ✓    | Insert byte(s), advance cursor, redraw from cursor to end                                                                        |
| 1.10 | Backspace and Delete                                   |   ✓    | Remove byte at/before cursor, redraw                                                                                             |
| 1.11 | Left/Right arrow cursor movement                       |   ✓    | Bounds checking, ANSI cursor move                                                                                                |
| 1.12 | Home/End (and Ctrl+A/Ctrl+E)                           |   ✓    | Jump to column 0 or end of buffer                                                                                                |
| 1.13 | Enter (accept line) and Ctrl+C (discard)               |   ✓    | Return buffer as String; add to history if non-empty                                                                             |
| 1.14 | Ctrl+D (EOF on empty line, delete otherwise)           |   ✓    | Match readline behavior                                                                                                          |
| 1.15 | Ctrl+K (kill to end) and Ctrl+U (kill to beginning)    |   ✓    | Truncate buffer; redraw                                                                                                          |
| 1.16 | Ctrl+W (delete word backward)                          |   ✓    | Delete backward to previous whitespace boundary                                                                                  |
| 1.17 | Ctrl+L (clear screen and redraw prompt + line)         |   ✓    | Write ESC `[` `2J` ESC `[` `H`, then redraw                                                                                      |
| 1.18 | History buffer (`List[String]`, configurable max size) |   ✓    | FIFO with eviction; default max 1000 entries                                                                                     |
| 1.19 | Up/Down arrow history navigation                       |   ✓    | Save current line, navigate history, restore on return to bottom                                                                 |
| 1.20 | Line redraw function                                   |   ✓    | Clear line → write prompt → write buffer → position cursor                                                                       |
| 1.21 | Integrate into decimo REPL (`repl.mojo`)               |   ✓    | Replace `write_prompt` + `read_line` with `editor.read_line`                                                                     |
| 1.22 | Unit tests for `LineEditor`                            |   ✗    | Buffer manipulation, cursor movement, history navigation                                                                         |
| 1.23 | Manual integration testing                             |   ✗    | Run `decimo` REPL and verify all keybindings work                                                                                |

**Milestone:** `decimo` REPL supports full arrow-key editing and up/down history.

### Phase 2: Polish

Quality-of-life improvements and robustness.

| #    | Task                                    | Status | Notes                                                   |
| ---- | --------------------------------------- | :----: | ------------------------------------------------------- |
| 2.1  | History persistence (save/load to file) |   ✗    | `~/.decimo_history` or configurable path                |
| 2.2  | Duplicate history suppression           |   ✓    | Included in Phase 1: consecutive duplicate suppression  |
| 2.3  | Ctrl+T (transpose characters)           |   ✗    | Swap char before cursor with char at cursor             |
| 2.4  | Alt+B / Alt+F (word movement)           |   ✗    | Move cursor by word boundaries                          |
| 2.5  | Alt+D (delete word forward)             |   ✗    | Delete from cursor to next word boundary                |
| 2.6  | Alt+Backspace (delete word backward)    |   ✗    | Same as Ctrl+W                                          |
| 2.7  | CJK/Unicode display width handling      |   ✗    | Wide chars occupy 2 columns; affects cursor positioning |
| 2.8  | UTF-8 multi-byte input                  |   ✗    | Read continuation bytes for non-ASCII input             |
| 2.9  | Handle terminal resize during editing   |   ✗    | SIGWINCH → re-query terminal width → redraw             |
| 2.10 | History prefix search                   |   ✗    | Type prefix, press up → find matching history entry     |

**Milestone:** Robust line editing with word operations, Unicode support, and persistent history.

### Phase 3: Advanced Features (Future)

Features that would make limo competitive as a standalone library.

| #   | Task                                        | Status | Notes                                                              |
| --- | ------------------------------------------- | :----: | ------------------------------------------------------------------ |
| 3.1 | Ctrl+R (reverse incremental history search) |   ✗    | Interactive search through history; display matches                |
| 3.2 | Tab completion (callback-based)             |   ✗    | `set_completion_callback(fn)` for application-specific completions |
| 3.3 | Syntax highlighting (callback-based)        |   ✗    | `set_highlighter(fn)` to colorize the current line                 |
| 3.4 | Hints/suggestions (callback-based)          |   ✗    | Show dim suggestion text after cursor (like fish shell)            |
| 3.5 | Customizable key bindings                   |   ✗    | Register callbacks for arbitrary key sequences                     |
| 3.6 | Extract to standalone repo `forfudan/limo`  |   ✗    | Own pixi.toml, tests, README, conda-forge release                  |

**Milestone:** Feature-complete line editor suitable for general-purpose use.

### Future: Re-evaluate FFI Signature Alignment

Limo currently uses `Int`-only signatures for `tcgetattr`, `tcsetattr`, and `read` to match argmojo's `external_call` declarations and avoid LLVM IR conflicts (see [user_manual_limo.md](../user_manual_limo.md), "FFI Signature Convention"). This works but is a workaround — the root cause is that Mojo's `external_call` produces flat C-level symbols whose type signatures must be globally consistent across all packages.

As of Mojo nightly v0.26.3, a new `abi("C")` function effect has been added for declaring C calling convention on function definitions and function pointer types. Additionally, a bug fix now correctly applies platform ABI coercion (System V AMD64 / AAPCS on ARM64) when lowering external calls. These changes improve C interop but do not yet address the `external_call` signature conflict directly — `external_call` still produces global LLVM declarations that must match.

**Check periodically** (e.g., with each Mojo release) whether:

- [ ] `external_call` gains namespace-scoped or module-local declarations, allowing different packages to declare different signatures for the same C function without conflict.
- [ ] A higher-level C FFI mechanism (e.g., `DLHandle.get_function` with `abi("C")`) becomes the recommended way to call POSIX functions, making `external_call` alignment unnecessary.
- [ ] The Mojo team explicitly documents whether same-name `external_call` conflicts are a bug to be fixed or a design constraint to live with.

If any of these are resolved, limo (and argmojo) can adopt proper C types (`Int32` for fd, `UnsafePointer` for buffers) instead of the current `Int`-everywhere convention.

## 5. Design Decisions

| Decision              | Choice                          | Rationale                                                                                        |
| --------------------- | ------------------------------- | ------------------------------------------------------------------------------------------------ |
| Package location      | `src/cli/limo/` inside decimo   | Start as internal package; extract when API is stable and a second consumer exists               |
| Module count          | 2 modules + `__init__`          | Minimal footprint; `terminal.mojo` for FFI, `line_editor.mojo` for logic                         |
| Source of FFI code    | Adapted from termo              | Termo's Phase 1 (`sys_libc.mojo`, `raw_mode.mojo`) is tested and correct for macOS arm64         |
| Buffer representation | `List[UInt8]`                   | Byte-level buffer; simple and efficient; UTF-8 multi-byte handled in Phase 2                     |
| History storage       | `List[String]` with max cap     | Simple FIFO; most REPLs cap at 1000–5000 entries                                                 |
| Default keybindings   | Emacs-style (readline defaults) | Universal standard; every developer's muscle memory expects these                                |
| No Vi mode            | Intentional omission            | Complexity not justified for a calculator REPL; add in Phase 3 if demand exists                  |
| No multi-line editing | Intentional omission            | Calculator expressions are single-line; multi-line adds significant cursor management complexity |
| Platform              | macOS arm64 only (initially)    | Matches termo; Linux support requires different termios struct layout (add in Phase 2 if needed) |
| Prompt handling       | Prompt is a display-only string | `read_line(prompt)` writes the prompt but does not include it in the returned buffer             |
| Ctrl+C behavior       | Discard line, print newline     | Match readline: Ctrl+C cancels current input but doesn't exit the REPL (ISIG is disabled)        |
| EOF on Ctrl+D         | Only when buffer is empty       | Match readline: Ctrl+D on non-empty line is "delete under cursor"                                |
| ANSI escape strategy  | Direct write (no terminfo)      | All modern macOS/Linux terminals support VT100+; terminfo lookup is unnecessary complexity       |
| Relationship to termo | Subset, not dependency          | Limo copies the relevant FFI code rather than depending on termo; avoids dependency management   |

## 6. Line Redraw Algorithm

The core rendering operation. Called after every keystroke that modifies the buffer or cursor position.

```mojo
def _redraw(self):
    # 1. Move cursor to beginning of the line (column 0)
    write("\r")

    # 2. Write the prompt
    write(self.prompt)

    # 3. Write the entire buffer
    write(self.buffer)

    # 4. Clear any remaining characters from a previous longer line
    write(ESC[K)  # clear from cursor to end of line

    # 5. Move cursor back to the correct position
    #    The cursor should be at: prompt_display_width + cursor_position
    #    It is currently at: prompt_display_width + buffer_length
    #    So move left by: buffer_length - cursor_position
    var back = len(self.buffer) - self.cursor
    if back > 0:
        write(ESC[{back}D)
```

This is the same approach used by linenoise. It's simple, correct, and fast enough for interactive use (terminal bandwidth is not a bottleneck for single-line redraws).

For CJK support (Phase 2), `prompt_display_width` and cursor offset calculations must use `char_width()` instead of byte count.

## 7. History Navigation Algorithm

```mojo
# State:
#   history: List[String]       — past accepted lines (oldest first)
#   history_index: Int           — -1 = current line; 0..len-1 = history position
#   saved_line: String           — the in-progress line saved when entering history
#   buffer: List[UInt8]          — current line content
#   cursor: Int                  — cursor position in buffer

def _history_up():
    if len(history) == 0:
        return
    if history_index == -1:
        # Entering history for the first time — save current line
        saved_line = buffer_to_string()
        history_index = len(history) - 1  # most recent
    elif history_index > 0:
        history_index -= 1  # go further back
    else:
        return  # already at oldest entry

    # Load history entry into buffer
    set_buffer(history[history_index])
    cursor = len(buffer)  # cursor at end
    redraw()

def _history_down():
    if history_index == -1:
        return  # not in history navigation
    if history_index < len(history) - 1:
        history_index += 1
        set_buffer(history[history_index])
    else:
        # Return to the saved in-progress line
        history_index = -1
        set_buffer(saved_line)
    cursor = len(buffer)
    redraw()
```

## 8. Escape Sequence Parsing

When `read_byte()` returns `0x1B` (ESC), we need to determine whether this is a standalone Escape keypress or the start of a CSI escape sequence.

```mojo
def _read_escape_sequence() -> Action:
    # Read next byte with implicit short timeout (raw mode VTIME)
    var b1 = read_byte()

    if b1 == '[':   # CSI sequence
        var b2 = read_byte()
        match b2:
            case 'A': return HistoryUp
            case 'B': return HistoryDown
            case 'C': return CursorRight
            case 'D': return CursorLeft
            case 'H': return Home
            case 'F': return End
            case '3':
                var b3 = read_byte()
                if b3 == '~': return Delete
            case _: return Ignore  # unknown sequence

    elif b1 == 'b': return WordBackward     # Alt+B
    elif b1 == 'f': return WordForward      # Alt+F
    elif b1 == 'd': return DeleteWordForward # Alt+D
    elif b1 == 0x7F: return DeleteWordBackward # Alt+Backspace

    return Escape  # standalone ESC
```

Note: For Phase 1, we can use `VMIN=1, VTIME=0` (blocking) for simplicity. The ESC disambiguation timeout (`VMIN=0, VTIME=1` = 100ms) can be added in Phase 2 if needed. In practice, escape sequences arrive as bursts and the bytes are available immediately after ESC.

## 9. Complexity Estimate

| Component          | Estimated lines | Notes                                                  |
| ------------------ | --------------- | ------------------------------------------------------ |
| `terminal.mojo`    | ~200            | TermIOS + raw mode + ANSI helpers (adapted from termo) |
| `line_editor.mojo` | ~350            | Buffer, cursor, history, key dispatch, redraw          |
| `__init__.mojo`    | ~10             | Re-exports                                             |
| **Total Phase 1**  | **~560**        |                                                        |
| Tests              | ~200            | Buffer ops, cursor, history                            |
| Phase 2 additions  | ~150            | Word ops, Unicode, persistence                         |
| Phase 3 additions  | ~200            | Search, completion, highlights                         |

This is comparable to linenoise (1,100 lines of C for the full feature set).

## 10. Risk and Mitigation

| Risk                                                    | Mitigation                                                              |
| ------------------------------------------------------- | ----------------------------------------------------------------------- |
| TermIOS struct layout differs on Linux                  | Start macOS-only; add Linux layout with conditional compilation later   |
| Mojo's `external_call` behavior changes across versions | Pin Mojo version in pixi.toml; termo code already tested on 0.26.x      |
| Raw mode not restored on crash/panic                    | `RawModeGuard.__del__` does direct FFI (no raise); always defer cleanup |
| Unicode cursor positioning off-by-one for CJK           | Phase 1 is ASCII-only; add `char_width()` in Phase 2                    |
| UTF-8 multi-byte characters split across reads          | Phase 1 handles printable ASCII only; Phase 2 adds UTF-8 continuation   |
| Performance overhead of per-keystroke redraw            | Single-line redraw is fast; benchmark if needed                         |

## 11. References

- [linenoise](https://github.com/antirez/linenoise) — Salvatore Sanfilippo's ~1,100 line C readline replacement. The primary design inspiration for limo.
- [rustyline](https://github.com/kkawakam/rustyline) — Rust readline implementation. Reference for the callback-based completion/highlighting API.
- [termo](https://github.com/forfudan/termo) — My own Mojo terminal library. Source of FFI bindings and raw mode code (`/Users/ZHU/Programs/termo/`).
- [VT100 escape codes](https://vt100.net/docs/vt100-ug/chapter3.html) — Canonical reference for ANSI escape sequences.
- [XTerm Control Sequences](https://invisible-island.net/xterm/ctlseqs/ctlseqs.html) — Comprehensive reference for modern terminal escape sequences.
