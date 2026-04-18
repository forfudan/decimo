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

"""Provides a readline-style line editor with history support.

Provides arrow-key navigation, Emacs-style shortcuts (Ctrl+A/E/K/U/W/L),
backspace, delete, and up/down history navigation for interactive REPLs.

Usage::

    from limo import LineEditor

    var editor = LineEditor()
    while True:
        var line = editor.read_line("prompt> ")
        if not line:
            break  # EOF (Ctrl-D on empty line)
        process(line.value())
"""

from .terminal import (
    enable_raw_mode,
    disable_raw_mode_nothrow,
    read_byte,
    write_stdout,
    write_stderr,
    cursor_move_left,
    clear_line_from_cursor,
    clear_screen,
    move_to_column_zero,
)


# === Action enum (dispatch targets) =========================================

# Actions returned by key parsing, used for the main dispatch loop.
comptime _ACT_INSERT: Int = 0
comptime _ACT_ACCEPT: Int = 1  # Enter
comptime _ACT_EOF: Int = 2  # Ctrl-D on empty line
comptime _ACT_CANCEL: Int = 3  # Ctrl-C
comptime _ACT_LEFT: Int = 4
comptime _ACT_RIGHT: Int = 5
comptime _ACT_HOME: Int = 6
comptime _ACT_END: Int = 7
comptime _ACT_BACKSPACE: Int = 8
comptime _ACT_DELETE: Int = 9
comptime _ACT_DELETE_OR_EOF: Int = 10  # Ctrl-D (delete or EOF)
comptime _ACT_KILL_TO_END: Int = 11  # Ctrl-K
comptime _ACT_KILL_TO_START: Int = 12  # Ctrl-U
comptime _ACT_KILL_WORD_BACK: Int = 13  # Ctrl-W
comptime _ACT_HISTORY_UP: Int = 14
comptime _ACT_HISTORY_DOWN: Int = 15
comptime _ACT_CLEAR_SCREEN: Int = 16  # Ctrl-L
comptime _ACT_IGNORE: Int = 17


# === LineEditor ==============================================================


