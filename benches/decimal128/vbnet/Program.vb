' Cross-language Decimal128 benchmark — VB.NET (System.Decimal) side.
'
' Mirrors csharp/Program.cs but written in Visual Basic .NET. Both target the
' same .NET runtime and the same `System.Decimal` type, so results are
' expected to be byte-identical to C#; the only thing this measures
' separately is whether the VB compiler produces a noticeably different
' codegen path for tight benchmark loops.
'
' Usage:  dotnet run -c Release -- --op add --cases-dir ../cases --logs-dir ../logs

Imports System.Diagnostics
Imports System.Globalization
Imports System.IO
Imports System.Text
Imports Tomlyn
Imports Tomlyn.Model

Namespace DecimoBench

    Module Program

        Private Const Reps As Integer = 5

        Function Main(args As String()) As Integer
            Dim op As String = "add"
            Dim casesDir As String = "../cases"
            Dim logsDir As String = "../logs"
            Dim i As Integer = 0
            While i < args.Length
                Select Case args(i)
                    Case "--op"
                        i += 1
                        op = args(i)
                    Case "--cases-dir"
                        i += 1
                        casesDir = args(i)
                    Case "--logs-dir"
                        i += 1
                        logsDir = args(i)
                End Select
                i += 1
            End While

            Dim tomlPath As String = Path.Combine(casesDir, op & ".toml")
            If Not File.Exists(tomlPath) Then
                Console.Error.WriteLine("missing case file: " & tomlPath)
                Return 2
            End If

            Dim loaded = LoadCases(tomlPath)
            Dim iterations As Integer = loaded.Item1
            Dim cases As List(Of BenchCase) = loaded.Item2

            Directory.CreateDirectory(logsDir)
            Dim ts As String = DateTime.UtcNow.ToString("yyyyMMdd_HHmmss",
                CultureInfo.InvariantCulture)
            Dim logPath As String = Path.Combine(logsDir, "vbnet_" & op & "_" & ts & ".csv")

            Console.WriteLine("# vbnet System.Decimal " & op & " (iters=" & iterations & ")")
            Console.WriteLine(String.Format("{0,-40}{1,-32}ns/iter", "case", "result"))

            Using log As New StreamWriter(logPath)
                log.WriteLine("timestamp,language,op,case_name,result,ns_per_iter")
                For Each bc In cases
                    Dim a As Decimal = ParseDec(bc.A)
                    Dim b As Decimal = If(String.IsNullOrEmpty(bc.B), 0D, ParseDec(bc.B))
                    Dim result As String = ResultFor(op, a, b, bc.A)
                    Dim ns As Double = BenchOp(op, a, b, bc.A, iterations)
                    Dim resShort As String = If(result.Length > 30, result.Substring(0, 30), result)
                    Console.WriteLine(String.Format("{0,-40}{1,-32}{2:F2}", bc.Name, resShort, ns))
                    log.WriteLine(String.Join(","c,
                        ts,
                        "vbnet",
                        op,
                        CsvQuote(bc.Name),
                        CsvQuote(result),
                        ns.ToString("F4", CultureInfo.InvariantCulture)))
                Next
            End Using
            Console.WriteLine("wrote " & logPath)
            Return 0
        End Function

        ' ---------------- Case + TOML loading ----------------

        Private Class BenchCase
            Public Name As String
            Public A As String
            Public B As String
        End Class

        Private Function LoadCases(path As String) As Tuple(Of Integer, List(Of BenchCase))
            Dim text As String = File.ReadAllText(path)
            Dim doc = Toml.Parse(text)
            Dim model As TomlTable = doc.ToModel()
            Dim iters As Integer = 1000
            ' Shared TOML cases put iteration count under [config].iterations;
            ' fall back to the root key for backward compatibility.
            Dim found As Boolean = False
            Dim cfgObj As Object = Nothing
            Dim cfgIt As Object = Nothing
            If model.TryGetValue("config", cfgObj) Then
                Dim cfg As TomlTable = TryCast(cfgObj, TomlTable)
                If cfg IsNot Nothing AndAlso cfg.TryGetValue("iterations", cfgIt) Then
                    iters = Convert.ToInt32(cfgIt, CultureInfo.InvariantCulture)
                    found = True
                End If
            End If
            If Not found Then
                Dim itObj As Object = Nothing
                If model.TryGetValue("iterations", itObj) Then
                    iters = Convert.ToInt32(itObj, CultureInfo.InvariantCulture)
                End If
            End If

            Dim list As New List(Of BenchCase)
            Dim casesObj As Object = Nothing
            If model.TryGetValue("cases", casesObj) Then
                Dim arr As TomlTableArray = TryCast(casesObj, TomlTableArray)
                If arr IsNot Nothing Then
                    For Each t In arr
                        Dim nameObj As Object = Nothing
                        Dim aObj As Object = Nothing
                        Dim bObj As Object = Nothing
                        Dim bc As New BenchCase()
                        bc.Name = If(t.TryGetValue("name", nameObj),
                            CStr(nameObj), "")
                        bc.A = Expand(If(t.TryGetValue("a", aObj),
                            CStr(aObj), ""))
                        bc.B = Expand(If(t.TryGetValue("b", bObj),
                            CStr(bObj), ""))
                        list.Add(bc)
                    Next
                End If
            End If
            Return Tuple.Create(iters, list)
        End Function

        ''' <summary>Expand `{C,N}` macros (repeat character C exactly N times).</summary>
        Private Function Expand(s As String) As String
            If String.IsNullOrEmpty(s) OrElse s.IndexOf("{"c) < 0 Then Return s
            Dim sb As New StringBuilder(s.Length)
            Dim i As Integer = 0
            While i < s.Length
                Dim c As Char = s(i)
                If c = "{"c Then
                    Dim close As Integer = s.IndexOf("}"c, i + 1)
                    If close < 0 Then
                        sb.Append(c)
                        i += 1
                        Continue While
                    End If
                    Dim spec As String = s.Substring(i + 1, close - i - 1)
                    Dim comma As Integer = spec.IndexOf(","c)
                    Dim n As Integer
                    If comma > 0 AndAlso
                       Integer.TryParse(spec.Substring(comma + 1),
                                        NumberStyles.Integer,
                                        CultureInfo.InvariantCulture, n) AndAlso
                       n >= 0 Then
                        Dim ch As String = spec.Substring(0, comma)
                        For k As Integer = 0 To n - 1
                            sb.Append(ch)
                        Next
                        i = close + 1
                        Continue While
                    End If
                    sb.Append(s, i, close - i + 1)
                    i = close + 1
                Else
                    sb.Append(c)
                    i += 1
                End If
            End While
            Return sb.ToString()
        End Function

        Private Function ParseDec(s As String) As Decimal
            Return Decimal.Parse(s, NumberStyles.Float, CultureInfo.InvariantCulture)
        End Function

        ' ---------------- Result + bench dispatch ----------------

        Private Function ResultFor(op As String, a As Decimal, b As Decimal, aStr As String) As String
            Select Case op
                Case "add" : Return (a + b).ToString(CultureInfo.InvariantCulture)
                Case "subtract" : Return (a - b).ToString(CultureInfo.InvariantCulture)
                Case "multiply" : Return (a * b).ToString(CultureInfo.InvariantCulture)
                Case "divide" : Return (a / b).ToString(CultureInfo.InvariantCulture)
                Case "comparison" : Return Decimal.Compare(a, b).ToString(CultureInfo.InvariantCulture)
                Case "from_string" : Return ParseDec(aStr).ToString(CultureInfo.InvariantCulture)
                Case "to_string" : Return a.ToString(CultureInfo.InvariantCulture)
                Case Else : Throw New ArgumentException("unknown op: " & op)
            End Select
        End Function

        Private Function BenchOp(op As String, a As Decimal, b As Decimal, aStr As String, iters As Integer) As Double
            Select Case op
                Case "add" : Return BenchAdd(a, b, iters)
                Case "subtract" : Return BenchSub(a, b, iters)
                Case "multiply" : Return BenchMul(a, b, iters)
                Case "divide" : Return BenchDiv(a, b, iters)
                Case "comparison" : Return BenchCmp(a, b, iters)
                Case "from_string" : Return BenchParse(aStr, iters)
                Case "to_string" : Return BenchToStr(a, iters)
                Case Else : Throw New ArgumentException("unknown op: " & op)
            End Select
        End Function

        Private Function BenchAdd(a As Decimal, b As Decimal, iters As Integer) As Double
            Dim best As Long = Long.MaxValue
            Dim sink As Decimal = 0D
            Dim sw As New Stopwatch()
            For rep As Integer = 0 To Reps - 1
                sw.Restart()
                Dim local As Decimal = 0D
                For i As Integer = 0 To iters - 1
                    local = a + b
                Next
                sw.Stop()
                sink = local
                If sw.ElapsedTicks < best Then best = sw.ElapsedTicks
            Next
            GC.KeepAlive(sink)
            Return CDbl(best) * 1000000000.0 / Stopwatch.Frequency / iters
        End Function

        Private Function BenchSub(a As Decimal, b As Decimal, iters As Integer) As Double
            Dim best As Long = Long.MaxValue
            Dim sink As Decimal = 0D
            Dim sw As New Stopwatch()
            For rep As Integer = 0 To Reps - 1
                sw.Restart()
                Dim local As Decimal = 0D
                For i As Integer = 0 To iters - 1
                    local = a - b
                Next
                sw.Stop()
                sink = local
                If sw.ElapsedTicks < best Then best = sw.ElapsedTicks
            Next
            GC.KeepAlive(sink)
            Return CDbl(best) * 1000000000.0 / Stopwatch.Frequency / iters
        End Function

        Private Function BenchMul(a As Decimal, b As Decimal, iters As Integer) As Double
            Dim best As Long = Long.MaxValue
            Dim sink As Decimal = 0D
            Dim sw As New Stopwatch()
            For rep As Integer = 0 To Reps - 1
                sw.Restart()
                Dim local As Decimal = 0D
                For i As Integer = 0 To iters - 1
                    local = a * b
                Next
                sw.Stop()
                sink = local
                If sw.ElapsedTicks < best Then best = sw.ElapsedTicks
            Next
            GC.KeepAlive(sink)
            Return CDbl(best) * 1000000000.0 / Stopwatch.Frequency / iters
        End Function

        Private Function BenchDiv(a As Decimal, b As Decimal, iters As Integer) As Double
            Dim best As Long = Long.MaxValue
            Dim sink As Decimal = 0D
            Dim sw As New Stopwatch()
            For rep As Integer = 0 To Reps - 1
                sw.Restart()
                Dim local As Decimal = 0D
                For i As Integer = 0 To iters - 1
                    local = a / b
                Next
                sw.Stop()
                sink = local
                If sw.ElapsedTicks < best Then best = sw.ElapsedTicks
            Next
            GC.KeepAlive(sink)
            Return CDbl(best) * 1000000000.0 / Stopwatch.Frequency / iters
        End Function

        Private Function BenchCmp(a As Decimal, b As Decimal, iters As Integer) As Double
            Dim best As Long = Long.MaxValue
            Dim sink As Integer = 0
            Dim sw As New Stopwatch()
            For rep As Integer = 0 To Reps - 1
                sw.Restart()
                Dim local As Integer = 0
                For i As Integer = 0 To iters - 1
                    local = Decimal.Compare(a, b)
                Next
                sw.Stop()
                sink = local
                If sw.ElapsedTicks < best Then best = sw.ElapsedTicks
            Next
            GC.KeepAlive(sink)
            Return CDbl(best) * 1000000000.0 / Stopwatch.Frequency / iters
        End Function

        Private Function BenchParse(s As String, iters As Integer) As Double
            Dim best As Long = Long.MaxValue
            Dim sink As Long = 0L
            Dim sw As New Stopwatch()
            For rep As Integer = 0 To Reps - 1
                sw.Restart()
                For i As Integer = 0 To iters - 1
                    Dim d As Decimal = Decimal.Parse(s, NumberStyles.Float,
                        CultureInfo.InvariantCulture)
                    sink += CLng(Decimal.GetBits(d)(0))
                Next
                sw.Stop()
                If sw.ElapsedTicks < best Then best = sw.ElapsedTicks
            Next
            GC.KeepAlive(sink)
            Return CDbl(best) * 1000000000.0 / Stopwatch.Frequency / iters
        End Function

        Private Function BenchToStr(d As Decimal, iters As Integer) As Double
            Dim best As Long = Long.MaxValue
            Dim sink As Long = 0L
            Dim sw As New Stopwatch()
            For rep As Integer = 0 To Reps - 1
                sw.Restart()
                For i As Integer = 0 To iters - 1
                    sink += d.ToString(CultureInfo.InvariantCulture).Length
                Next
                sw.Stop()
                If sw.ElapsedTicks < best Then best = sw.ElapsedTicks
            Next
            GC.KeepAlive(sink)
            Return CDbl(best) * 1000000000.0 / Stopwatch.Frequency / iters
        End Function

        ' ---------------- CSV helpers ----------------

        Private Function CsvQuote(s As String) As String
            Dim need As Boolean = False
            For Each c In s
                If c = ","c OrElse c = """"c OrElse c = vbLf OrElse c = vbCr Then
                    need = True
                    Exit For
                End If
            Next
            If Not need Then Return s
            Dim sb As New StringBuilder(s.Length + 2)
            sb.Append(""""c)
            For Each c In s
                If c = """"c Then
                    sb.Append("""""")
                Else
                    sb.Append(c)
                End If
            Next
            sb.Append(""""c)
            Return sb.ToString()
        End Function

    End Module

End Namespace
