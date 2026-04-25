// Cross-language Decimal128 benchmark — Rust side.
//
// Reads cases/<op>.toml (shared with the Mojo side), expands `{C,N}` repeat
// patterns, runs `iterations` of each case, and emits one CSV record per
// case to stdout AND to `logs/rust_<op>_<ts>.csv`. Schema:
//
//     timestamp,language,op,case_name,result,ns_per_iter
//
// Usage:  cargo run --release --quiet -- --op add        [--cases-dir DIR]
//                                              --logs-dir DIR
//
// Available ops: add, subtract, multiply, divide, comparison, from_string,
//                to_string.

use rust_decimal::Decimal;
use rust_decimal::MathematicalOps;
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

fn parse_d(s: &str) -> Decimal {
    // rust_decimal's FromStr does not accept scientific notation; use the
    // dedicated entry point.
    if s.contains('e') || s.contains('E') {
        Decimal::from_scientific(s).expect("from_scientific")
    } else {
        Decimal::from_str(s).expect("from_str")
    }
}

fn run_op(op: &str, a: &str, b: &str, iters: u64) -> (String, f64) {
    // Always parse twice (avoid measuring parsing). Then run `iters` reps.
    let da = parse_d(a);
    let db = if b.is_empty() { Decimal::ZERO } else { parse_d(b) };

    // Compute the displayed result first (string form for cross-lang diff).
    let result_str = match op {
        "add" => (da + db).to_string(),
        "subtract" => (da - db).to_string(),
        "multiply" => (da * db).to_string(),
        "divide" => (da / db).to_string(),
        "comparison" => match da.cmp(&db) {
            std::cmp::Ordering::Less => "-1".into(),
            std::cmp::Ordering::Equal => "0".into(),
            std::cmp::Ordering::Greater => "1".into(),
        },
        "from_string" => parse_d(a).to_string(),
        "to_string" => da.to_string(),
        "ln" => da.ln().to_string(),
        "log10" => da.log10().to_string(),
        "exp" => da.exp().to_string(),
        other => panic!("unknown op {other}"),
    };

    // Best-of-5 timing.
    let mut best = u128::MAX;
    for _ in 0..5 {
        let t0 = Instant::now();
        match op {
            "add" => {
                let mut acc = Decimal::ZERO;
                for _ in 0..iters {
                    acc = black_box(black_box(da) + black_box(db));
                }
                black_box(acc);
            }
            "subtract" => {
                let mut acc = Decimal::ZERO;
                for _ in 0..iters {
                    acc = black_box(black_box(da) - black_box(db));
                }
                black_box(acc);
            }
            "multiply" => {
                let mut acc = Decimal::ZERO;
                for _ in 0..iters {
                    acc = black_box(black_box(da) * black_box(db));
                }
                black_box(acc);
            }
            "divide" => {
                let mut acc = Decimal::ZERO;
                for _ in 0..iters {
                    acc = black_box(black_box(da) / black_box(db));
                }
                black_box(acc);
            }
            "comparison" => {
                let mut acc: i64 = 0;
                for _ in 0..iters {
                    if black_box(da) < black_box(db) {
                        acc += 1;
                    }
                }
                black_box(acc);
            }
            "from_string" => {
                let mut acc = Decimal::ZERO;
                for _ in 0..iters {
                    acc = parse_d(black_box(a));
                }
                black_box(acc);
            }
            "to_string" => {
                let mut total: usize = 0;
                for _ in 0..iters {
                    total += black_box(da).to_string().len();
                }
                black_box(total);
            }
            "ln" => {
                let mut acc = Decimal::ZERO;
                for _ in 0..iters {
                    acc = black_box(black_box(da).ln());
                }
                black_box(acc);
            }
            "log10" => {
                let mut acc = Decimal::ZERO;
                for _ in 0..iters {
                    acc = black_box(black_box(da).log10());
                }
                black_box(acc);
            }
            "exp" => {
                let mut acc = Decimal::ZERO;
                for _ in 0..iters {
                    acc = black_box(black_box(da).exp());
                }
                black_box(acc);
            }
            _ => unreachable!(),
        }
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
    let iters = doc
        .config
        .as_ref()
        .and_then(|c| c.iterations)
        .unwrap_or(1000);

    fs::create_dir_all(&logs_dir).ok();
    let ts = chrono_now();
    let log_path = logs_dir.join(format!("rust_{op}_{ts}.csv"));
    let mut log = fs::File::create(&log_path).expect("open log");
    writeln!(log, "timestamp,language,op,case_name,result,ns_per_iter").ok();

    println!("# rust_decimal {} (iters={})", op, iters);
    println!("{:<40} {:<32} {:>12}", "case", "result", "ns/iter");
    for case in &doc.cases {
        let a = expand(&case.a);
        let b = expand(&case.b);
        let (result, per) = run_op(&op, &a, &b, iters);
        let result_short: String = result.chars().take(30).collect();
        println!("{:<40} {:<32} {:>12.3}", case.name, result_short, per);
        writeln!(
            log,
            "{},rust,{},{},{},{:.3}",
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

/// Tiny timestamp without pulling in chrono. Format: YYYYMMDD_HHMMSS.
fn chrono_now() -> String {
    use std::time::SystemTime;
    let secs = SystemTime::now()
        .duration_since(SystemTime::UNIX_EPOCH)
        .unwrap()
        .as_secs();
    // Convert to local-ish time using std (UTC actually — fine for filenames).
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
