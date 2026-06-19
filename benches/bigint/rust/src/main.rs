// Cross-language BigInt benchmark — Rust side (num-bigint).
//
// Reads cases/<op>.toml (shared with the Mojo / Python sides), expands
// `{C,N}` repeat patterns, auto-tunes the iteration count to ~50ms per
// case, and emits one CSV record per case to stdout AND to
// `logs/rust_<op>_<ts>.csv`. Schema:
//
//     timestamp,language,op,case_name,result,ns_per_iter
//
// BigInt arithmetic is exact, so there is no precision parameter.
//
// Usage:  cargo run --release --quiet -- --op add [--cases-dir DIR]
//                                                  [--logs-dir DIR]
//
// Available ops: add, multiply, floor_divide, power, shift, sqrt,
//                from_string, to_string.

use num_bigint::BigInt;
use num_integer::Integer;
use num_traits::Pow;
use serde::Deserialize;
use std::env;
use std::fs;
use std::hint::black_box;
use std::io::Write;
use std::path::PathBuf;
use std::str::FromStr;
use std::time::Instant;

#[derive(Debug, Deserialize)]
struct Doc {
    config: Option<Config>,
    cases: Vec<Case>,
}

#[derive(Debug, Deserialize)]
struct Config {
    iterations: Option<u64>,
}

#[derive(Debug, Deserialize, Clone)]
struct Case {
    name: String,
    a: String,
    #[serde(default)]
    b: String,
}

/// Expand `{C,N}` repeat patterns. `{9,3}` → "999", `1{0,4}2` → "100002".
fn expand(s: &str) -> String {
    let mut out = String::new();
    let bytes = s.as_bytes();
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'{' {
            if let Some(close_rel) = s[i + 1..].find('}') {
                let close = i + 1 + close_rel;
                let inner = &s[i + 1..close];
                if let Some(comma) = inner.rfind(',') {
                    let payload = &inner[..comma];
                    if let Ok(n) = inner[comma + 1..].parse::<usize>() {
                        for _ in 0..n {
                            out.push_str(payload);
                        }
                        i = close + 1;
                        continue;
                    }
                }
            }
        }
        out.push(bytes[i] as char);
        i += 1;
    }
    out
}

// ----- timing config (mirrors the Mojo / Python harnesses) --------------
const TARGET_NS: u128 = 50_000_000; // 50ms per rep target
const MIN_RES_NS: u128 = 100_000; // 100µs floor per rep for resolution
const MAX_WALL_NS: u128 = 500_000_000; // 500ms total wall per case

/// Run `iters` reps of `op` on the prepared operands. The result is fed to
/// `black_box` so the optimizer cannot elide the work.
fn run_iters(op: &str, da: &BigInt, db: &BigInt, exp: u32, shift: usize, a: &str, iters: u64) {
    match op {
        "add" => {
            for _ in 0..iters {
                black_box(black_box(da) + black_box(db));
            }
        }
        "multiply" => {
            for _ in 0..iters {
                black_box(black_box(da) * black_box(db));
            }
        }
        "floor_divide" => {
            for _ in 0..iters {
                black_box(black_box(da).div_floor(black_box(db)));
            }
        }
        "power" => {
            for _ in 0..iters {
                black_box(Pow::pow(black_box(da), black_box(exp)));
            }
        }
        "shift" => {
            for _ in 0..iters {
                black_box(black_box(da) << black_box(shift));
            }
        }
        "sqrt" => {
            for _ in 0..iters {
                black_box(black_box(da).sqrt());
            }
        }
        "from_string" => {
            for _ in 0..iters {
                black_box(BigInt::from_str(black_box(a)).expect("parse"));
            }
        }
        "to_string" => {
            for _ in 0..iters {
                black_box(black_box(da).to_string());
            }
        }
        other => panic!("unknown op {other}"),
    }
}

fn compute_result(op: &str, da: &BigInt, db: &BigInt, exp: u32, shift: usize, a: &str) -> String {
    match op {
        "add" => (da + db).to_string(),
        "multiply" => (da * db).to_string(),
        "floor_divide" => da.div_floor(db).to_string(),
        "power" => Pow::pow(da, exp).to_string(),
        "shift" => (da << shift).to_string(),
        "sqrt" => da.sqrt().to_string(),
        "from_string" => BigInt::from_str(a).expect("parse").to_string(),
        "to_string" => da.to_string(),
        other => panic!("unknown op {other}"),
    }
}

