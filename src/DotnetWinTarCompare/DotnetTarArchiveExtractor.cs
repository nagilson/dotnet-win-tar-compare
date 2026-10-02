// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

using System.Formats.Tar;
using System.IO.Compression;

namespace DotnetWinTarCompare;

internal sealed class DotnetTarArchiveExtractor : ITarArchiveExtractor
{
    public void Extract(TarExtractionContext context)
    {
        bool isGzip = context.ArchivePath.EndsWith(".gz", StringComparison.OrdinalIgnoreCase);

        using var archiveStream = new FileStream(
            context.ArchivePath,
            FileMode.Open,
            FileAccess.Read,
            FileShare.Read);
        using Stream tarStream = isGzip
            ? new GZipStream(archiveStream, CompressionMode.Decompress, leaveOpen: false)
            : archiveStream;
        using var tarReader = new TarReader(tarStream, leaveOpen: false);

        var deferredHardLinks = new List<(string DestinationPath, string TargetPath)>();
        while (tarReader.GetNextEntry() is { } entry)
        {
            ProcessEntry(entry, context.TargetDirectory, deferredHardLinks);
        }

        CreateDeferredHardLinks(deferredHardLinks);
    }

    private static void ProcessEntry(
        TarEntry entry,
        string targetDirectory,
        List<(string DestinationPath, string TargetPath)> deferredHardLinks)
    {
        string destinationPath;
        switch (entry.EntryType)
        {
            case TarEntryType.RegularFile:
                destinationPath = ResolveDestination(entry.Name, targetDirectory);
                Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
                entry.ExtractToFile(destinationPath, overwrite: true);
                break;
            case TarEntryType.Directory:
                destinationPath = ResolveDestination(entry.Name, targetDirectory);
                Directory.CreateDirectory(destinationPath);
                break;
            case TarEntryType.SymbolicLink:
                destinationPath = ResolveDestination(entry.Name, targetDirectory);
                Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
                if (File.Exists(destinationPath) || Directory.Exists(destinationPath))
                {
                    File.Delete(destinationPath);
                }

                File.CreateSymbolicLink(destinationPath, entry.LinkName!);
                break;
            case TarEntryType.HardLink:
                destinationPath = ResolveDestination(entry.Name, targetDirectory);
                string targetPath = ResolveDestination(entry.LinkName!, targetDirectory);
                Directory.CreateDirectory(Path.GetDirectoryName(destinationPath)!);
                deferredHardLinks.Add((destinationPath, targetPath));
                break;
            default:
                Console.Error.WriteLine(
                    $"Warning: Skipping unsupported TAR entry type '{entry.EntryType}' for '{entry.Name}'.");
                break;
        }
    }

    private static string ResolveDestination(string entryName, string targetDirectory)
    {
        string targetRoot = Path.TrimEndingDirectorySeparator(Path.GetFullPath(targetDirectory));
        string relativePath = entryName
            .Replace('/', Path.DirectorySeparatorChar)
            .TrimStart(Path.DirectorySeparatorChar);
        string destinationPath = Path.GetFullPath(Path.Combine(targetRoot, relativePath));
        string requiredPrefix = targetRoot + Path.DirectorySeparatorChar;

        if (!destinationPath.StartsWith(requiredPrefix, StringComparison.OrdinalIgnoreCase) &&
            !string.Equals(destinationPath, targetRoot, StringComparison.OrdinalIgnoreCase))
        {
            throw new IOException($"Archive entry escapes the target directory: '{entryName}'.");
        }

        return destinationPath;
    }

    private static void CreateDeferredHardLinks(
        List<(string DestinationPath, string TargetPath)> deferredHardLinks)
    {
        foreach ((string destinationPath, string targetPath) in deferredHardLinks)
        {
            if (File.Exists(destinationPath))
            {
                File.Delete(destinationPath);
            }

            File.CreateHardLink(destinationPath, targetPath);
        }
    }
}
