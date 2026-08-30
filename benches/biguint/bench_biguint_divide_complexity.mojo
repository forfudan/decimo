"""Benchmark for BigUInt division time complexity analysis.

Tests word sizes from 32 to 2^18 words (powers of 2).
Cases are generated programmatically — no TOML data file.
"""

from std.collections import List
from std.python import Python, PythonObject
from std.time import perf_counter_ns

from decimo import BigUInt
from decimo.biguint.arithmetics import floor_divide
from decimo.tests import log_print, open_log_file, print_header


def create_test_biguint(num_words: Int) raises -> BigUInt:
    """Creates a BigUInt with the specified number of words filled with test
    values."""
    var words = List[UInt32](capacity=num_words)
    for i in range(num_words):
        if i == num_words - 1:
            words.append(UInt32(100_000_000 + (i % 800_000_000)))
        else:
            words.append(UInt32(123_456_789 + (i % 876_543_210)))
    return BigUInt(words=words^)


def benchmark_divide_at_size(
    dividend_words: Int,
    divisor_words: Int,
    iterations: Int,
    log_file: PythonObject,
) raises -> Float64:
    """Benchmarks division for specific word sizes."""
    log_print(
        "Testing "
        + String(dividend_words)
        + " / "
        + String(divisor_words)
        + " words...",
        log_file,
    )

    var dividend = create_test_biguint(dividend_words)
    var divisor = create_test_biguint(divisor_words)
    var total_time: Float64 = 0.0

    for i in range(iterations):
        var start = perf_counter_ns()
        var _result = floor_divide(dividend, divisor)
        var elapsed = Float64(perf_counter_ns() - start) / 1_000_000_000.0
        total_time += elapsed
        log_print(
            "  Iteration "
            + String(i + 1)
            + ": "
            + String(elapsed)
            + " seconds",
            log_file,
        )

    var avg = total_time / Float64(iterations)
    log_print(
        "  Average time for "
        + String(dividend_words)
        + " / "
        + String(divisor_words)
        + " words: "
        + String(avg)
        + " seconds",
        log_file,
    )
    return avg


def main() raises:
    var log_file = open_log_file("benchmark_divide_complexity")
    print_header("Decimo BigUInt Division Time Complexity Benchmark", log_file)

    log_print("", log_file)
    log_print(
        "Testing division with various dividend and divisor sizes", log_file
    )
    log_print("Each test uses 5 iterations for averaging", log_file)
    log_print(
        "WARNING: Larger sizes (>100K words) may take significant time!",
        log_file,
    )
    log_print("", log_file)

    var test_sizes = List[Int]()
    test_sizes.append(32)
    test_sizes.append(64)
    test_sizes.append(128)
    test_sizes.append(256)
    test_sizes.append(512)
    test_sizes.append(1024)
    test_sizes.append(2048)
    test_sizes.append(4096)
    test_sizes.append(8192)
    test_sizes.append(16384)
    test_sizes.append(32768)
    test_sizes.append(65536)
    test_sizes.append(131072)
    test_sizes.append(262144)

    # --- TEST CASE 1: 2n / n ---
    log_print("=== TEST CASE 1: LARGE / SMALL DIVISION (2n / n) ===", log_file)
    var ls_results = List[Float64]()
    for i in range(len(test_sizes)):
        var divisor_size = test_sizes[i]
        var dividend_size = divisor_size * 2
        if dividend_size <= 2**18:
            var avg = benchmark_divide_at_size(
                dividend_size, divisor_size, 5, log_file
            )
            ls_results.append(avg)
        else:
            ls_results.append(0.0)
        log_print("", log_file)

    # --- TEST CASE 2: 4n / n ---
    log_print(
        "=== TEST CASE 2: VERY LARGE / SMALL DIVISION (4n / n) ===", log_file
    )
    var vls_results = List[Float64]()
    for i in range(len(test_sizes)):
        var divisor_size = test_sizes[i]
        var dividend_size = divisor_size * 4
        if dividend_size <= 2**18:
            var avg = benchmark_divide_at_size(
                dividend_size, divisor_size, 5, log_file
            )
            vls_results.append(avg)
        else:
            vls_results.append(0.0)
        log_print("", log_file)

    # --- Summary tables ---
    log_print(
        "=== SUMMARY TABLE: LARGE / SMALL DIVISION (2n / n) ===", log_file
    )
    log_print(
        "Divisor\t\tDividend\t\tTime (s)\t\tRatio to Previous",
        log_file,
    )
    log_print(
        (
            "----------------------------------------------------------------------"
            "----------"
        ),
        log_file,
    )
    for i in range(len(test_sizes)):
        var ds = test_sizes[i]
        var dd = ds * 2
        var t = ls_results[i]
        if t > 0.0:
            if i > 0 and ls_results[i - 1] > 0.0:
                var ratio = t / ls_results[i - 1]
                log_print(
                    String(ds)
                    + "\t\t"
                    + String(dd)
                    + "\t\t"
                    + String(t)
                    + "\t\t"
                    + String(ratio),
                    log_file,
                )
            else:
                log_print(
                    String(ds)
                    + "\t\t"
                    + String(dd)
                    + "\t\t"
                    + String(t)
                    + "\t\tN/A",
                    log_file,
                )

    log_print("", log_file)
    log_print(
        "=== SUMMARY TABLE: VERY LARGE / SMALL DIVISION (4n / n) ===",
        log_file,
    )
    log_print(
        "Divisor\t\tDividend\t\tTime (s)\t\tRatio to Previous",
        log_file,
    )
    log_print(
        (
            "----------------------------------------------------------------------"
            "----------"
        ),
        log_file,
    )
    for i in range(len(test_sizes)):
        var ds = test_sizes[i]
        var dd = ds * 4
        if dd <= 2**18:
            var t = vls_results[i]
            if t > 0.0:
                if i > 0 and vls_results[i - 1] > 0.0:
                    var ratio = t / vls_results[i - 1]
                    log_print(
                        String(ds)
                        + "\t\t"
                        + String(dd)
                        + "\t\t"
                        + String(t)
                        + "\t\t"
                        + String(ratio),
                        log_file,
                    )
                else:
                    log_print(
                        String(ds)
                        + "\t\t"
                        + String(dd)
                        + "\t\t"
                        + String(t)
                        + "\t\tN/A",
                        log_file,
                    )

    log_print("", log_file)
    log_print("=== ANALYSIS ===", log_file)
    log_print("Expected behavior for division algorithms:", log_file)
    log_print("- Single word divisor: O(n) where n is dividend size", log_file)
    log_print("- Double word divisor: O(n) where n is dividend size", log_file)
    log_print(
        "- General division: O(n²) where n is max(dividend, divisor) size",
        log_file,
    )
    log_print("", log_file)

    log_file.close()
    print("Division complexity benchmark completed. Log file closed.")
