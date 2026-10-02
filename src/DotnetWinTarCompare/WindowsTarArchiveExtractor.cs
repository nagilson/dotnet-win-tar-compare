// Licensed to the .NET Foundation under one or more agreements.
// The .NET Foundation licenses this file to you under the MIT license.

using System.ComponentModel;
using System.Diagnostics;
using System.Text;

namespace DotnetWinTarCompare;

internal sealed class WindowsTarArchiveExtractor : ITarArchiveExtractor
{
    private static readonly string s_tarExecutable = Path.Combine(
        Environment.GetFolderPath(Environment.SpecialFolder.Windows),
        "System32",
        "tar.exe");
    private const int MaximumStandardErrorLength = 16 * 1024;

    public void Extract(TarExtractionContext context)
    {
        if (!OperatingSystem.IsWindows())
        {
            throw new PlatformNotSupportedException("This comparison requires Windows tar.exe (bsdtar).");
        }

        Directory.CreateDirectory(context.TargetDirectory);

        var startInfo = new ProcessStartInfo
        {
            FileName = s_tarExecutable,
            UseShellExecute = false,
            CreateNoWindow = true,
            RedirectStandardInput = true,
            RedirectStandardError = true,
        };

        startInfo.ArgumentList.Add(
            context.ArchivePath.EndsWith(".gz", StringComparison.OrdinalIgnoreCase) ? "-xzf" : "-xf");
        startInfo.ArgumentList.Add(context.ArchivePath);
        startInfo.ArgumentList.Add("-C");
        startInfo.ArgumentList.Add(context.TargetDirectory);

        using var process = new Process { StartInfo = startInfo };
        try
        {
            if (!process.Start())
            {
                throw new InvalidOperationException($"Failed to start '{s_tarExecutable}'.");
            }
        }
        catch (Win32Exception ex)
        {
            throw new InvalidOperationException(
                $"Failed to start Windows tar.exe (bsdtar) at '{s_tarExecutable}'.",
                ex);
        }

        process.StandardInput.Close();
        Task<string> standardErrorTask = ReadBoundedAsync(
            process.StandardError,
            MaximumStandardErrorLength);
        process.WaitForExit();
        string standardError = standardErrorTask.GetAwaiter().GetResult();

        if (process.ExitCode != 0)
        {
            string details = string.IsNullOrWhiteSpace(standardError)
                ? string.Empty
                : $" Error output: {standardError.Trim()}";
            throw new InvalidOperationException(
                $"'{s_tarExecutable}' exited with code {process.ExitCode}.{details}");
        }
    }

    private static async Task<string> ReadBoundedAsync(StreamReader reader, int maximumLength)
    {
        var retained = new StringBuilder(capacity: maximumLength);
        char[] buffer = new char[1024];
        int read;
        while ((read = await reader.ReadAsync(buffer).ConfigureAwait(false)) > 0)
        {
            int remaining = maximumLength - retained.Length;
            if (remaining > 0)
            {
                retained.Append(buffer, 0, Math.Min(read, remaining));
            }
        }

        return retained.ToString();
    }
}
