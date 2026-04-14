# API Reference

## Initialization of BigUInt

There are three issues associated with the initialization of `BigUInt`:

1. The embedded list of words is **empty**. In this sense, the coefficient of the `BigUInt` is **uninitialized**. This situation, in most cases, is not desirable because it can lead to bugs and unexpected behavior if users try to perform arithmetic operations on an uninitialized `BigUInt`. However, in some cases, users may want to create an uninitialized `BigUInt` for performance reasons, e.g., when they want to fill the words with their own values later. Therefore, we can allow users to create an uninitialized `BigUInt` by providing a key-word only argument, e.g., `uninitialized=True`.
1. There are **leading zero words** in the embedded list of words, e.g., 000000000_123456789. This situation is not a safety issue, but it can lead to performance issues because it increases the number of words that need to be processed during arithmetic operations. In some cases, users may want to keep these leading zero words for specific applications, e.g., aligning the number of words for two `BigUInt` operations.
1. The value of a word is greater than **999_999_999**. This situation is a safety issue because it violates the invariant that each word should be smaller than a billion. It can lead to bugs and unexpected behavior if users try to perform arithmetic operations on a `BigUInt` with invalid words.

To make sure that the users construct `BigUInt` safely by default, the default constructor of `BigUInt` will check for these issues so that the `BigUInt` is always non-empty, has no leading zero words, and all words are smaller than a billion. We also allow users, mainly developers, to create unsafe `BigUInt` instances if they want to, but they must explicitly choose to do so by providing a key-word only argument, e.g., `uninitialized=True`, or use specific methods, e.g., `from_list_unsafe()`.

Note: Mojo now supports keyword-only arguments of the same data type.

| Method                                   | non-empty | no leading zero words | all words valid | notes                                  |
| ---------------------------------------- | --------- | --------------------- | --------------- | -------------------------------------- |
| `BigUInt(var words: List[UInt32])`       | ✓         | ✓                     | ✓               | Validating constructor for word lists. |
| `BigUInt(*, uninitialized_capacity=Int)` | ✗         | ?                     | ?               | Length of words list is 0              |
| `BigUInt(*, unsafe_uninit_length=Int)`   | ✗         | ?                     | ?               | Length of words list not 0             |
| `BigUInt(*, raw_words: List[UInt32])`    | ✓         | ✗                     | ✗               |                                        |
| `BigUInt(value: Int)`                    | ✓         | ✓                     | ✓               |                                        |
| `BigUInt(value: Scalar)`                 | ✓         | ✓                     | ✓               | Only unsigned scalars are supported.   |

## Initialization of Decimal

### Python Interoperability: `from_python_decimal()`

Method Signature is

```mojo
@staticmethod
fn from_python_decimal(value: PythonObject) raises -> Decimal
```

---

Why use `as_tuple()` instead of direct memory copy (memcpy)?

Python's `decimal` module (libmpdec) internally uses a base-10^9 representation on 64-bit systems (base 10^4 on 32-bit), which happens to match Decimal's internal representation. This raises the question: why not directly memcpy the internal limbs for better performance?

Direct memcpy is theoretically possible because:

- On 64-bit systems: libmpdec uses base 10^9, same as Decimal
- Both use `uint32_t` limbs for storage
- Direct memory mapping would avoid digit decomposition overhead

However, this approach is **NOT** used due to significant practical issues:

1. No mature API for direct access.
1. Using direct memory access would require unsafe pointer manipulation, breaking Decimo's current design principles of using safe Mojo as much as possible.
1. Platform dependency. 32-bit systems use base 10^4 (incompatible with Decimal's 10^9). This would require runtime platform detection.
1. Maintenance burden. CPython internal structure (`mpd_t`) may change between versions.
1. Marginal performance gain. `as_tuple()` overhead: O(n) where n = number of digits. Direct memcpy: O(m) where m = number of limbs. Theoretical speedup: ~10x. But how often are users really converting Python decimals to Decimal?

---

The `as_tuple()` API returns a tuple of `(sign, digits, exponent)`:

- `sign`: 0 for positive, 1 for negative
- `digits`: Tuple of individual decimal digits (0-9)
- `exponent`: Power of 10 to multiply by

`as_tuple()` performs limb → digits decomposition internally. The digits returned are individual base-10 digits, not the base-10^9 limbs stored internally.

Example:

```python
# Python
from decimal import Decimal
d = Decimal("123456789012345678")
print(d.as_tuple())
# DecimalTuple(sign=0, digits=(1,2,3,4,5,6,7,8,9,0,1,2,3,4,5,6,7,8), exponent=0)
```

The `as_tuple()` approach provides:

- Safe: No unsafe pointer manipulation
- Stable: Public API guaranteed across Python versions
- Portable: Works on all platforms (32/64-bit, CPython/PyPy/etc.)
- Clean: Maintainable, readable code
- Adequate performance: O(n) is acceptable for typical use cases
