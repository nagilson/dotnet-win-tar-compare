# .NET 11 Windows TAR extraction comparison

Generated: `2026-10-02T11:20:06.1415041-07:00`

- OS: `Microsoft Windows NT 10.0.26300.0`
- Processor count: `20`
- Iterations per case: `3`
- Runs were serialized; archive download, build, target cleanup, and validation were excluded from timing.
- Managed extraction uses `System.Formats.Tar` and `GZipStream`; native extraction uses Windows `tar.exe` from `PATH`.

## Summary

| Product | Version | Format | Managed median (ms) | Native median (ms) | Faster | Difference |
|---|---|---:|---:|---:|---|---:|
| .NET SDK | `11.0.100-rc.1.26425.128` | `tar.gz` | 7,833.5 | 3,496.6 | **Native** | 55.4% |
| .NET SDK | `11.0.100-rc.1.26425.128` | `tar` | 6,875.3 | 2,466.2 | **Native** | 64.1% |
| .NET Runtime | `11.0.0-rc.1.26425.128` | `tar.gz` | 516.5 | 341.4 | **Native** | 33.9% |
| .NET Runtime | `11.0.0-rc.1.26425.128` | `tar` | 248.6 | 181.3 | **Native** | 27.1% |

## Observations

| Product | Format | Extractor | Iteration | Extraction time (ms) |
|---|---:|---|---:|---:|
| .NET SDK | `tar.gz` | managed | 1 | 9,954.704 |
| .NET SDK | `tar.gz` | managed | 2 | 7,367.382 |
| .NET SDK | `tar.gz` | managed | 3 | 7,833.531 |
| .NET SDK | `tar.gz` | native | 1 | 3,603.107 |
| .NET SDK | `tar.gz` | native | 2 | 3,469.852 |
| .NET SDK | `tar.gz` | native | 3 | 3,496.627 |
| .NET SDK | `tar` | managed | 1 | 6,875.273 |
| .NET SDK | `tar` | managed | 2 | 7,158.017 |
| .NET SDK | `tar` | managed | 3 | 6,787.626 |
| .NET SDK | `tar` | native | 1 | 2,514.867 |
| .NET SDK | `tar` | native | 2 | 2,401.393 |
| .NET SDK | `tar` | native | 3 | 2,466.151 |
| .NET Runtime | `tar.gz` | managed | 1 | 504.260 |
| .NET Runtime | `tar.gz` | managed | 2 | 516.461 |
| .NET Runtime | `tar.gz` | managed | 3 | 525.861 |
| .NET Runtime | `tar.gz` | native | 1 | 336.399 |
| .NET Runtime | `tar.gz` | native | 2 | 341.402 |
| .NET Runtime | `tar.gz` | native | 3 | 363.833 |
| .NET Runtime | `tar` | managed | 1 | 248.578 |
| .NET Runtime | `tar` | managed | 2 | 247.464 |
| .NET Runtime | `tar` | managed | 3 | 262.968 |
| .NET Runtime | `tar` | native | 1 | 172.262 |
| .NET Runtime | `tar` | native | 2 | 181.319 |
| .NET Runtime | `tar` | native | 3 | 183.537 |

## Ranges

| Product | Format | Extractor | Minimum (ms) | Median (ms) | Maximum (ms) |
|---|---:|---|---:|---:|---:|
| .NET Runtime | `tar` | managed | 247.5 | 248.6 | 263.0 |
| .NET Runtime | `tar` | native | 172.3 | 181.3 | 183.5 |
| .NET Runtime | `tar.gz` | managed | 504.3 | 516.5 | 525.9 |
| .NET Runtime | `tar.gz` | native | 336.4 | 341.4 | 363.8 |
| .NET SDK | `tar` | managed | 6,787.6 | 6,875.3 | 7,158.0 |
| .NET SDK | `tar` | native | 2,401.4 | 2,466.2 | 2,514.9 |
| .NET SDK | `tar.gz` | managed | 7,367.4 | 7,833.5 | 9,954.7 |
| .NET SDK | `tar.gz` | native | 3,469.9 | 3,496.6 | 3,603.1 |
