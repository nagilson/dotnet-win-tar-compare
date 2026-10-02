using System.Diagnostics;

namespace DotnetWinTarCompare;

internal static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length != 3)
        {
            Console.Error.WriteLine(
                "Usage: DotnetWinTarCompare <dotnet|windows-tar> <archive.tar[.gz]> <target-directory>");
            return 2;
        }

        ITarArchiveExtractor extractor = args[0].ToLowerInvariant() switch
        {
            "dotnet" => new DotnetTarArchiveExtractor(),
            "windows-tar" => new WindowsTarArchiveExtractor(),
            _ => throw new ArgumentException(
                $"Unknown extractor '{args[0]}'. Expected 'dotnet' or 'windows-tar'.",
                nameof(args)),
        };

        string archivePath = Path.GetFullPath(args[1]);
        string targetDirectory = Path.GetFullPath(args[2]);
        if (!File.Exists(archivePath))
        {
            throw new FileNotFoundException("Archive not found.", archivePath);
        }

        if (Directory.Exists(targetDirectory) &&
            Directory.EnumerateFileSystemEntries(targetDirectory).Any())
        {
            throw new IOException($"Target directory must be empty: '{targetDirectory}'.");
        }

        Directory.CreateDirectory(targetDirectory);
        var stopwatch = Stopwatch.StartNew();
        extractor.Extract(new TarExtractionContext(archivePath, targetDirectory));
        stopwatch.Stop();
        Console.WriteLine($"elapsed_ms={stopwatch.Elapsed.TotalMilliseconds:F3}");
        return 0;
    }
}
