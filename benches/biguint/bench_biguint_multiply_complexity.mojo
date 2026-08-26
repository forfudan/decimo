"""Benchmark for BigUInt multiplication time complexity analysis.

Tests word sizes from 8 to 262144 words (powers of 2), which spans all
four multiplication tiers.
Cases are generated programmatically — no TOML data file.
"""

from std.time import perf_counter_ns
from decimo import BigUInt
from decimo.biguint.arithmetics import multiply
from decimo.tests import open_log_file, log_print, print_header
from std.python import Python, PythonObject
from std.collections import List


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


def benchmark_multiply_at_size(
    num_words: Int, iterations: Int, log_file: PythonObject
) raises -> Float64:
    """Benchmarks multiplication for a specific word size."""
    log_print("Testing " + String(num_words) + " words...", log_file)

    var x = create_test_biguint(num_words)
    var y = create_test_biguint(num_words)
    var total_time: Float64 = 0.0

    for i in range(iterations):
        var start = perf_counter_ns()
        var _result = multiply(x, y)
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
        + String(num_words)
        + " words: "
        + String(avg)
        + " seconds",
        log_file,
    )
    return avg


def main() raises:
    var log_file = open_log_file("benchmark_multiply_complexity")
    print_header(
        "Decimo BigUInt Multiplication Time Complexity Benchmark", log_file
    )

    log_print("", log_file)
    log_print(
        "Testing word sizes from 8 to 262144 words (powers of 2)", log_file
    )
    log_print("Each test uses 5 iterations for averaging", log_file)
    log_print(
        "WARNING: Larger sizes (>100K words) may take significant time!",
        log_file,
    )
    log_print("", log_file)

    var test_sizes = List[Int]()
    test_sizes.append(8)
    test_sizes.append(16)
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

    var results = List[Float64]()

    for i in range(len(test_sizes)):
        var avg = benchmark_multiply_at_size(test_sizes[i], 5, log_file)
        results.append(avg)
        log_print("", log_file)

    # Summary table
    log_print("=== SUMMARY TABLE ===", log_file)
    log_print(
        "Words\t\tTime (s)\t\tRatio to Previous\tTheoretical O(n^1.585)",
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
        var size = test_sizes[i]
        var t = results[i]
        if i > 0:
            var prev = results[i - 1]
            var ratio = t / prev
            var size_ratio = Float64(size) / Float64(test_sizes[i - 1])
            var theoretical = size_ratio**1.585
            log_print(
                String(size)
                + "\t\t"
                + String(t)
                + "\t\t"
                + String(ratio)
                + "\t\t"
                + String(theoretical),
                log_file,
            )
        else:
            log_print(
                String(size) + "\t\t" + String(t) + "\t\tN/A\t\t\tN/A",
                log_file,
            )

    log_print("", log_file)
    log_print("=== ANALYSIS ===", log_file)
    log_print("Expected behavior, by the cutoffs in the source:", log_file)
    log_print("- <=  256 words (CUTOFF_KARATSUBA): schoolbook O(n^2)", log_file)
    log_print(
        "- <=  768 words (CUTOFF_TOOM3):     Karatsuba  O(n^1.585)", log_file
    )
    log_print(
        "- <= 2048 words (CUTOFF_NTT):       Toom-3     O(n^1.465)", log_file
    )
    log_print(
        "- above that:                       transform  O(n log n)", log_file
    )
    log_print("", log_file)
    log_print(
        "Each row doubles the word count, so the ratio to the row above says",
        log_file,
    )
    log_print("which tier is in force:", log_file)
    log_print("  ~4.0 -> O(n^2)      schoolbook", log_file)
    log_print("  ~3.0 -> O(n^1.585)  Karatsuba", log_file)
    log_print("  ~2.8 -> O(n^1.465)  Toom-3", log_file)
    log_print("  ~2.1 -> O(n log n)  number-theoretic transform", log_file)
    log_print("", log_file)

    # Statistics
    var max_ratio: Float64 = 0.0
    var min_ratio: Float64 = 1000.0
    var avg_ratio: Float64 = 0.0
    var count: Int = 0
    for i in range(1, len(results)):
        var ratio = results[i] / results[i - 1]
        if ratio > max_ratio:
            max_ratio = ratio
        if ratio < min_ratio:
            min_ratio = ratio
        avg_ratio += ratio
        count += 1
    avg_ratio = avg_ratio / Float64(count)

    log_print("Performance statistics:", log_file)
    log_print("- Maximum ratio: " + String(max_ratio), log_file)
    log_print("- Minimum ratio: " + String(min_ratio), log_file)
    log_print("- Average ratio: " + String(avg_ratio), log_file)
    log_print("", log_file)

    log_file.close()
    print("Multiplication complexity benchmark completed. Log file closed.")
