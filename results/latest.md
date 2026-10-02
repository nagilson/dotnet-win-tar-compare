# .NET 11 Windows TAR extraction comparison

Generated: `2026-10-02T11:36:52.6612034-07:00`

- OS: `Microsoft Windows NT 10.0.26300.0`
- Processor count: `20`
- Build SDK: `11.0.100-rc.1.26425.128`
- Iterations per case: `5`
- Warmup iterations per case: `1`
- Runs were serialized with alternating extractor order; archive download, Native AOT publish, warmup, target cleanup, and validation were excluded from timing.
- The benchmark host is a trimmed, self-contained `win-x64` Native AOT executable published in `Release` with `OptimizationPreference=Speed`.
- The .NET implementation runs `TarFile.ExtractToDirectory` and `GZipStream` in process; the Windows tar.exe (bsdtar) implementation launches the inbox `System32\tar.exe`.
- Windows tar.exe (bsdtar) measurements include child-process startup and inter-process synchronization.
- Every extraction, including compressed and uncompressed forms, is validated against the first complete path/type/size manifest for that product fixture.

## Summary

| Product | Version | Format | .NET implementation median (ms) | Windows tar.exe (bsdtar) median (ms) | Faster | Difference |
|---|---|---:|---:|---:|---|---:|
| .NET SDK | `11.0.100-rc.1.26425.128` | `tar.gz` | 10,875.8 | 3,938.2 | **Windows tar.exe (bsdtar)** | 63.8% |
| .NET SDK | `11.0.100-rc.1.26425.128` | `tar` | 10,891.6 | 2,989.2 | **Windows tar.exe (bsdtar)** | 72.6% |
| .NET Runtime | `11.0.0-rc.1.26425.128` | `tar.gz` | 656.2 | 358.6 | **Windows tar.exe (bsdtar)** | 45.4% |
| .NET Runtime | `11.0.0-rc.1.26425.128` | `tar` | 358.1 | 191.5 | **Windows tar.exe (bsdtar)** | 46.5% |

## Observations

| Sequence | Product | Format | Extractor | Iteration | Extraction time (ms) |
|---:|---|---:|---|---:|---:|
| 1 | .NET SDK | `tar.gz` | Windows tar.exe (bsdtar) | 1 | 3,945.664 |
| 2 | .NET SDK | `tar.gz` | .NET implementation | 1 | 10,875.776 |
| 3 | .NET SDK | `tar.gz` | .NET implementation | 2 | 10,785.630 |
| 4 | .NET SDK | `tar.gz` | Windows tar.exe (bsdtar) | 2 | 3,963.312 |
| 5 | .NET SDK | `tar.gz` | Windows tar.exe (bsdtar) | 3 | 3,910.193 |
| 6 | .NET SDK | `tar.gz` | .NET implementation | 3 | 10,846.250 |
| 7 | .NET SDK | `tar.gz` | .NET implementation | 4 | 11,378.662 |
| 8 | .NET SDK | `tar.gz` | Windows tar.exe (bsdtar) | 4 | 3,938.206 |
| 9 | .NET SDK | `tar.gz` | Windows tar.exe (bsdtar) | 5 | 3,877.448 |
| 10 | .NET SDK | `tar.gz` | .NET implementation | 5 | 10,884.795 |
| 11 | .NET SDK | `tar` | .NET implementation | 1 | 10,851.649 |
| 12 | .NET SDK | `tar` | Windows tar.exe (bsdtar) | 1 | 2,989.210 |
| 13 | .NET SDK | `tar` | Windows tar.exe (bsdtar) | 2 | 2,897.785 |
| 14 | .NET SDK | `tar` | .NET implementation | 2 | 10,796.862 |
| 15 | .NET SDK | `tar` | .NET implementation | 3 | 10,891.561 |
| 16 | .NET SDK | `tar` | Windows tar.exe (bsdtar) | 3 | 2,993.901 |
| 17 | .NET SDK | `tar` | Windows tar.exe (bsdtar) | 4 | 2,893.434 |
| 18 | .NET SDK | `tar` | .NET implementation | 4 | 11,216.723 |
| 19 | .NET SDK | `tar` | .NET implementation | 5 | 11,494.054 |
| 20 | .NET SDK | `tar` | Windows tar.exe (bsdtar) | 5 | 3,283.190 |
| 21 | .NET Runtime | `tar.gz` | Windows tar.exe (bsdtar) | 1 | 380.156 |
| 22 | .NET Runtime | `tar.gz` | .NET implementation | 1 | 595.833 |
| 23 | .NET Runtime | `tar.gz` | .NET implementation | 2 | 633.624 |
| 24 | .NET Runtime | `tar.gz` | Windows tar.exe (bsdtar) | 2 | 377.403 |
| 25 | .NET Runtime | `tar.gz` | Windows tar.exe (bsdtar) | 3 | 354.171 |
| 26 | .NET Runtime | `tar.gz` | .NET implementation | 3 | 656.188 |
| 27 | .NET Runtime | `tar.gz` | .NET implementation | 4 | 678.114 |
| 28 | .NET Runtime | `tar.gz` | Windows tar.exe (bsdtar) | 4 | 358.604 |
| 29 | .NET Runtime | `tar.gz` | Windows tar.exe (bsdtar) | 5 | 357.468 |
| 30 | .NET Runtime | `tar.gz` | .NET implementation | 5 | 658.423 |
| 31 | .NET Runtime | `tar` | .NET implementation | 1 | 348.184 |
| 32 | .NET Runtime | `tar` | Windows tar.exe (bsdtar) | 1 | 191.548 |
| 33 | .NET Runtime | `tar` | Windows tar.exe (bsdtar) | 2 | 190.585 |
| 34 | .NET Runtime | `tar` | .NET implementation | 2 | 358.099 |
| 35 | .NET Runtime | `tar` | .NET implementation | 3 | 361.215 |
| 36 | .NET Runtime | `tar` | Windows tar.exe (bsdtar) | 3 | 200.529 |
| 37 | .NET Runtime | `tar` | Windows tar.exe (bsdtar) | 4 | 188.271 |
| 38 | .NET Runtime | `tar` | .NET implementation | 4 | 339.574 |
| 39 | .NET Runtime | `tar` | .NET implementation | 5 | 395.047 |
| 40 | .NET Runtime | `tar` | Windows tar.exe (bsdtar) | 5 | 263.439 |

## Ranges

| Product | Format | Extractor | Minimum (ms) | Median (ms) | Maximum (ms) |
|---|---:|---|---:|---:|---:|
| .NET Runtime | `tar` | .NET implementation | 339.6 | 358.1 | 395.0 |
| .NET Runtime | `tar` | Windows tar.exe (bsdtar) | 188.3 | 191.5 | 263.4 |
| .NET Runtime | `tar.gz` | .NET implementation | 595.8 | 656.2 | 678.1 |
| .NET Runtime | `tar.gz` | Windows tar.exe (bsdtar) | 354.2 | 358.6 | 380.2 |
| .NET SDK | `tar` | .NET implementation | 10,796.9 | 10,891.6 | 11,494.1 |
| .NET SDK | `tar` | Windows tar.exe (bsdtar) | 2,893.4 | 2,989.2 | 3,283.2 |
| .NET SDK | `tar.gz` | .NET implementation | 10,785.6 | 10,875.8 | 11,378.7 |
| .NET SDK | `tar.gz` | Windows tar.exe (bsdtar) | 3,877.4 | 3,938.2 | 3,963.3 |
