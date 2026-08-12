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

"""Provides terminal primitives for raw mode and ANSI escape sequences.

Adapted from termo (forfudan/termo) — provides the minimal subset needed
for single-line editing:

- TermIOS struct (macOS arm64 termios layout, 72 bytes)
- enable_raw_mode / disable_raw_mode (with manual cleanup)
- read_byte (blocking single-byte read from stdin)
- ANSI cursor helpers for single-line use

Platform support:

The `TermIOS` layout (size, field offsets, c_cc length, baud-rate placement)
is hard-coded for the **macOS arm64** ABI.  On other platforms — Linux
(x86_64 / aarch64), macOS x86_64, or any BSD — the C `struct termios`
layout differs, and using these primitives there will silently corrupt
terminal settings.  `enable_raw_mode()` therefore performs a runtime
check and raises on unsupported platforms; once a platform-specific
layout is added, the guard can be relaxed.  See:
https://github.com/forfudan/decimo/issues for tracking.
"""

from std.ffi import external_call
from std.sys.info import CompilationTarget


# === File descriptors ========================================================

comptime STDIN_FILENO: Int32 = 0
comptime STDOUT_FILENO: Int32 = 1
comptime STDERR_FILENO: Int32 = 2


# === tcsetattr actions ======================================================

comptime TCSAFLUSH: Int32 = 2


# === Input flags (c_iflag) ==================================================

comptime IGNBRK: UInt64 = 0x00000001
comptime BRKINT: UInt64 = 0x00000002
comptime PARMRK: UInt64 = 0x00000008
comptime ISTRIP: UInt64 = 0x00000020
comptime INLCR: UInt64 = 0x00000040
comptime IGNCR: UInt64 = 0x00000080
comptime ICRNL: UInt64 = 0x00000100
comptime IXON: UInt64 = 0x00000200


# === Output flags (c_oflag) ================================================

comptime OPOST: UInt64 = 0x00000001


# === Control flags (c_cflag) ===============================================

comptime CSIZE: UInt64 = 0x00000300
comptime CS8: UInt64 = 0x00000300
comptime PARENB: UInt64 = 0x00001000


# === Local flags (c_lflag) =================================================

comptime ECHO: UInt64 = 0x00000008
comptime ECHONL: UInt64 = 0x00000010
comptime ICANON: UInt64 = 0x00000100
comptime ISIG: UInt64 = 0x00000080
comptime IEXTEN: UInt64 = 0x00000400


# === Control character indices (macOS) =====================================
# These are indices into the c_cc[] array of the termios struct.
# VMIN: minimum number of bytes for a successful read() in raw mode.
# VTIME: timeout in deciseconds (0.1s) for read() in raw mode.

comptime VMIN: Int = 16
comptime VTIME: Int = 17


# === TermIOS ===============================================================


