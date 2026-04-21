// Cross-language Decimal128 benchmark — C# (System.Decimal) side.
//
// Reads cases/<op>.toml (shared with the Rust + Mojo sides), expands `{C,N}`
// repeat patterns, runs `iterations` of each case, and emits one CSV record
// per case to stdout AND to logs/csharp_<op>_<ts>.csv.
//
// Schema (mirrors rust/src/main.rs):
//
//     timestamp,language,op,case_name,result,ns_per_iter
//
// Usage:  dotnet run -c Release -- --op add --cases-dir ../cases --logs-dir ../logs
//
// Available ops: add, subtract, multiply, divide, comparison, from_string,
//                to_string.

using System.Diagnostics;
using System.Globalization;
using System.Runtime.CompilerServices;
using System.Text;
using Tomlyn;
using Tomlyn.Model;

namespace DecimoBench;

internal static class Program
{
    private static int Main(string[] args)
    {
        string op = "add";
        string casesDir = "../cases";
        string logsDir = "../logs";
        for (int i = 0; i < args.Length; i++)
        {
            switch (args[i])
            {
                case "--op": op = args[++i]; break;
                case "--cases-dir": casesDir = args[++i]; break;
                case "--logs-dir": logsDir = args[++i]; break;
            }
        }

        var tomlPath = Path.Combine(casesDir, $"{op}.toml");
        if (!File.Exists(tomlPath))
        {
            Console.Error.WriteLine($"missing case file: {tomlPath}");
            return 2;
        }
        var (iterations, cases) = LoadCases(tomlPath);

        Directory.CreateDirectory(logsDir);
        var ts = DateTime.UtcNow.ToString("yyyyMMdd_HHmmss", CultureInfo.InvariantCulture);
        var logPath = Path.Combine(logsDir, $"csharp_{op}_{ts}.csv");

        Console.WriteLine($"# csharp System.Decimal {op} (iters={iterations})");
        Console.WriteLine($"{"case",-40}{"result",-32}ns/iter");

        using var log = new StreamWriter(logPath);
        log.WriteLine("timestamp,language,op,case_name,result,ns_per_iter");

        foreach (var bc in cases)
        {
            decimal a = ParseDecimal(bc.A);
            decimal b = string.IsNullOrEmpty(bc.B) ? 0m : ParseDecimal(bc.B);
            string result = ResultFor(op, a, b, bc.A);
            double nsPerIter = BenchOp(op, a, b, bc.A, iterations);

            string resShort = result.Length > 30 ? result[..30] : result;
            Console.WriteLine($"{bc.Name,-40}{resShort,-32}{nsPerIter:F2}");

            log.WriteLine(string.Join(",",
                ts,
                "csharp",
                op,
                CsvQuote(bc.Name),
                CsvQuote(result),
                nsPerIter.ToString("F4", CultureInfo.InvariantCulture)));
        }
        Console.WriteLine($"wrote {logPath}");
        return 0;
    }

    // ---------------- TOML loading + {C,N} pattern expansion ----------------

    internal sealed record Case(string Name, string A, string B);

    private static (int iters, List<Case> cases) LoadCases(string path)
    {
        var text = File.ReadAllText(path);
        var doc = Toml.Parse(text);
        var model = doc.ToModel();
        int iters = 1000;
        // Shared TOML cases put iteration count under [config].iterations;
        // fall back to the root key for backward compatibility.
        if (model.TryGetValue("config", out var cfgObj) && cfgObj is TomlTable cfg
            && cfg.TryGetValue("iterations", out var cfgIt))
            iters = Convert.ToInt32(cfgIt, CultureInfo.InvariantCulture);
        else if (model.TryGetValue("iterations", out var itObj))
            iters = Convert.ToInt32(itObj, CultureInfo.InvariantCulture);

        var list = new List<Case>();
        if (model.TryGetValue("cases", out var casesObj) && casesObj is TomlTableArray arr)
        {
            foreach (var t in arr)
            {
                string name = t.TryGetValue("name", out var n) ? (string)n : "";
                string a = Expand(t.TryGetValue("a", out var av) ? (string)av : "");
                string b = Expand(t.TryGetValue("b", out var bv) ? (string)bv : "");
                list.Add(new Case(name, a, b));
            }
        }
        return (iters, list);
    }

    /// <summary>Expand `{C,N}` macros (repeat character C exactly N times).</summary>
    private static string Expand(string s)
    {
        if (string.IsNullOrEmpty(s) || !s.Contains('{')) return s;
        var sb = new StringBuilder(s.Length);
        int i = 0;
        while (i < s.Length)
        {
            char c = s[i];
            if (c == '{')
            {
                int close = s.IndexOf('}', i + 1);
                if (close < 0) { sb.Append(c); i++; continue; }
                var spec = s.AsSpan(i + 1, close - i - 1);
                int comma = spec.IndexOf(',');
                if (comma > 0
                    && int.TryParse(spec[(comma + 1)..], NumberStyles.Integer,
                                    CultureInfo.InvariantCulture, out var n)
                    && n >= 0)
                {
                    var ch = spec[..comma];
                    for (int k = 0; k < n; k++) sb.Append(ch);
                    i = close + 1;
                    continue;
                }
                sb.Append(s, i, close - i + 1);
                i = close + 1;
            }
            else
            {
                sb.Append(c);
                i++;
            }
        }
        return sb.ToString();
    }

