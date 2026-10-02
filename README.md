# .NET Windows TAR extraction comparison

This repository compares two extraction paths for local .NET 11 Windows TAR archives:

- `System.Formats.Tar` with `GZipStream`
- Windows inbox `tar.exe` (libarchive/bsdtar)

The benchmark performs extraction only. It does not run dotnetup installation,
manifest, download, signature, cache, component tracking, or muxer logic.

Archive fixtures are stored under `archives/`. Benchmark outputs are written to
`work/`, and the Markdown report is written to `results/`.

