# .NET Windows TAR extraction comparison

This repository compares two extraction paths for local .NET 11 Windows TAR archives:

- `System.Formats.Tar` with `GZipStream`
- Windows inbox `tar.exe` (libarchive/bsdtar)

Archive fixtures are downloaded into `archives/` from the official .NET 11
release metadata when missing. Published SHA-512 hashes are verified before
use, and matching uncompressed `.tar` files are generated locally. Benchmark
outputs are written to `work/`, and the Markdown report is written to
`results/`.

## Run

Use a .NET 11 SDK:

```powershell
.\benchmark.ps1 -DotnetPath C:\path\to\dotnet.exe -Iterations 5 -WarmupIterations 1
```

To download, verify, and decompress the fixtures without publishing or running
the benchmark:

```powershell
.\benchmark.ps1 -PrepareArchivesOnly
```

Runs are serialized. Each extractor is measured against both the SDK and runtime
fixtures in compressed (`.tar.gz`) and uncompressed (`.tar`) form. A warmup pass is
excluded from measurement, and extractor order alternates to avoid systematically
giving either implementation the colder cache. Only the call to
`ITarArchiveExtractor.Extract` is timed.

Both extractor code paths are published in `Release` with trimming and
`OptimizationPreference=Speed`, and run from the same self-contained `win-x64`
Native AOT benchmark host. The .NET implementation uses the supported
`TarFile.ExtractToDirectory` convenience API in process; the Windows tar.exe
(bsdtar) implementation launches the inbox `System32\tar.exe`. Windows tar.exe
(bsdtar) timing therefore includes child-process startup.

The script downloads or generates missing archive fixtures and publishes the
executable before running the benchmark, so required artifacts are created
automatically. Publish, download, decompression, warmup, cleanup, and extracted
layout validation are outside the measured interval. Every extraction is
checked against a complete path/type/size manifest to ensure both
implementations and both archive forms produce equivalent layouts.

See [Windows `tar.exe` vs. .NET TAR extraction hypotheses](PERFORMANCE-HYPOTHESES.md)
for a source-level comparison of the measured implementations and proposed
experiments for the performance gap.