struct LineEditor(Movable):
    """A readline-style line editor with history support.

    Enters raw terminal mode during `read_line()` and restores the
    original terminal settings on return (even on error).  Supports:

    - Left/Right arrow cursor movement
    - Home/End (and Ctrl+A/Ctrl+E)
    - Backspace and Delete
    - Ctrl+K (kill to end), Ctrl+U (kill to start), Ctrl+W (kill word)
    - Ctrl+L (clear screen and redraw)
    - Ctrl+C (discard line), Ctrl+D (EOF on empty / delete)
    - Up/Down arrow history navigation
    """

    var _history: List[String]
    var _max_history: Int

    fn __init__(out self, max_history: Int = 1000):
        """Creates a new LineEditor.

        Args:
            max_history: Maximum number of history entries to retain.
        """
        self._history = List[String]()
        self._max_history = max_history

    fn __init__(out self, *, deinit take: Self):
        self._history = take._history^
        self._max_history = take._max_history

    def read_line(mut self, prompt: String) raises -> Optional[String]:
        """Displays a prompt and reads a line with full editing support.

        Returns the edited line on Enter, or None on EOF (Ctrl-D on
        empty line).  Automatically adds non-empty lines to history.
        Non-empty duplicate of the most recent history entry is skipped.

        The prompt is written to stderr so that stdout remains clean
        for piping results.

        Args:
            prompt: The prompt string to display (e.g. "decimo> ").

        Returns:
            The edited line, or None on EOF.
        """
        # Enter raw mode — restored after the loop exits
        var original_settings = enable_raw_mode()

        # Result accumulator — set when we're ready to return
        var result: Optional[String] = None
        var done = False

        # Line buffer and cursor state
        var buffer = List[UInt8]()
        var cursor: Int = 0

        # History navigation state
        var history_index: Int = -1  # -1 = current line (not navigating)
        var saved_line = String("")

        # Prompt display width (ASCII only for Phase 1)
        var prompt_len = len(prompt)

        # Draw initial prompt
        self._draw_prompt(prompt)

        while not done:
            # Read a key and classify it
            var byte: UInt8
            try:
                byte = read_byte()
            except:
                # Read error — treat as EOF
                write_stdout("\n")
                done = True
                continue

            var action = _ACT_IGNORE
            var insert_byte: UInt8 = 0

            # Classify the byte into an action
            if byte == 0x0D or byte == 0x0A:
                action = _ACT_ACCEPT
            elif byte == 0x03:
                action = _ACT_CANCEL
            elif byte == 0x04:
                action = _ACT_DELETE_OR_EOF
            elif byte == 0x01:
                action = _ACT_HOME
            elif byte == 0x05:
                action = _ACT_END
            elif byte == 0x02:
                action = _ACT_LEFT
            elif byte == 0x06:
                action = _ACT_RIGHT
            elif byte == 0x0B:
                action = _ACT_KILL_TO_END
            elif byte == 0x15:
                action = _ACT_KILL_TO_START
            elif byte == 0x17:
                action = _ACT_KILL_WORD_BACK
            elif byte == 0x0C:
                action = _ACT_CLEAR_SCREEN
            elif byte == 0x7F:
                action = _ACT_BACKSPACE
            elif byte == 0x1B:
                action = self._parse_escape()
            elif byte >= 0x20 and byte <= 0x7E:
                action = _ACT_INSERT
                insert_byte = byte

            # == Dispatch action ======================================

            if action == _ACT_ACCEPT:
                write_stdout("\r\n")
                var line = _buffer_to_string(buffer)
                self._add_history(line)
                result = line
                done = True

            elif action == _ACT_CANCEL:
                write_stdout("\r\n")
                result = String("")
                done = True

            elif action == _ACT_DELETE_OR_EOF:
                if len(buffer) == 0:
                    done = True  # EOF — result stays None
                else:
                    _action_delete(buffer, cursor)
                    self._redraw(prompt, buffer, cursor, prompt_len)

            elif action == _ACT_INSERT:
                _action_insert(buffer, cursor, insert_byte)
                self._redraw(prompt, buffer, cursor, prompt_len)

            elif action == _ACT_BACKSPACE:
                if cursor > 0:
                    _action_backspace(buffer, cursor)
                    self._redraw(prompt, buffer, cursor, prompt_len)

            elif action == _ACT_DELETE:
                if cursor < len(buffer):
                    _action_delete(buffer, cursor)
                    self._redraw(prompt, buffer, cursor, prompt_len)

            elif action == _ACT_LEFT:
                if cursor > 0:
                    cursor -= 1
                    cursor_move_left(1)

            elif action == _ACT_RIGHT:
                if cursor < len(buffer):
                    cursor += 1
                    write_stdout("\x1b[1C")

            elif action == _ACT_HOME:
                if cursor > 0:
                    cursor_move_left(cursor)
                    cursor = 0

            elif action == _ACT_END:
                if cursor < len(buffer):
                    var diff = len(buffer) - cursor
                    write_stdout("\x1b[" + String(diff) + "C")
                    cursor = len(buffer)

            elif action == _ACT_KILL_TO_END:
                if cursor < len(buffer):
                    buffer.resize(cursor, 0)
                    clear_line_from_cursor()

            elif action == _ACT_KILL_TO_START:
                if cursor > 0:
                    _action_kill_to_start(buffer, cursor)
                    self._redraw(prompt, buffer, cursor, prompt_len)

            elif action == _ACT_KILL_WORD_BACK:
                if cursor > 0:
                    _action_kill_word_back(buffer, cursor)
                    self._redraw(prompt, buffer, cursor, prompt_len)

            elif action == _ACT_HISTORY_UP:
                _action_history_up(
                    self._history, buffer, cursor, history_index, saved_line
                )
                self._redraw(prompt, buffer, cursor, prompt_len)

            elif action == _ACT_HISTORY_DOWN:
                _action_history_down(
                    self._history, buffer, cursor, history_index, saved_line
                )
                self._redraw(prompt, buffer, cursor, prompt_len)

            elif action == _ACT_CLEAR_SCREEN:
                clear_screen()
                self._redraw(prompt, buffer, cursor, prompt_len)

        # Restore terminal before returning
        disable_raw_mode_nothrow(original_settings)
        return result

    def add_history(mut self, line: String):
        """Adds a line to history manually."""
        if len(line) == 0:
            return
        self._history.append(line)
        if len(self._history) > self._max_history:
            _ = self._history.pop(0)

    def clear_history(mut self):
        """Clears all history entries."""
        self._history.clear()

    def get_history(self) -> List[String]:
        """Returns a copy of the history buffer."""
        return self._history.copy()

    def set_max_history(mut self, max: Int):
        """Sets the maximum number of history entries to retain."""
        self._max_history = max
        while len(self._history) > self._max_history:
            _ = self._history.pop(0)

    # == Private helpers ==============================================

    fn _draw_prompt(self, prompt: String):
        """Writes the styled prompt to stderr."""
        # Bold green prompt, matching the existing decimo style
        write_stderr("\x1b[1m\x1b[92m" + prompt + "\x1b[0m")

    fn _redraw(
        self,
        prompt: String,
        buffer: List[UInt8],
        cursor: Int,
        prompt_len: Int,
    ):
        """Redraws the prompt and buffer, then positions the cursor correctly.

        Algorithm (same as linenoise):
        1. Move to column 0
        2. Write prompt
        3. Write buffer
        4. Clear remaining chars from previous longer line
        5. Move cursor back to correct position
        """
        # 1. Carriage return
        move_to_column_zero()

        # 2. Prompt (to stderr — but in raw mode we write directly)
        write_stderr("\x1b[1m\x1b[92m" + prompt + "\x1b[0m")

        # 3. Buffer content
        if len(buffer) > 0:
            write_stdout(_buffer_to_string(buffer))

        # 4. Clear to end of line
        clear_line_from_cursor()

        # 5. Move cursor back to correct position
        var back = len(buffer) - cursor
        if back > 0:
            cursor_move_left(back)

    def _parse_escape(self) -> Int:
        """Parses an escape sequence after ESC (0x1B) has been read.

        Returns the action code for the recognized sequence.
        """
        var first_byte: UInt8
        try:
            first_byte = read_byte()
        except:
            return _ACT_IGNORE

        if first_byte == 91:  # '['  — CSI sequence
            var second_byte: UInt8
            try:
                second_byte = read_byte()
            except:
                return _ACT_IGNORE

            if second_byte == 65:  # 'A' — Up
                return _ACT_HISTORY_UP
            elif second_byte == 66:  # 'B' — Down
                return _ACT_HISTORY_DOWN
            elif second_byte == 67:  # 'C' — Right
                return _ACT_RIGHT
            elif second_byte == 68:  # 'D' — Left
                return _ACT_LEFT
            elif second_byte == 72:  # 'H' — Home
                return _ACT_HOME
            elif second_byte == 70:  # 'F' — End
                return _ACT_END
            elif second_byte == 51:  # '3' — might be Delete
                var third_byte: UInt8
                try:
                    third_byte = read_byte()
                except:
                    return _ACT_IGNORE
                if third_byte == 126:  # '~' — Delete
                    return _ACT_DELETE
                return _ACT_IGNORE
            else:
                return _ACT_IGNORE

        # Alt+key sequences (ESC followed by a printable char)
        # Phase 2: Alt+B, Alt+F, Alt+D, Alt+Backspace
        return _ACT_IGNORE

    def _add_history(mut self, line: String):
        """Adds a non-empty line to history, skipping consecutive duplicates."""
        if len(line) == 0:
            return
        # Skip if same as the most recent entry
        if (
            len(self._history) > 0
            and self._history[len(self._history) - 1] == line
        ):
            return
        self._history.append(line)
        if len(self._history) > self._max_history:
            _ = self._history.pop(0)


