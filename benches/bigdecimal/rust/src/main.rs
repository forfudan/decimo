// Cross-language BigDecimal benchmark — Rust (bigdecimal crate) side.
//
// Reads cases/<op>.toml directly (with serde+toml), expands {C,N} repeat
// patterns, auto-tunes iter count to ~50ms per case, writes one CSV record
// per case to logs/rust_<op>_<ts>.csv. Schema:
//
//     timestamp,language,op,case_name,result,ns_per_iter
//
// Supported ops: add, subtract, multiply, divide, comparison, from_string,
//                to_string, sqrt.
// Skipped (not implemented in `bigdecimal` crate): exp, ln, root, round.
// (`bigdecimal` does have round_to_scale via `with_scale`, but the cross-
// language `round` op encodes mode information that maps awkwardly; left
// out for now.)

use bigdecimal::{BigDecimal, Context, RoundingMode};
use std::num::NonZeroU64;
use serde::Deserialize;
use std::env;
use std::fs;
use std::hint::black_box;
use std::io::Write;
use std::path::PathBuf;
use std::str::FromStr;
use std::time::Instant;

const TARGET_NS: u128 = 50_000_000;
const MIN_RES_NS: u128 = 100_000;        // 100µs floor per rep for resolution
const MAX_WALL_NS: u128 = 500_000_000;   // 500ms total wall per case

#[derive(Debug, Deserialize)]
struct Doc {
    config: Option<Config>,
    cases: Vec<Case>,
}

#[derive(Debug, Deserialize)]
struct Config {
    iterations: Option<u64>,
    precision: Option<u64>,
}

#[derive(Debug, Deserialize, Clone)]
struct Case {
    name: String,
    a: String,
    #[serde(default)]
    b: String,
}

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

fn parse_bd(s: &str, _precision: u64) -> BigDecimal {
    // Parse the raw string without pre-rounding, so arithmetic semantics
    // match Python's `decimal.Decimal(...)` (full input retained, result
    // rounded to `precision`).
    BigDecimal::from_str(s).expect("from_str")
}

fn round_at_prec(v: BigDecimal, precision: u64) -> BigDecimal {
    // bigdecimal::with_prec PADS small values up to `precision` digits;
    // we only want to ROUND values that already exceed the requested
    // precision, leaving short results alone (no trailing-zero padding).
    if v.digits() > precision {
        v.with_prec(precision)
    } else {
        v
    }
}

// Render a BigDecimal in fixed-point form (no scientific notation) so the
// string is human-readable. Cross-language equality is checked numerically
// by the aggregator, not by string equality, so we do NOT normalize here
// (trailing zeros after the decimal point carry precision information).
fn render(v: &BigDecimal) -> String {
    v.to_plain_string()
}

enum BenchResult {
    Skip(String),
    Run { result: String, per_ns: f64 },
}