    private static decimal ParseDecimal(string s) =>
        decimal.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture);

    // ---------------- result + bench dispatch ----------------

    private static string ResultFor(string op, decimal a, decimal b, string aStr) => op switch
    {
        "add" => (a + b).ToString(CultureInfo.InvariantCulture),
        "subtract" => (a - b).ToString(CultureInfo.InvariantCulture),
        "multiply" => (a * b).ToString(CultureInfo.InvariantCulture),
        "divide" => (a / b).ToString(CultureInfo.InvariantCulture),
        "comparison" => decimal.Compare(a, b)
            .ToString(CultureInfo.InvariantCulture)
            // Map .NET's {-1,0,1} to a normalized form (already is).
            ,
        "from_string" => ParseDecimal(aStr).ToString(CultureInfo.InvariantCulture),
        "to_string" => a.ToString(CultureInfo.InvariantCulture),
        _ => throw new ArgumentException($"unknown op: {op}"),
    };

    private const int Reps = 5;

    private static double BenchOp(string op, decimal a, decimal b, string aStr, int iters)
    {
        return op switch
        {
            "add" => BenchBinary(a, b, iters, static (x, y) => x + y),
            "subtract" => BenchBinary(a, b, iters, static (x, y) => x - y),
            "multiply" => BenchBinary(a, b, iters, static (x, y) => x * y),
            "divide" => BenchBinary(a, b, iters, static (x, y) => x / y),
            "comparison" => BenchCompare(a, b, iters),
            "from_string" => BenchParse(aStr, iters),
            "to_string" => BenchToString(a, iters),
            _ => throw new ArgumentException($"unknown op: {op}"),
        };
    }

    private static double BenchBinary(decimal a, decimal b, int iters,
                                      Func<decimal, decimal, decimal> body)
    {
        long best = long.MaxValue;
        decimal sink = 0m;
        var sw = new Stopwatch();
        for (int rep = 0; rep < Reps; rep++)
        {
            sw.Restart();
            decimal local = 0m;
            for (int i = 0; i < iters; i++)
                local = body(a, b);
            sw.Stop();
            sink = local;
            if (sw.ElapsedTicks < best) best = sw.ElapsedTicks;
        }
        GC.KeepAlive(sink);
        double ns = (double)best * 1_000_000_000.0 / Stopwatch.Frequency;
        return ns / iters;
    }

    private static double BenchCompare(decimal a, decimal b, int iters)
    {
        long best = long.MaxValue;
        int sink = 0;
        var sw = new Stopwatch();
        for (int rep = 0; rep < Reps; rep++)
        {
            sw.Restart();
            int local = 0;
            for (int i = 0; i < iters; i++)
                local = decimal.Compare(a, b);
            sw.Stop();
            sink = local;
            if (sw.ElapsedTicks < best) best = sw.ElapsedTicks;
        }
        GC.KeepAlive(sink);
        double ns = (double)best * 1_000_000_000.0 / Stopwatch.Frequency;
        return ns / iters;
    }

    private static double BenchParse(string s, int iters)
    {
        long best = long.MaxValue;
        long sink = 0;
        var sw = new Stopwatch();
        for (int rep = 0; rep < Reps; rep++)
        {
            sw.Restart();
            for (int i = 0; i < iters; i++)
            {
                var d = decimal.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture);
                sink += unchecked((long)decimal.GetBits(d)[0]);
            }
            sw.Stop();
            if (sw.ElapsedTicks < best) best = sw.ElapsedTicks;
        }
        GC.KeepAlive(sink);
        double ns = (double)best * 1_000_000_000.0 / Stopwatch.Frequency;
        return ns / iters;
    }

    private static double BenchToString(decimal d, int iters)
    {
        long best = long.MaxValue;
        long sink = 0;
        var sw = new Stopwatch();
        for (int rep = 0; rep < Reps; rep++)
        {
            sw.Restart();
            for (int i = 0; i < iters; i++)
                sink += d.ToString(CultureInfo.InvariantCulture).Length;
            sw.Stop();
            if (sw.ElapsedTicks < best) best = sw.ElapsedTicks;
        }
        GC.KeepAlive(sink);
        double ns = (double)best * 1_000_000_000.0 / Stopwatch.Frequency;
        return ns / iters;
    }

    // ---------------- CSV helpers ----------------

    private static string CsvQuote(string s)
    {
        bool need = false;
        foreach (var c in s) { if (c == ',' || c == '"' || c == '\n' || c == '\r') { need = true; break; } }
        if (!need) return s;
        var sb = new StringBuilder(s.Length + 2);
        sb.Append('"');
        foreach (var c in s) { if (c == '"') sb.Append("\"\""); else sb.Append(c); }
        sb.Append('"');
        return sb.ToString();
    }
}
