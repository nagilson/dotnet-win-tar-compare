# .NET Windows TAR extraction comparison

This repository compares two extraction paths for local .NET 11 Windows TAR archives:

- `System.Formats.Tar` with `GZipStream`
- Windows inbox `tar.exe` (libarchive/bsdtar)

Archive fixtures are stored under `archives/`. Benchmark outputs are written to
`work/`, and the Markdown report is written to `results/`.

## Run

Use a .NET 11 SDK:

```powershell
.\benchmark.ps1 -DotnetPath C:\path\to\dotnet.exe -Iterations 3
```

Runs are serialized. Each extractor is measured against both the SDK and runtime
fixtures in compressed (`.tar.gz`) and uncompressed (`.tar`) form. Only the call
to `ITarArchiveExtractor.Extract` is timed. Build, download, cleanup, and extracted
layout validation are outside the measured interval.
