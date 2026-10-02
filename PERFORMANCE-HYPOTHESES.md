# Windows `tar.exe` vs. .NET TAR extraction hypotheses

This document compares the source paths used by the benchmark and records
testable hypotheses for why .NET TAR extraction is slower than Windows inbox
`tar.exe`. These are source-informed hypotheses, not confirmed root causes.
They should be validated with controlled experiments and Windows File I/O
traces before proposing runtime changes.

## Compared implementations

### .NET

The benchmark's .NET implementation calls `TarFile.ExtractToDirectory` from
[`DotnetTarArchiveExtractor`](src/DotnetWinTarCompare/DotnetTarArchiveExtractor.cs).
The measured runtime fixture contains:

- `System.Formats.Tar.dll` product version
  `11.0.0-rc.1.26425.128+3551975be08744f0418857c5bed8ab1545c5dd47`
- The embedded commit is the
  [dotnet/dotnet VMR commit `3551975b`](https://github.com/dotnet/dotnet/commit/3551975be08744f0418857c5bed8ab1545c5dd47).
- The runtime sources below are pinned to that exact VMR commit under
  `src/runtime`.

The relevant pipeline is:

1. [`TarFile.ExtractToDirectoryInternal`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarFile.cs#L647-L668)
   creates a `TarReader`, reads entries sequentially, and calls
   `TarEntry.ExtractRelativeToDirectory`.
2. [`TarEntry.ExtractRelativeToDirectory`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L321-L360)
   computes safe destination paths, creates the destination or parent
   directory, and extracts the entry.
3. [`GetDestinationAndLinkPaths` and `FilePathEscapesDirectory`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L363-L475)
   sanitize, normalize, contain, and physically resolve paths.
4. [`VerifyDestinationPath` and `ExtractAsRegularFile`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L636-L742)
   probe the destination, create a `FileStream`, copy data, close the stream,
   and then restore the last-write time.

### Windows inbox `tar.exe`

[Microsoft documents](https://learn.microsoft.com/windows/tar/) that Windows
`tar.exe` is based on libarchive's `bsdtar`.

The libarchive source links below use the signed
[`v3.8.9` release](https://github.com/libarchive/libarchive/releases/tag/v3.8.9)
as the public reference implementation.
Libarchive uses a
[permissive BSD-style license](https://github.com/libarchive/libarchive/blob/v3.8.9/COPYING).

The relevant pipeline is:

1. [`bsdtar` creates one reusable disk writer](https://github.com/libarchive/libarchive/blob/v3.8.9/tar/read.c#L80-L94).
2. [`bsdtar` passes each entry to `archive_read_extract2`](https://github.com/libarchive/libarchive/blob/v3.8.9/tar/read.c#L350-L366).
3. [`archive_read_extract2`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_read_extract2.c#L68-L101)
   writes the entry header, streams data blocks to the disk writer, and
   finishes entry metadata.
4. The Windows disk writer
   [`archive_write_disk_windows.c`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c)
   maintains extraction state and an open Win32 file handle.

Microsoft may apply downstream patches or different build options. The
upstream release is therefore an implementation reference, not a reproducible
source claim for the installed Windows binary.

## Benchmark evidence

The current measurements are in [`results/latest.md`](results/latest.md).
For uncompressed TAR extraction:

| Fixture | Entries | File content | .NET implementation median | Windows tar.exe (bsdtar) median | .NET implementation time per entry |
|---|---:|---:|---:|---:|---:|
| .NET SDK | 6,249 | about 692.8 MB | 10,891.6 ms | 2,989.2 ms | 1.74 ms |
| .NET Runtime | 209 | about 82.9 MB | 358.1 ms | 191.5 ms | 1.71 ms |

The SDK archive contains 5,458 regular files:

- 1,502 are smaller than 4 KB.
- 4,305 are smaller than 64 KB.

The nearly constant .NET implementation time per entry, despite very different archive
sizes and file-size distributions, points toward fixed per-entry filesystem
and path-validation work. The SDK's .NET implementation compressed and uncompressed times
are also almost identical, which makes gzip decompression an unlikely primary
bottleneck for that fixture.

## Hypothesis 1: repeated physical path and symlink validation

**Confidence: high. Expected impact: high for deep archives with many entries.**

.NET performs containment and symlink checks independently for every entry:

- It calls `Path.GetFullPath` for the logical destination.
- It resolves the physical extraction root.
- It splits the relative entry path into components.
- For every component, it creates a `FileInfo`, reads `LinkTarget`, possibly
  resolves the final target, and normalizes the resulting path again.

See:

- [`GetDestinationAndLinkPaths`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L363-L421)
- [`FilePathEscapesDirectory`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L423-L475)
- [`ResolveSymlink` and `ResolvePhysicalPath`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L477-L516)

`bsdtar` also enables secure symlink and `..` protections by default:

- [`SECURITY` flags](https://github.com/libarchive/libarchive/blob/v3.8.9/tar/bsdtar.c#L110-L114)
- [Default extraction flags](https://github.com/libarchive/libarchive/blob/v3.8.9/tar/bsdtar.c#L232-L237)

The important implementation difference is that libarchive can cache verified
path prefixes. The Windows disk writer in libarchive 3.8.9
[`checks only the portion after the cached safe prefix`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c#L2124-L2251),
[`records the verified portion for the next entry`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c#L2254-L2275),
and
[`invalidates the cache before creating a symbolic link`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c#L1780-L1785).
TAR archives are commonly ordered by directory, so adjacent entries often
share most path components and can benefit from this approach.

**Experiment:** Add a correctness-preserving cache of verified physical
directory prefixes to a private runtime build, invalidating it whenever an
archive operation can change the validity of a cached prefix. Compare SDK
extraction and count path metadata operations with ETW.

## Hypothesis 2: unconditional parent-directory creation

**Confidence: high. Expected impact: high for archives with many files.**

For every non-directory entry, .NET calls:

```csharp
TarHelpers.CreateDirectory(Path.GetDirectoryName(destinationFullPath)!, ...);
```

See
[`TarEntry.ExtractRelativeToDirectory`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L321-L360).
On Windows, the helper directly calls
[`Directory.CreateDirectory`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarHelpers.Windows.cs#L13-L17).

For the SDK fixture, this can repeat an already-satisfied directory operation
for each of 5,458 files.

Libarchive's
[`restore_entry`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c#L1412-L1477)
tries to create the filesystem object first. It invokes recursive parent
creation only when creation fails with `ENOENT` or `ENOTDIR`.

**Experiment:** Cache successfully created parent directories, invalidating
entries when archive operations can replace a directory or link. A
fixture-specific diagnostic can first skip redundant calls for known
well-formed archives, but a runtime fix must retain arbitrary entry ordering
and link safety.

## Hypothesis 3: destination probes before `CREATE_NEW`

**Confidence: high that the extra operations exist; impact requires tracing.**

.NET's
[`VerifyDestinationPath`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L636-L665):

1. Calls `Path.Exists` on the parent.
2. Calls `Path.Exists` on the destination.
3. May call `Directory.Exists`.
4. Deletes an existing destination when overwrite is enabled.
5. Later opens the file with `FileMode.CreateNew`.

On the benchmark's empty destination, the normal case is a negative existence
probe followed by a create-new operation.

Libarchive directly calls
[`CreateFileW` or `CreateFile2` with `CREATE_NEW`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c#L1825-L1865)
and handles the returned error. This combines the normal existence check and
creation attempt.

**Experiment:** Prototype a single-attempt create path and handle
already-exists cases without a preliminary probe. Verify overwrite behavior,
directory collisions, symlinks, hard links, races, and exception compatibility.

## Hypothesis 4: preallocation costs more than it saves for small files

**Confidence: high that an extra Win32 API call occurs; performance impact is unknown.**

.NET sets `PreallocationSize = Length` for every nonsparse regular file in
[`CreateFileStreamOptions`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L727-L744).
On Windows, `FileStream` implements this using
[`SetFileInformationByHandle(FileAllocationInfo)`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Private.CoreLib/src/Microsoft/Win32/SafeHandles/SafeFileHandle.Windows.cs#L192-L208).

This is an additional Win32 operation for each regular file. Most SDK files
are small enough that reserving their exact allocation may provide little
benefit.

Libarchive writes blocks directly with
[`WriteFile`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c#L1092-L1122).
When finishing an entry, it skips truncation if the final write offset already
equals the expected file size, explicitly identifying that as the common case:
[`archive_write_finish_entry`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c#L1166-L1205).

**Experiment:** Benchmark no preallocation and thresholds such as 64 KB,
1 MB, and 8 MB. Report results by file-size distribution rather than selecting
a threshold from only these two fixtures.

## Hypothesis 5: timestamps are restored after closing the file

**Confidence: high that the handle lifetime differs; impact requires tracing.**

.NET disposes the `FileStream` and then calls
[`File.SetLastWriteTime`](https://github.com/dotnet/dotnet/blob/3551975be08744f0418857c5bed8ab1545c5dd47/src/runtime/src/libraries/System.Formats.Tar/src/System/Formats/Tar/TarEntry.cs#L668-L724)
by path. On Windows, that may require another open or metadata operation.

Libarchive restores metadata, including timestamps, while the destination
handle remains open, then closes the handle:

- [`archive_write_finish_entry` metadata ordering](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c#L1202-L1282)
- [`SetFileTime` using the existing handle when available](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_write_disk_windows.c#L2662-L2722)

**Experiment:** Restore last-write time through the open `SafeFileHandle`
before disposing the stream. Confirm timestamp precision, failure behavior,
read-only files, links, and all supported Windows filesystems.

## Hypothesis 6: .NET object and stream overhead

**Confidence: medium. Expected to be secondary until profiling shows otherwise.**

.NET creates entry objects and uses `FileStream` plus
`Stream.CopyTo`. Libarchive reuses a disk-writer object and transfers
archive blocks directly into its current Win32 handle through
[`archive_read_extract2`](https://github.com/libarchive/libarchive/blob/v3.8.9/libarchive/archive_read_extract2.c#L68-L101).

The uncompressed per-entry correlation and the large number of small files
make filesystem and metadata work more likely than raw parsing or copy speed.

**Experiment:** Add diagnostic modes that:

1. Parse entries and drain data to `Stream.Null`.
2. Decompress gzip data to `Stream.Null`.
3. Write equivalent file sizes without TAR parsing or metadata restoration.

These modes should be reported separately and must not replace the supported
`TarFile.ExtractToDirectory` end-to-end benchmark.

## Suggested validation sequence

1. Capture ETW/WPR File I/O traces for both uncompressed fixtures.
2. Compare per-entry counts for file opens, directory queries, attribute
   queries, allocation changes, timestamp operations, writes, and closes.
3. Measure parse-only, decompression-only, and write-only baselines.
4. Test one hypothesis at a time in a private runtime build.
5. Re-run the existing complete output-manifest validation.
6. Add traversal, symlink, hard-link, overwrite, timestamp, sparse file,
   existing-directory, and unusual-entry-order tests.
7. Only combine changes after measuring each independent contribution.

## Current working theory

The leading explanation is not one unusually slow TAR parser. It is the
accumulation of several safe, general-purpose operations for every entry:

- repeated physical path-component validation without a common-prefix cache;
- unconditional parent-directory creation;
- destination existence probes before `CREATE_NEW`;
- per-file allocation requests;
- timestamp restoration after the original file handle is closed.

This theory fits the observed scaling: .NET implementation extraction is about 1.7 ms per
entry for both uncompressed fixtures, while the performance gap expands
substantially for the SDK archive containing thousands of mostly small files.
The hypotheses remain unproven until syscall counts or isolated runtime
experiments attribute time to these operations.
