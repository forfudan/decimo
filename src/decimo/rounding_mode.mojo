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

"""Implements the RoundingMode for different rounding modes.
"""

comptime ROUND_DOWN = RoundingMode.ROUND_DOWN
"""Rounding mode: Truncate (toward zero)."""
comptime ROUND_HALF_UP = RoundingMode.ROUND_HALF_UP
"""Rounding mode: Round away from zero if >= 0.5."""
comptime ROUND_HALF_DOWN = RoundingMode.ROUND_HALF_DOWN
"""Rounding mode: Round toward zero if <= 0.5."""
comptime ROUND_HALF_EVEN = RoundingMode.ROUND_HALF_EVEN
"""Rounding mode: Round to nearest even digit if equidistant (banker's rounding)."""
comptime ROUND_UP = RoundingMode.ROUND_UP
"""Rounding mode: Round away from zero."""
comptime ROUND_CEILING = RoundingMode.ROUND_CEILING
"""Rounding mode: Round toward positive infinity."""
comptime ROUND_FLOOR = RoundingMode.ROUND_FLOOR
"""Rounding mode: Round toward negative infinity."""


struct RoundingMode(Copyable, ImplicitlyCopyable, Movable, Writable):
    """
    Represents different rounding modes for decimal operations.

    Available modes:
    - DOWN: Truncate (toward zero)
    - HALF_UP: Round away from zero if >= 0.5
    - HALF_DOWN: Round toward zero if <= 0.5
    - HALF_EVEN: Round to nearest even digit if equidistant (banker's rounding)
    - UP: Round away from zero
    - CEILING: Round toward positive infinity
    - FLOOR: Round toward negative infinity

    Notes:

    Currently, enum is not available in Mojo. This module provides a workaround
    to define a custom enum-like class for rounding modes.
    """

    # alias
    comptime ROUND_DOWN = Self.down()
    """Truncate (toward zero)."""
    comptime ROUND_HALF_UP = Self.half_up()
    """Round away from zero if >= 0.5."""
    comptime ROUND_HALF_DOWN = Self.half_down()
    """Round toward zero if <= 0.5."""
    comptime ROUND_HALF_EVEN = Self.half_even()
    """Round to nearest even digit if equidistant (banker's rounding)."""
    comptime ROUND_UP = Self.up()
    """Round away from zero."""
    comptime ROUND_CEILING = Self.ceiling()
    """Round toward positive infinity."""
    comptime ROUND_FLOOR = Self.floor()
    """Round toward negative infinity."""

    # Internal value
    var value: Int
    """Internal value representing the rounding mode."""

    # Static constants for each rounding mode
    @staticmethod
    def down() -> Self:
        """Creates a `RoundingMode` that truncates toward zero.

        Returns:
            A `RoundingMode` representing truncation toward zero.
        """
        return Self(0)

    @staticmethod
    def half_up() -> Self:
        """Creates a `RoundingMode` that rounds away from zero if >= 0.5.

        Returns:
            A `RoundingMode` representing half-up rounding.
        """
        return Self(1)

    @staticmethod
    def half_down() -> Self:
        """Creates a `RoundingMode` that rounds toward zero if <= 0.5.

        Returns:
            A `RoundingMode` representing half-down rounding.
        """
        return Self(6)

    @staticmethod
    def half_even() -> Self:
        """Creates a `RoundingMode` that rounds to nearest even digit if equidistant.

        Returns:
            A `RoundingMode` representing banker's rounding.
        """
        return Self(2)

    @staticmethod
    def up() -> Self:
        """Creates a `RoundingMode` that rounds away from zero.

        Returns:
            A `RoundingMode` representing round-up.
        """
        return Self(3)

    @staticmethod
    def ceiling() -> Self:
        """Creates a `RoundingMode` that rounds toward positive infinity.

        Returns:
            A `RoundingMode` representing ceiling rounding.
        """
        return Self(4)

    @staticmethod
    def floor() -> Self:
        """Creates a `RoundingMode` that rounds toward negative infinity.

        Returns:
            A `RoundingMode` representing floor rounding.
        """
        return Self(5)

    def __init__(out self, value: Int):
        """Creates a `RoundingMode` from its internal integer representation.

        Args:
            value: The integer code identifying the rounding mode.
        """
        self.value = value

    def __eq__(self, other: Self) -> Bool:
        """Checks whether two `RoundingMode` values are equal.

        Args:
            other: The `RoundingMode` to compare against.

        Returns:
            `True` if both rounding modes have the same internal value.
        """
        return self.value == other.value

    def __eq__(self, other: String) -> Bool:
        """Checks whether this rounding mode matches a string name.

        Args:
            other: The rounding mode name to compare against (e.g. "ROUND_DOWN").

        Returns:
            `True` if the string representation of this mode equals `other`.
        """
        return String(self) == other

    def write_to[W: Writer](self, mut writer: W):
        """Writes the rounding mode name to a writer.

        Parameters:
            W: A type conforming to the `Writer` interface.

        Args:
            writer: The writer instance.
        """
        if self == Self.down():
            writer.write("ROUND_DOWN")
        elif self == Self.half_up():
            writer.write("ROUND_HALF_UP")
        elif self == Self.half_even():
            writer.write("ROUND_HALF_EVEN")
        elif self == Self.up():
            writer.write("ROUND_UP")
        elif self == Self.ceiling():
            writer.write("ROUND_CEILING")
        elif self == Self.half_down():
            writer.write("ROUND_HALF_DOWN")
        elif self == Self.floor():
            writer.write("ROUND_FLOOR")
        else:
            writer.write("UNKNOWN_ROUNDING_MODE")
