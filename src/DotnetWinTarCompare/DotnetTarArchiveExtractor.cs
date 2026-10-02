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

        using FileStream archiveStream = File.OpenRead(context.ArchivePath);
        if (isGzip)
        {
            using var gzipStream = new GZipStream(
                archiveStream,
                CompressionMode.Decompress,
                leaveOpen: false);
            TarFile.ExtractToDirectory(
                gzipStream,
                context.TargetDirectory,
                overwriteFiles: true);
        }
        else
        {
            TarFile.ExtractToDirectory(
                archiveStream,
                context.TargetDirectory,
                overwriteFiles: true);
        }
    }
}
