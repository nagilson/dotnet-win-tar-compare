// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

namespace DotnetWinTarCompare;

internal interface ITarArchiveExtractor
{
    void Extract(TarExtractionContext context);
}

internal sealed record TarExtractionContext(
    string ArchivePath,
    string TargetDirectory);

