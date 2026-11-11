using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using Microsoft.CodeAnalysis;
using Microsoft.CodeAnalysis.Text;

namespace SourceGen;

/// AdditionalFiles 의 명세(.xml)와 생성기(.lisp)가 바뀔 때마다 `dotnet dotcl main.lisp <명세> <UiTarget>` 을 돌린다
[Generator]
public sealed class UiGenerator : IIncrementalGenerator
{
    static readonly DiagnosticDescriptor SpecError = new("UI0001", "UI 명세 오류", "{0}", "Ui", DiagnosticSeverity.Error, true);
    static readonly DiagnosticDescriptor RunError = new("UI0002", "UI 생성기 실행 실패", "{0}", "Ui", DiagnosticSeverity.Error, true);

    public void Initialize(IncrementalGeneratorInitializationContext context)
    {
        // (명세 경로, main.lisp 경로, 내용 지문) — 문자열이라 값으로 견주어져, 내용이 그대로면 다시 돌지 않는다
        var input = context.AdditionalTextsProvider
            .Where(f => f.Path.EndsWith(".xml") || f.Path.EndsWith(".lisp"))
            .Select((f, cancel) => (f.Path, Text: f.GetText(cancel)?.ToString() ?? ""))
            .Collect()
            .Select((files, _) => (
                Spec: files.FirstOrDefault(f => f.Path.EndsWith(".xml")).Path ?? "",
                Main: files.FirstOrDefault(f => Path.GetFileName(f.Path) == "main.lisp").Path ?? "",
                Print: string.Join("|", files.OrderBy(f => f.Path).Select(f => f.Path + ":" + f.Text.Length + ":" + f.Text.GetHashCode()))));
        var target = context.AnalyzerConfigOptionsProvider
            .Select((options, _) => options.GlobalOptions.TryGetValue("build_property.UiTarget", out var t) ? t : "");

        context.RegisterSourceOutput(input.Combine(target), (output, pair) =>
        {
            var ((spec, main, _), uiTarget) = pair;
            if (spec == "" || main == "" || uiTarget == "")
            {
                output.ReportDiagnostic(Diagnostic.Create(RunError, Location.None, "AdditionalFiles 에 명세(.xml) · gen/main.lisp 가, 속성에 UiTarget 이 있어야 한다"));
                return;
            }
            var (exit, source, errors) = Run(main, spec, uiTarget);
            var reported = false;
            foreach (var line in errors.Split('\n'))
            {
                // 생성기가 찍는 꼴: 파일(줄) : error UI0001: 내용
                var m = Regex.Match(line.TrimEnd(), @"^(?<file>.+?)(\((?<line>\d+)\))? : error \w+: (?<message>.*)$");
                if (!m.Success) continue;
                var at = m.Groups["line"].Success ? int.Parse(m.Groups["line"].Value) - 1 : 0;
                var position = new LinePosition(at, 0);
                output.ReportDiagnostic(Diagnostic.Create(SpecError,
                    Location.Create(m.Groups["file"].Value, new TextSpan(0, 0), new LinePositionSpan(position, position)),
                    m.Groups["message"].Value));
                reported = true;
            }
            if (exit != 0 && !reported)
                output.ReportDiagnostic(Diagnostic.Create(RunError, Location.None,
                    $"dotnet dotcl 이 {exit} 로 끝났다 — `dotnet tool restore` 를 했는지: {errors.Trim()}"));
            if (exit == 0)
                output.AddSource("Ui.g.cs", SourceText.From(source, Encoding.UTF8));
        });
    }

    // 소스 생성기에서 프로세스를 띄우는 건 권장되지 않는 우회다(RS1035) — 생성기를 Lisp 로 두려고 감수한다
#pragma warning disable RS1035
    static (int Exit, string Output, string Errors) Run(string main, string spec, string target)
    {
        try
        {
            var start = new ProcessStartInfo(Environment.GetEnvironmentVariable("DOTNET_HOST_PATH") ?? "dotnet",
                $"dotcl \"{main}\" \"{spec}\" {target}")
            {
                // 여기서 위로 올라가며 dotnet-tools.json 을 찾는다
                WorkingDirectory = Path.GetDirectoryName(main),
                RedirectStandardOutput = true,
                RedirectStandardError = true,
                StandardOutputEncoding = Encoding.UTF8,
                StandardErrorEncoding = Encoding.UTF8,
                UseShellExecute = false,
                CreateNoWindow = true,
            };
            using var process = Process.Start(start)!;
            var errors = process.StandardError.ReadToEndAsync();
            var output = process.StandardOutput.ReadToEnd();
            process.WaitForExit();
            return (process.ExitCode, output, errors.Result);
        }
        catch (Exception e)
        {
            return (-1, "", e.Message);
        }
    }
#pragma warning restore RS1035
}
