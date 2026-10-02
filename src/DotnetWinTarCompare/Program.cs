namespace DotnetWinTarCompare;

internal static class Program
{
    public static int Main(string[] args)
    {
        if (args.Length != 3)
        {
            Console.Error.WriteLine(
                "Usage: DotnetWinTarCompare <managed|native> <archive.tar[.gz]> <target-directory>");
            return 2;
        }

        ITarArchiveExtractor extractor = args[0].ToLowerInvariant() switch
        {
            "managed" => new DotnetTarArchiveExtractor(),
            "native" => new WindowsNativeTarArchiveExtractor(),
            _ => throw new ArgumentException(
                $"Unknown extractor '{args[0]}'. Expected 'managed' or 'native'.",
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
        extractor.Extract(new TarExtractionContext(archivePath, targetDirectory));
        return 0;
    }
}
