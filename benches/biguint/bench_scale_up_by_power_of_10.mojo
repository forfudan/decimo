"""Benchmarks for BigUInt scale_up_by_power_of_10. No Python comparison (Mojo-only)."""

from std.collections import List
from std.python import Python, PythonObject
from std.time import perf_counter_ns

import decimo.biguint.arithmetics
from decimo.biguint.biguint import BigUInt
from decimo.tests import (
    BenchCase,
    load_bench_cases,
    load_bench_iterations,
    log_print,
    open_log_file,
    print_header,
)


def run_case(
    bc: BenchCase,
    iterations: Int,
    log_file: PythonObject,
    mut times: List[Float64],
) raises:
    log_print("\nBenchmark:       " + bc.name, log_file)
    log_print("a: " + bc.a[byte=:80], log_file)
    log_print("power: " + bc.b, log_file)

    var m_a = BigUInt(bc.a)
    var power = atol(bc.b)

    var t0 = perf_counter_ns()
    for _ in range(iterations):
        _ = decimo.biguint.arithmetics.multiply_by_power_of_ten(m_a, power)
    var tm = (perf_counter_ns() - t0) / UInt(iterations)
    times.append(Float64(tm))

    log_print("BigUInt:         " + String(tm) + " ns/iter", log_file)


def main() raises:
    var toml_path = "bench_data/scale_up_by_power_of_10.toml"
    var log_file = open_log_file("benchmark_biguint_scale_up")
    print_header("Decimo BigUInt scale_up_by_power_of_10 Benchmark", log_file)

    var cases = load_bench_cases(toml_path)
    var iterations = load_bench_iterations(toml_path)
    var times = List[Float64]()

    log_print(
        "\nRunning "
        + String(len(cases))
        + " benchmarks with "
        + String(iterations)
        + " iterations each",
        log_file,
    )

    for i in range(len(cases)):
        run_case(cases[i], iterations, log_file, times)

    # Summary (no speedup — Mojo-only benchmark)
    if len(times) > 0:
        var total: Float64 = 0.0
        for i in range(len(times)):
            total += times[i]
        var avg = total / Float64(len(times))

        log_print(
            "\n=== BigUInt scale_up_by_power_of_10 Benchmark Summary ===",
            log_file,
        )
        log_print(
            "Benchmarked:         " + String(len(times)) + " cases",
            log_file,
        )
        log_print(
            "Iterations per case: " + String(iterations),
            log_file,
        )
        log_print("Average time:        " + String(avg) + " ns", log_file)

        log_print("\nIndividual benchmark times:", log_file)
        for i in range(len(times)):
            log_print(
                String("Case {}: {} ns").format(i + 1, round(times[i], 2)),
                log_file,
            )

    log_file.close()
    print("Benchmark completed. Log file closed.")
