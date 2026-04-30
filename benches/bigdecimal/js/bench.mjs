// Cross-language BigDecimal benchmark — JavaScript (decimal.js) side.
//
// Reads cases/<op>.toml, expands {C,N} repeat patterns, auto-tunes iteration
// count to ~50ms per case, and emits one CSV per case to
// logs/js_<op>_<ts>.csv. Schema (mirrors mojo/python sides):
//
//     timestamp,language,op,case_name,result,ns_per_iter
//
// Usage:  node bench.mjs --op multiply --cases-dir ../cases --logs-dir ../logs

import { readFileSync, writeFileSync, mkdirSync, existsSync } from "node:fs";
import { dirname, join } from "node:path";
import { fileURLToPath } from "node:url";
import process from "node:process";
import { performance } from "node:perf_hooks";

import Decimal from "decimal.js";
import TOML from "@iarna/toml";

const TARGET_NS = 50_000_000n;

function expand(s) {
    // Mirror Mojo/Python {C,N} repeat expansion (last comma wins).
    let out = "";
    let i = 0;
    while (i < s.length) {
        if (s[i] === "{") {
            const close = s.indexOf("}", i + 1);
            if (close < 0) {
                out += s[i++];
                continue;
            }
            const inner = s.slice(i + 1, close);
            const comma = inner.lastIndexOf(",");
            if (comma < 0) {
                out += s.slice(i, close + 1);
                i = close + 1;
                continue;
            }
            const payload = inner.slice(0, comma);
            const n = parseInt(inner.slice(comma + 1), 10);
            if (Number.isNaN(n)) {
                out += s.slice(i, close + 1);
            } else {
                out += payload.repeat(n);
            }
            i = close + 1;
        } else {
            out += s[i++];
        }
    }
    return out;
}

function csvQuote(s) {
    if (typeof s !== "string") s = String(s);
    if (s.includes(",") || s.includes('"') || s.includes("\n") || s.includes("\r")) {
        return '"' + s.replaceAll('"', '""') + '"';
    }
    return s;
}

function ts() {
    // YYYYMMDD_HHMMSS in UTC (matches mojo/rust/go sides).
    const d = new Date();
    const pad = (n) => String(n).padStart(2, "0");
    return (
        d.getUTCFullYear() +
        pad(d.getUTCMonth() + 1) +
        pad(d.getUTCDate()) +
        "_" +
        pad(d.getUTCHours()) +
        pad(d.getUTCMinutes()) +
        pad(d.getUTCSeconds())
    );
}

function makeKernel(op, a, b, precision) {
    // decimal.js precision is sig digits, set globally. Set toExpPos/toExpNeg
    // wide so toString() prefers plain decimal form (closer to Python /
    // decimo's default formatting and avoids spurious "DIFF" rows).
    Decimal.set({ precision: precision, toExpPos: 999, toExpNeg: -999 });
    const da = new Decimal(a);
    const db = b === "" ? new Decimal(0) : new Decimal(b);

    switch (op) {
        case "add": return [da.plus(db).toString(), () => da.plus(db)];
        case "subtract": return [da.minus(db).toString(), () => da.minus(db)];
        case "multiply": return [da.times(db).toString(), () => da.times(db)];
        case "divide": return [da.div(db).toString(), () => da.div(db)];
        case "comparison": {
            const c = da.cmp(db);
            return [String(c), () => da.cmp(db)];
        }
        case "from_string": return [new Decimal(a).toString(), () => new Decimal(a)];
        case "to_string": return [da.toString(), () => da.toString()];
        case "sqrt": return [da.sqrt().toString(), () => da.sqrt()];
        case "exp": return [da.exp().toString(), () => da.exp()];
        case "ln": return [da.ln().toString(), () => da.ln()];
        case "root": {
            const recip = new Decimal(1).div(db);
            return [da.pow(recip).toString(), () => da.pow(recip)];
        }
        case "round": {
            const [ndigStr, mode] = b.split("|");
            const ndigits = parseInt(ndigStr, 10);
            const rmMap = {
                ROUND_DOWN: Decimal.ROUND_DOWN,        // toward zero
                ROUND_UP: Decimal.ROUND_UP,            // away from zero
                ROUND_HALF_UP: Decimal.ROUND_HALF_UP,
                ROUND_HALF_DOWN: Decimal.ROUND_HALF_DOWN,
                ROUND_HALF_EVEN: Decimal.ROUND_HALF_EVEN,
                ROUND_CEILING: Decimal.ROUND_CEIL,
                ROUND_FLOOR: Decimal.ROUND_FLOOR,
            };
            const rm = rmMap[mode];
            // toDecimalPlaces rounds to ndigits decimal places (negative ndigits
            // rounds the integer part, which decimal.js supports via toDP-then-multiply
            // workaround). decimal.js's toDecimalPlaces accepts negative dp.
            return [da.toDecimalPlaces(ndigits, rm).toString(),
            () => da.toDecimalPlaces(ndigits, rm)];
        }
        default: throw new Error("unknown op: " + op);
    }
}

function bench(kernel, iterHint) {
    // calibrate
    let t0 = process.hrtime.bigint();
    let r = kernel();
    let cal = process.hrtime.bigint() - t0;
    if (cal === 0n) cal = 1n;
    let iters = Number(TARGET_NS / cal);
    if (iters < 3) iters = 3;
    if (iters > iterHint) iters = iterHint;
    let best = 1n << 62n;
    for (let rep = 0; rep < 3; rep++) {
        t0 = process.hrtime.bigint();
        for (let i = 0; i < iters; i++) r = kernel();
        const dt = process.hrtime.bigint() - t0;
        if (dt < best) best = dt;
    }
    return Number(best) / iters;
}

function main() {
    let op = "add";
    let casesDir = "../cases";
    let logsDir = "../logs";
    const argv = process.argv.slice(2);
    for (let i = 0; i < argv.length; i++) {
        if (argv[i] === "--op") op = argv[++i];
        else if (argv[i] === "--cases-dir") casesDir = argv[++i];
        else if (argv[i] === "--logs-dir") logsDir = argv[++i];
    }

    const tomlPath = join(casesDir, `${op}.toml`);
    const doc = TOML.parse(readFileSync(tomlPath, "utf8"));
    const cfg = doc.config || {};
    const iterHint = cfg.iterations || 1000;
    const precision = cfg.precision || 28;
    const cases = doc.cases || [];

    if (!existsSync(logsDir)) mkdirSync(logsDir, { recursive: true });
    const stamp = ts();
    const logPath = join(logsDir, `js_${op}_${stamp}.csv`);

    console.log(`# js decimal.js ${op} (prec=${precision}, hint=${iterHint})`);
    console.log("case".padEnd(44) + "result".padEnd(36) + "ns/iter");

    const lines = ["timestamp,language,op,case_name,result,ns_per_iter"];
    for (const c of cases) {
        const name = c.name;
        const a = expand(c.a);
        const b = c.b ? expand(c.b) : "";
        let result, perNs;
        try {
            const [resStr, kernel] = makeKernel(op, a, b, precision);
            result = resStr;
            perNs = bench(kernel, iterHint);
        } catch (e) {
            result = `ERR: ${e.message}`;
            perNs = 0;
        }
        const short = result.length <= 34 ? result : result.slice(0, 34);
        console.log(name.padEnd(44) + short.padEnd(36) + perNs.toFixed(2));
        lines.push(
            [stamp, "js", op, csvQuote(name), csvQuote(result), perNs.toFixed(4)].join(",")
        );
    }
    writeFileSync(logPath, lines.join("\n") + "\n");
    console.error(`wrote ${logPath}`);
}

main();
