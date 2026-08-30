"""Benchmarks for BigUInt from_string constructor. Compares BigUInt and Python int."""

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
    print_summary,
)


def run_case(
    bc: BenchCase,
    iterations: Int,
    log_file: PythonObject,
    mut sf: List[Float64],
) raises:
    log_print("\nBenchmark:       " + bc.name, log_file)
    log_print("a: " + bc.a[byte=:80], log_file)

    var py = Python.import_module("builtins")

    try:
        var rm = BigUInt(bc.a)
        var rp = py.int(bc.a)

        var rm_str = String(rm)
        var rp_str = String(rp)

        # Correctness check: string match
        if rm_str != rp_str:
            log_print("*** WARNING: String mismatch detected! ***", log_file)
            log_print("BigUInt result:  " + rm_str[byte=:120], log_file)
            log_print("Python result:   " + rp_str[byte=:120], log_file)

        var t0 = perf_counter_ns()
        for _ in range(iterations):
            _ = BigUInt(bc.a)
        var tm = (perf_counter_ns() - t0) / UInt(iterations)
        if tm == 0:
            tm = 1

        t0 = perf_counter_ns()
        for _ in range(iterations):
            _ = py.int(bc.a)
        var tp = (perf_counter_ns() - t0) / UInt(iterations)

        var s = Float64(tp) / Float64(tm)
        sf.append(s)

        log_print("BigUInt:         " + String(tm) + " ns/iter", log_file)
        log_print("Python:          " + String(tp) + " ns/iter", log_file)
        log_print("Speedup:         " + String(s) + "×", log_file)
    except e:
        log_print("Error: " + String(e), log_file)
        log_print("Skipping this case", log_file)


def main() raises:
    var pysys = Python.import_module("sys")
    pysys.set_int_max_str_digits(10000000)

    var toml_path = "bench_data/from_string.toml"
    var log_file = open_log_file("benchmark_biguint_from_string")
    print_header("Decimo BigUInt from_string Benchmark", log_file)

    var cases = load_bench_cases(toml_path)
    var iterations = load_bench_iterations(toml_path)
    var sf = List[Float64]()

    log_print(
        "\nRunning "
        + String(len(cases))
        + " benchmarks with "
        + String(iterations)
        + " iterations each",
        log_file,
    )

    for i in range(len(cases)):
        run_case(cases[i], iterations, log_file, sf)

    print_summary(
        "BigUInt from_string Benchmark Summary",
        sf,
        "BigUInt",
        iterations,
        log_file,
    )
    log_file.close()
    print("Benchmark completed. Log file closed.")