fn run_op(op: &str, a_raw: &str, b_raw: &str, iter_hint: u64, precision: u64) -> BenchResult {
    let da = parse_bd(a_raw, precision);
    let db = if b_raw.is_empty() {
        BigDecimal::from(0)
    } else {
        parse_bd(b_raw, precision)
    };
    // Precision-aware context for ops that would otherwise silently use
    // the compile-time default (precision = 100). Used by divide and sqrt;
    // add/sub/mul are exact, so post-hoc rounding via round_at_prec is
    // sufficient.
    let ctx = Context::new(
        NonZeroU64::new(precision.max(1)).unwrap(),
        RoundingMode::HalfEven,
    );
    // Scale iteration cap inversely with precision: at p=100 keep the
    // configured iter_hint; at p=1000 / 10000 / 100000 divide by 10/100/1000.
    // Auto-tuner still targets ~50ms but is bounded by this cap. The
    // resolution floor below ensures cheap ops still run enough iterations
    // to be measurable even when this cap goes low.
    let iter_hint = iter_hint.max(3);

    macro_rules! timed {
        ($result_expr:expr, $kernel:expr) => {{
            let result = $result_expr;
            // calibrate
            let t0 = Instant::now();
            let _ = black_box($kernel);
            let cal = t0.elapsed().as_nanos().max(1);
            let mut iters = (TARGET_NS / cal) as u64;
            let n_min_res = (MIN_RES_NS / cal) as u64;
            if iters < n_min_res {
                iters = n_min_res;
            }
            if iters < 3 {
                iters = 3;
            }
            if iters > iter_hint {
                iters = iter_hint;
            }
            if iters < 1 {
                iters = 1;
            }
            let per_rep = (iters as u128) * cal;
            let mut reps: u32 = 3;
            if per_rep > 0 {
                let r = (MAX_WALL_NS / per_rep) as u32;
                reps = r.clamp(1, 3);
            }
            let mut best = u128::MAX;
            for _ in 0..reps {
                let t0 = Instant::now();
                for _ in 0..iters {
                    let _ = black_box($kernel);
                }
                let dt = t0.elapsed().as_nanos();
                if dt < best {
                    best = dt;
                }
            }
            BenchResult::Run {
                result,
                per_ns: best as f64 / iters as f64,
            }
        }};
    }

    match op {
        "add" => timed!(render(&round_at_prec(&da + &db, precision)), &da + &db),
        "subtract" => timed!(render(&round_at_prec(&da - &db, precision)), &da - &db),
        "multiply" => timed!(render(&round_at_prec(&da * &db, precision)), &da * &db),
        "divide" => {
            let inv = db.inverse_with_context(&ctx);
            timed!(
                render(&round_at_prec(&da * &inv, precision)),
                round_at_prec(&da * db.inverse_with_context(&ctx), precision)
            )
        }
        "comparison" => {
            let c = da.cmp(&db);
            let s = match c {
                std::cmp::Ordering::Less => "-1",
                std::cmp::Ordering::Equal => "0",
                std::cmp::Ordering::Greater => "1",
            };
            timed!(s.to_string(), da.cmp(&db))
        }
        "from_string" => timed!(
            render(&round_at_prec(parse_bd(a_raw, precision), precision)),
            round_at_prec(parse_bd(a_raw, precision), precision)
        ),
        "to_string" => timed!(
            render(&round_at_prec(da.clone(), precision)),
            round_at_prec(da.clone(), precision).to_plain_string()
        ),
        "sqrt" => match da.sqrt_with_context(&ctx) {
            Some(_) => timed!(
                render(&da.sqrt_with_context(&ctx).unwrap()),
                da.sqrt_with_context(&ctx).unwrap()
            ),
            None => BenchResult::Run { result: "ERR: sqrt(neg)".into(), per_ns: 0.0 },
        },
        "round" => {
            let parts: Vec<&str> = b_raw.splitn(2, '|').collect();
            let ndigits: i64 = parts[0].parse().unwrap_or(0);
            let mode = match parts.get(1).copied().unwrap_or("ROUND_HALF_EVEN") {
                "ROUND_DOWN" => RoundingMode::Down,
                "ROUND_UP" => RoundingMode::Up,
                "ROUND_HALF_UP" => RoundingMode::HalfUp,
                "ROUND_HALF_DOWN" => RoundingMode::HalfDown,
                "ROUND_HALF_EVEN" => RoundingMode::HalfEven,
                "ROUND_CEILING" => RoundingMode::Ceiling,
                "ROUND_FLOOR" => RoundingMode::Floor,
                other => return BenchResult::Run {
                    result: format!("ERR: bad mode {other}"), per_ns: 0.0
                },
            };
            timed!(
                render(&da.with_scale_round(ndigits, mode)),
                da.with_scale_round(ndigits, mode)
            )
        }
        "exp" | "ln" | "root" => BenchResult::Skip(op.to_string()),
        other => BenchResult::Run {
            result: format!("ERR: unknown op {other}"),
            per_ns: 0.0,
        },
    }
}

fn main() {
    let mut op = String::from("add");
    let mut cases_dir = PathBuf::from("../cases");
    let mut logs_dir = PathBuf::from("../logs");
    let mut precision_override: Option<u64> = None;
    let argv: Vec<String> = env::args().collect();
    let mut i = 1;
    while i < argv.len() {
        match argv[i].as_str() {
            "--op" => { op = argv[i + 1].clone(); i += 2; }
            "--cases-dir" => { cases_dir = PathBuf::from(&argv[i + 1]); i += 2; }
            "--logs-dir" => { logs_dir = PathBuf::from(&argv[i + 1]); i += 2; }
            "--precision" => { precision_override = Some(argv[i + 1].parse().unwrap()); i += 2; }
            _ => i += 1,
        }
    }

    let toml_path = cases_dir.join(format!("{op}.toml"));
    let raw = fs::read_to_string(&toml_path)
        .unwrap_or_else(|e| panic!("read {}: {e}", toml_path.display()));
    let doc: Doc = toml::from_str(&raw).expect("toml parse");
    let iter_hint = doc.config.as_ref()
        .and_then(|c| c.iterations).unwrap_or(1000);
    let precision = precision_override.unwrap_or_else(|| doc.config.as_ref()
        .and_then(|c| c.precision).unwrap_or(28));

    fs::create_dir_all(&logs_dir).ok();
    let ts = chrono_now();
    let log_path = logs_dir.join(format!("rust_{op}_p{precision}_{ts}.csv"));
    let mut log = fs::File::create(&log_path).expect("open log");
    writeln!(log, "timestamp,language,op,case_name,result,ns_per_iter,precision").ok();

    println!("# rust bigdecimal {op} (prec={precision}, hint={iter_hint})");
    println!("{:<44}{:<36}{:>10}", "case", "result", "ns/iter");
    for case in &doc.cases {
        let a = expand(&case.a);
        let b = expand(&case.b);
        match run_op(&op, &a, &b, iter_hint, precision) {
            BenchResult::Skip(o) => {
                eprintln!("# rust skipping op '{o}' (not in bigdecimal crate)");
                std::process::exit(0);
            }
            BenchResult::Run { result, per_ns } => {
                let short: String = result.chars().take(34).collect();
                println!("{:<44}{:<36}{:>10.2}", case.name, short, per_ns);
                writeln!(
                    log,
                    "{},rust,{},{},{},{:.4},{}",
                    ts, op, csv_quote(&case.name), csv_quote(&result), per_ns, precision
                ).ok();
            }
        }
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