struct TermIOS(Copyable, Movable):
    """Terminal I/O settings — Mojo wrapper for C struct termios.

    macOS arm64 layout (72 bytes total):
        c_iflag:  UInt64   (offset  0) — input flags
        c_oflag:  UInt64   (offset  8) — output flags
        c_cflag:  UInt64   (offset 16) — control flags
        c_lflag:  UInt64   (offset 24) — local flags
        c_cc[20]: UInt8×20 (offset 32) — control characters
        _pad:     4 bytes  (offset 52) — alignment padding
        c_ispeed: UInt64   (offset 56) — input baud rate
        c_ospeed: UInt64   (offset 64) — output baud rate
    """

    comptime SIZE = 72
    comptime _IFLAG = 0
    comptime _OFLAG = 8
    comptime _CFLAG = 16
    comptime _LFLAG = 24
    comptime _CC = 32

    var _buf: List[UInt8]

    def __init__(out self):
        """Creates a zeroed TermIOS."""
        self._buf = List[UInt8](capacity=Self.SIZE)
        self._buf.resize(Self.SIZE, 0)

    def __init__(out self, *, copy: Self):
        self._buf = copy._buf.copy()

    def __init__(out self, *, deinit move: Self):
        self._buf = move._buf^

    def copy(self) -> Self:
        """Returns an explicit copy."""
        return Self(copy=self)

    # == Read/write helpers ===========================================
    # NOTE: We deliberately read/write the UInt64 fields one byte at a time
    # rather than via a `bitcast[UInt64]()` on a UInt8 pointer.  The backing
    # buffer is a `List[UInt8]` whose storage is byte-aligned, so a bitcast
    # would produce an unaligned UInt64 access — undefined behaviour on
    # platforms that require natural alignment for 64-bit loads/stores
    # (e.g. some ARM configurations).  Byte-shift assembly is well-defined
    # everywhere and the codegen is essentially identical on x86_64/arm64.

    @always_inline
    def _read_u64(mut self, offset: Int) -> UInt64:
        return (
            UInt64(self._buf[offset + 0])
            | (UInt64(self._buf[offset + 1]) << 8)
            | (UInt64(self._buf[offset + 2]) << 16)
            | (UInt64(self._buf[offset + 3]) << 24)
            | (UInt64(self._buf[offset + 4]) << 32)
            | (UInt64(self._buf[offset + 5]) << 40)
            | (UInt64(self._buf[offset + 6]) << 48)
            | (UInt64(self._buf[offset + 7]) << 56)
        )

    @always_inline
    def _write_u64(mut self, offset: Int, value: UInt64):
        self._buf[offset + 0] = UInt8(value & 0xFF)
        self._buf[offset + 1] = UInt8((value >> 8) & 0xFF)
        self._buf[offset + 2] = UInt8((value >> 16) & 0xFF)
        self._buf[offset + 3] = UInt8((value >> 24) & 0xFF)
        self._buf[offset + 4] = UInt8((value >> 32) & 0xFF)
        self._buf[offset + 5] = UInt8((value >> 40) & 0xFF)
        self._buf[offset + 6] = UInt8((value >> 48) & 0xFF)
        self._buf[offset + 7] = UInt8((value >> 56) & 0xFF)

    # == Flag accessors ===============================================

    def get_iflag(mut self) -> UInt64:
        return self._read_u64(Self._IFLAG)

    def set_iflag(mut self, value: UInt64):
        self._write_u64(Self._IFLAG, value)

    def get_oflag(mut self) -> UInt64:
        return self._read_u64(Self._OFLAG)

    def set_oflag(mut self, value: UInt64):
        self._write_u64(Self._OFLAG, value)

    def get_cflag(mut self) -> UInt64:
        return self._read_u64(Self._CFLAG)

    def set_cflag(mut self, value: UInt64):
        self._write_u64(Self._CFLAG, value)

    def get_lflag(mut self) -> UInt64:
        return self._read_u64(Self._LFLAG)

    def set_lflag(mut self, value: UInt64):
        self._write_u64(Self._LFLAG, value)

    # == Control character access ======================================

    def get_control_char(self, index: Int) -> UInt8:
        """Returns the control character at the given index in the c_cc array.
        """
        return self._buf[Self._CC + index]

    def set_control_char(mut self, index: Int, value: UInt8):
        """Sets the control character at the given index in the c_cc array."""
        self._buf[Self._CC + index] = value

    # == Raw mode configuration =======================================

    def make_raw(mut self):
        """Configures this TermIOS for raw mode (equivalent to cfmakeraw).

        Disables line buffering, echo, signals, input/output processing.
        Enables 8-bit characters and byte-at-a-time reads.
        """
        # Input: disable break/parity/strip/NL-CR mapping/flow control
        self.set_iflag(
            self.get_iflag()
            & ~(
                IGNBRK | BRKINT | PARMRK | ISTRIP | INLCR | IGNCR | ICRNL | IXON
            )
        )
        # Output: disable post-processing
        self.set_oflag(self.get_oflag() & ~OPOST)
        # Control: clear character size, disable parity, set 8-bit
        var control_flags = self.get_cflag()
        control_flags &= ~(CSIZE | PARENB)
        control_flags |= CS8
        self.set_cflag(control_flags)
        # Local: disable echo, canonical mode, signals, extended processing
        self.set_lflag(
            self.get_lflag() & ~(ECHO | ECHONL | ICANON | ISIG | IEXTEN)
        )
        # Read returns after 1 byte, no timeout
        self.set_control_char(VMIN, 1)
        self.set_control_char(VTIME, 0)


# === FFI wrappers ==========================================================
# Signature convention: integer parameters use Mojo's `Int` type so that
# the LLVM IR declarations match those in argmojo (forfudan/argmojo).  When
# two Mojo packages call `external_call["func", ...]` with the same function
# name, LLVM merges them into a single declaration — so the type lists MUST
# be identical.  Using `Int` everywhere (= i64 on 64-bit platforms) is the
# common convention adopted by argmojo; limo follows suit.
#
# Exemptions: `isatty`, `write` and `read` are already declared inside the
# Mojo stdlib with their own signatures (`Int32 -> Int32` for `isatty`, a
# variadic-ish form for `write` and `read`); using `Int` for those names
# produces an "existing function with conflicting signature" lowering error.
# We keep the stdlib's declared types for those three symbols and use the
# `Int` convention for every other libc function we call directly.
#
# Reference: https://github.com/forfudan/argmojo — see src/argmojo/utils.mojo
# for the canonical FFI signatures.


def _tcgetattr(file_descriptor: Int32, mut settings: TermIOS) raises:
    """Gets terminal attributes for the given file descriptor."""
    var return_code = external_call["tcgetattr", Int, Int, Int](
        Int(file_descriptor), Int(settings._buf.unsafe_ptr())
    )
    if return_code != 0:
        raise Error("tcgetattr failed")