# === Buffer manipulation helpers (module-level fns) ==========================


fn _buffer_to_string(buffer: List[UInt8]) -> String:
    """Converts a byte buffer to a String."""
    if len(buffer) == 0:
        return String("")
    var copy = List[UInt8](capacity=len(buffer))
    for i in range(len(buffer)):
        copy.append(buffer[i])
    return String(unsafe_from_utf8=copy^)


fn _action_insert(mut buffer: List[UInt8], mut cursor: Int, byte: UInt8):
    """Inserts a byte at the cursor position and advances the cursor."""
    if cursor == len(buffer):
        # Append at end — fast path
        buffer.append(byte)
    else:
        # Insert in the middle
        buffer.append(0)  # extend
        var i = len(buffer) - 1
        while i > cursor:
            buffer[i] = buffer[i - 1]
            i -= 1
        buffer[cursor] = byte
    cursor += 1


fn _action_backspace(mut buffer: List[UInt8], mut cursor: Int):
    """Deletes the byte before the cursor."""
    if cursor <= 0 or cursor > len(buffer):
        return
    # Shift left
    var i = cursor - 1
    while i < len(buffer) - 1:
        buffer[i] = buffer[i + 1]
        i += 1
    _ = buffer.pop()
    cursor -= 1


fn _action_delete(mut buffer: List[UInt8], mut cursor: Int):
    """Deletes the byte at the cursor position."""
    if cursor < 0 or cursor >= len(buffer):
        return
    var i = cursor
    while i < len(buffer) - 1:
        buffer[i] = buffer[i + 1]
        i += 1
    _ = buffer.pop()


