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

"""Implements small utilities and helpers that are used in multiple places 
in the codebase.
"""


def unsigned_counterpart[dtype: DType]() -> DType where dtype.is_integral():
    """The unsigned dtype with the same bit width as `dtype`.

    A signed dtype maps to its unsigned sibling of equal width; an already
    unsigned dtype maps to itself. Handy when a value's magnitude has to
    live in an unsigned word so that the most negative value still fits.

    Constraints:
        `dtype` must be an integral dtype.

    Parameters:
        dtype: The integral dtype to find the unsigned counterpart for.

    Returns:
        The unsigned dtype with the same bit width as `dtype`.
    """
    comptime if dtype == DType.int8:
        return DType.uint8
    elif dtype == DType.int16:
        return DType.uint16
    elif dtype == DType.int32:
        return DType.uint32
    elif dtype == DType.int64:
        return DType.uint64
    elif dtype == DType.int128:
        return DType.uint128
    elif dtype == DType.int256:
        return DType.uint256
    elif dtype == DType.int:
        return DType.uint
    else:
        # Already unsigned: uint8 / uint16 / uint32 / uint64 / uint128 /
        # uint256 and the platform-sized `uint` are their own counterpart.
        comptime assert (
            dtype.is_unsigned()
        ), "unsigned_counterpart: unexpected signed integral dtype"
        return dtype


@always_inline
def alias_as_immutable_source[
    dtype: DType, //, o: Origin[mut=True]
](pointer: Pointer[Scalar[dtype], o]) -> Pointer[
    Scalar[dtype], ImmStaticOrigin
]:
    """Re-hands a mutable buffer pointer to a kernel as its own read source.

    Several word kernels take one mutable destination and one or more
    immutable sources, and are written so that the destination may be one of
    those sources: each word is read before the same word is written, and the
    tail copy is elided when the two pointers coincide. Handing the same
    buffer to both parameters is still an exclusivity violation the compiler
    rejects, because it cannot see that the overlap is exact rather than
    partial.

    This asserts precisely that, and nothing wider. The destination pointer
    keeps its real origin and so keeps the buffer alive for the call; only the
    duplicate handed in as a source loses its origin, and it never outlives the
    call it is written into.

    Do not use this to build a lasting pointer, to alias two *different*
    buffers that happen to overlap, or on a kernel whose contract does not
    already say the destination may alias a source.

    Parameters:
        dtype: The element dtype of the buffer.
        o: The origin of the mutable pointer.

    Args:
        pointer: The mutable destination pointer to re-hand as a source.

    Returns:
        The same address, typed as an immutable pointer with no origin.
    """
    return pointer.unsafe_mut_cast[False]().unsafe_origin_cast[
        ImmStaticOrigin
    ]()