fn run_op(op: &str, a: &str, b: &str, iter_hint: u64) -> (String, f64) {
    let da = BigInt::from_str(a).expect("from_str a");
    // `b` is the second operand (add/multiply/floor_divide) or a small
    // integer (power exponent / shift count). Unary ops leave it empty.
    // Fail fast on a malformed non-empty operand, consistent with `a`, so
    // bad case data cannot masquerade as a valid benchmark run.
    let db = if b.is_empty() {
        BigInt::from(0)
    } else {
        BigInt::from_str(b).expect("from_str b")
    };
    let exp: u32 = if op == "power" {
        b.parse::<u32>().expect("power exponent")
    } else {
        0
    };
    let shift: usize = if op == "shift" {
        b.parse::<usize>().expect("shift count")
    } else {
        0
    };

    // Displayed result, computed once (string form for cross-lang diff).
    let result_str = compute_result(op, &da, &db, exp, shift, a);

    // Calibrate one rep to estimate per-iter cost.
    let t0 = Instant::now();
    run_iters(op, &da, &db, exp, shift, a, 1);
    let mut cal = t0.elapsed().as_nanos();
    if cal == 0 {
        cal = 1;
    }
    let mut n = TARGET_NS / cal;
    let n_min_res = MIN_RES_NS / cal;
    if n < n_min_res {
        n = n_min_res;
    }
    if n < 3 {
        n = 3;
    }
    if n > iter_hint as u128 {
        n = iter_hint as u128;
    }
    if n < 1 {
        n = 1;
    }
    let iters = n as u64;
    let per_rep = (iters as u128) * cal;
    let reps: u32 = if per_rep > 0 {
        (MAX_WALL_NS / per_rep).clamp(1, 3) as u32
    } else {
        3
    };

    // Best-of-N timing.
    let mut best = u128::MAX;
    for _ in 0..reps {
        let t0 = Instant::now();
        run_iters(op, &da, &db, exp, shift, a, iters);
        let dt = t0.elapsed().as_nanos();
        if dt < best {
            best = dt;
        }
    }
    let per = best as f64 / iters as f64;
    (result_str, per)
}

fn main() {
    let mut op = String::from("add");
    let mut cases_dir = PathBuf::from("../cases");
    let mut logs_dir = PathBuf::from("../logs");
    let args: Vec<String> = env::args().collect();
    let mut i = 1;
    while i < args.len() {
        match args[i].as_str() {
            "--op" => {
                op = args[i + 1].clone();
                i += 2;
            }
            "--cases-dir" => {
                cases_dir = PathBuf::from(&args[i + 1]);
                i += 2;
            }
            "--logs-dir" => {
                logs_dir = PathBuf::from(&args[i + 1]);
                i += 2;
            }
            _ => i += 1,
        }
    }

    let toml_path = cases_dir.join(format!("{op}.toml"));
    let raw = fs::read_to_string(&toml_path)
        .unwrap_or_else(|e| panic!("read {}: {e}", toml_path.display()));
    let doc: Doc = toml::from_str(&raw).expect("toml parse");
    let iter_hint = doc
        .config
        .as_ref()
        .and_then(|c| c.iterations)
        .unwrap_or(1000);

    fs::create_dir_all(&logs_dir).ok();
    let ts = chrono_now();
    let log_path = logs_dir.join(format!("rust_{op}_{ts}.csv"));
    let mut log = fs::File::create(&log_path).expect("open log");
    writeln!(log, "timestamp,language,op,case_name,result,ns_per_iter").ok();

    println!("# num-bigint {} (hint={})", op, iter_hint);
    println!("{:<40} {:<32} {:>12}", "case", "result", "ns/iter");
    for case in &doc.cases {
        let a = expand(&case.a);
        let b = expand(&case.b);
        let (result, per) = run_op(&op, &a, &b, iter_hint);
        let result_short: String = result.chars().take(30).collect();
        println!("{:<40} {:<32} {:>12.3}", case.name, result_short, per);
        writeln!(
            log,
            "{},rust,{},{},{},{:.4}",
            ts,
            op,
            csv_quote(&case.name),
            csv_quote(&result),
            per
        )
        .ok();
    }
    eprintln!("wrote {}", log_path.display());
}

fn csv_quote(s: &str) -> String {
    if s.contains(',') || s.contains('"') || s.contains('\n') || s.contains('\r') {
        format!("\"{}\"", s.replace('"', "\"\""))
    } else {
        s.to_string()
    }
}

/// Tiny timestamp without pulling in chrono. Format: YYYYMMDD_HHMMSS (UTC).
fn chrono_now() -> String {
    use std::time::SystemTime;
    let secs = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    let (y, m, d, hh, mm, ss) = unix_to_ymd_hms(secs);
    format!("{:04}{:02}{:02}_{:02}{:02}{:02}", y, m, d, hh, mm, ss)
}

fn unix_to_ymd_hms(secs: u64) -> (u32, u32, u32, u32, u32, u32) {
    let days = secs / 86400;
    let rem = secs % 86400;
    let hh = (rem / 3600) as u32;
    let mm = ((rem % 3600) / 60) as u32;
    let ss = (rem % 60) as u32;

    // Civil-from-days algorithm (Howard Hinnant).
    let z = days as i64 + 719468;
    let era = (if z >= 0 { z } else { z - 146096 }) / 146097;
    let doe = (z - era * 146097) as u64;
    let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
    let y = yoe as i64 + era * 400;
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
    let mp = (5 * doy + 2) / 153;
    let d = doy - (153 * mp + 2) / 5 + 1;
    let m = if mp < 10 { mp + 3 } else { mp - 9 };
    let y = y + (if m <= 2 { 1 } else { 0 });
    (y as u32, m as u32, d as u32, hh, mm, ss)
}