fn _action_kill_to_start(mut buffer: List[UInt8], mut cursor: Int):
    """Deletes everything from the start of the line to the cursor."""
    if cursor <= 0:
        return
    var new_len = len(buffer) - cursor
    for i in range(new_len):
        buffer[i] = buffer[cursor + i]
    buffer.resize(new_len, 0)
    cursor = 0


fn _action_kill_word_back(mut buffer: List[UInt8], mut cursor: Int):
    """Deletes the word before the cursor (Ctrl+W).

    Deletes backward: first skips whitespace, then skips non-whitespace.
    """
    if cursor <= 0:
        return
    var original_cursor = cursor

    # Skip whitespace backward
    while cursor > 0 and buffer[cursor - 1] == 32:  # ' '
        cursor -= 1
    # Skip non-whitespace backward
    while cursor > 0 and buffer[cursor - 1] != 32:
        cursor -= 1

    # Remove [cursor, original_cursor) from buffer
    var removed = original_cursor - cursor
    if removed > 0:
        var new_len = len(buffer) - removed
        var dest_index = cursor
        for i in range(original_cursor, len(buffer)):
            buffer[dest_index] = buffer[i]
            dest_index += 1
        buffer.resize(new_len, 0)


fn _action_history_up(
    history: List[String],
    mut buffer: List[UInt8],
    mut cursor: Int,
    mut history_index: Int,
    mut saved_line: String,
):
    """Navigates to the previous history entry."""
    if len(history) == 0:
        return
    if history_index == -1:
        # Entering history for the first time — save current line
        saved_line = _buffer_to_string(buffer)
        history_index = len(history) - 1
    elif history_index > 0:
        history_index -= 1
    else:
        return  # Already at oldest entry

    _set_buffer_from_string(buffer, cursor, history[history_index])


fn _action_history_down(
    history: List[String],
    mut buffer: List[UInt8],
    mut cursor: Int,
    mut history_index: Int,
    mut saved_line: String,
):
    """Navigates to the next history entry or back to the current line."""
    if history_index == -1:
        return  # Not navigating history

    if history_index < len(history) - 1:
        history_index += 1
        _set_buffer_from_string(buffer, cursor, history[history_index])
    else:
        # Return to the saved in-progress line
        history_index = -1
        _set_buffer_from_string(buffer, cursor, saved_line)


fn _set_buffer_from_string(
    mut buffer: List[UInt8], mut cursor: Int, text: String
):
    """Replaces the buffer contents with the given string and sets cursor to the end.
    """
    var bytes = StringSlice(text).as_bytes()
    buffer.clear()
    for i in range(len(bytes)):
        buffer.append(bytes[i])
    cursor = len(buffer)
