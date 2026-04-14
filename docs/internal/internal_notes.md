# Internal Notes

## Inconsistencies between libraries

- For power functionality: `BigDecimal.power()`, Python's decimal, WolframAlpha give the same result, but `mpmath` gives a different result. Eamples:
  - `0.123456789 ** 1000`
  - `1234523894766789 ** 1098.1209848`
- For sin functionality: `BigDecimal.sin()` and WolframAlpha give the same results, but `mpmath` gives a different result. This occurs mainly for pi-related values. Examples:
  - `sin(3.1415926535897932384626433833)`, precision 50:
    - Decimo:       -2.0497115802830600624894179025055407692183593713791E-29
    - WolframAlpha: -2.0497115802830600624894179025055407692183593713791 x 10-29
    - mpmath:       -2.049711580283060062489453928920860542175349360102e-29
  - `sin(6.2831853071795864769252867666)`, precision 50:
    - Decimo:       4.0994231605661201249788358050110815384367187427582E-29
    - WolframAlpha: 4.0994231605661201249788358050110815384367187427582 x 10-29
    - mpmath:       4.0994231605661201249789078578417210843506987202039e-29

## Time complexity for pi() implementations

- #94. Implementing pi() with Machin's formula. Time taken for precision 2048: 33.580649 seconds.
- #95. Implementing pi() with Chudnovsky algorithm (binary splitting). Time taken for precision 2048: 1.771954 seconds.
- #97. Implementing Karatsuba multiplication for BigUInt. Time taken for precision 2048: 0.60656999994535 seconds.
- #105. Implementing Burnikel-Ziegler division for BigUInt. Time taken for precision 2048: 0.5454419999732636 seconds.