def _tcsetattr_raw(
    file_descriptor: Int32, action: Int32, mut settings: TermIOS
) -> Int32:
    """Sets terminal attributes (low-level, returns the return code directly).
    """
    return Int32(
        external_call["tcsetattr", Int, Int, Int, Int](
            Int(file_descriptor), Int(action), Int(settings._buf.unsafe_ptr())
        )
    )


def _tcsetattr(
    file_descriptor: Int32, action: Int32, mut settings: TermIOS
) raises:
    """Sets terminal attributes for the given file descriptor."""
    if _tcsetattr_raw(file_descriptor, action, settings) != 0:
        raise Error("tcsetattr failed")


def _isatty(file_descriptor: Int32) -> Bool:
    """Checks if the given file descriptor refers to a terminal.

    NOTE: Uses the `Int32 -> Int32` signature rather than the project's
    usual `Int`-based FFI convention because the Mojo stdlib already
    declares `isatty` with the `Int32` signature; using `Int` here would
    produce an "existing function with conflicting signature" LLVM IR
    lowering error.  See the FFI convention comment above for details.
    """
    return external_call["isatty", Int32](file_descriptor) != 0


# === Raw mode control =====================================================


def enable_raw_mode() raises -> TermIOS:
    """Enters raw mode on stdin and returns the original terminal settings.

    The caller must pass the returned TermIOS to `disable_raw_mode()`
    or `disable_raw_mode_nothrow()` when done to restore the terminal.

    Raises on non-macOS-arm64 platforms because the hard-coded `termios`
    layout would not match the kernel's `struct termios`.
    """
    comptime if not (
        CompilationTarget.is_macos() and CompilationTarget.has_neon()
    ):
        raise Error(
            "limo raw mode is currently only supported on macOS arm64; "
            "the TermIOS layout in this file is hard-coded for that ABI."
        )
    if not _isatty(STDIN_FILENO):
        raise Error("stdin is not a terminal")

    var original = TermIOS()
    _tcgetattr(STDIN_FILENO, original)

    var raw = original.copy()
    raw.make_raw()
    _tcsetattr(STDIN_FILENO, TCSAFLUSH, raw)

    return original^


def disable_raw_mode(mut original_settings: TermIOS) raises:
    """Restores the terminal to the given original settings."""
    _tcsetattr(STDIN_FILENO, TCSAFLUSH, original_settings)


def disable_raw_mode_nothrow(mut original_settings: TermIOS):
    """Restores the terminal to the given original settings (best-effort).

    Uses the non-raising variant so it is safe for cleanup paths
    where propagating errors is not possible.
    """
    _ = _tcsetattr_raw(STDIN_FILENO, TCSAFLUSH, original_settings)


# === I/O primitives =======================================================


def read_byte() raises -> UInt8:
    """Reads a single byte from stdin (blocking).

    Requires raw mode to be active for byte-at-a-time reads.
    Uses `read(2)` without explicit argument types, like `write` below: the
    Mojo stdlib already declares `read`, so spelling out the argument types
    produces a conflicting LLVM declaration.
    """
    var buf = List[UInt8](length=1, fill=0)
    var bytes_read = external_call["read", Int](
        Int(STDIN_FILENO), buf.unsafe_ptr(), UInt(1)
    )
    if bytes_read <= 0:
        raise Error("read failed (EOF)")
    return buf[0]


def write_stdout(data: String):
    """Writes a string to stdout (best-effort, for terminal output)."""
    var byte_span = data.as_bytes()
    # NOTE: Unlike tcgetattr/tcsetattr/read, we do NOT use explicit Int arg
    # types here because `write` already has a declaration in the Mojo stdlib
    # with different arg types — adding explicit types would cause an LLVM IR
    # signature conflict.
    _ = external_call["write", Int](
        Int(STDOUT_FILENO),
        byte_span.unsafe_ptr(),
        UInt(len(byte_span)),
    )


def write_stderr(data: String):
    """Writes a string to stderr (best-effort, for prompt output)."""
    var byte_span = data.as_bytes()
    # Same note as write_stdout — no explicit arg types for `write`.
    _ = external_call["write", Int](
        Int(STDERR_FILENO),
        byte_span.unsafe_ptr(),
        UInt(len(byte_span)),
    )


# === ANSI escape helpers (single-line use) =================================


def cursor_move_left(count: Int):
    """Moves the cursor left by `count` columns."""
    if count > 0:
        write_stdout("\x1b[" + String(count) + "D")


def cursor_move_right(count: Int):
    """Moves the cursor right by `count` columns."""
    if count > 0:
        write_stdout("\x1b[" + String(count) + "C")


def clear_line_from_cursor():
    """Clears from the cursor to the end of the line."""
    write_stdout("\x1b[K")


def clear_screen():
    """Clears the entire screen and moves the cursor to top-left."""
    write_stdout("\x1b[2J\x1b[H")


def move_to_column_zero():
    """Moves the cursor to the beginning of the current line."""
    write_stdout("\r")
