[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$Iterations = 3,

    [string]$DotnetPath = 'dotnet',

    [string]$ResultPath = (Join-Path $PSScriptRoot 'results\latest.md')
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectPath = Join-Path $PSScriptRoot 'src\DotnetWinTarCompare\DotnetWinTarCompare.csproj'
$archiveDirectory = Join-Path $PSScriptRoot 'archives'
$workDirectory = Join-Path $PSScriptRoot 'work'

$fixtures = @(
    [pscustomobject]@{
        Product = '.NET SDK'
        Version = '11.0.100-rc.1.26425.128'
        ValidationPath = 'sdk\11.0.100-rc.1.26425.128\dotnet.dll'
        BaseName = 'dotnet-sdk-11.0.100-rc.1.26425.128-win-x64'
    },
    [pscustomobject]@{
        Product = '.NET Runtime'
        Version = '11.0.0-rc.1.26425.128'
        ValidationPath = 'shared\Microsoft.NETCore.App\11.0.0-rc.1.26425.128\Microsoft.NETCore.App.deps.json'
        BaseName = 'dotnet-runtime-11.0.0-rc.1.26425.128-win-x64'
    }
)

function Invoke-Checked {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath,

        [Parameter(Mandatory)]
        [string[]]$ArgumentList
    )

    & $FilePath @ArgumentList
    if ($LASTEXITCODE -ne 0) {
        throw "'$FilePath' exited with code $LASTEXITCODE."
    }
}

function Get-Median {
    param([double[]]$Values)

    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if ($sorted.Count % 2 -eq 1) {
        return $sorted[$middle]
    }

    return ($sorted[$middle - 1] + $sorted[$middle]) / 2
}

New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultPath) | Out-Null

Invoke-Checked -FilePath $DotnetPath -ArgumentList @(
    'build',
    $projectPath,
    '--configuration',
    'Release',
    '--nologo'
)

$assemblyPath = Join-Path $PSScriptRoot 'artifacts\bin\DotnetWinTarCompare\release\DotnetWinTarCompare.dll'
if (-not (Test-Path -LiteralPath $assemblyPath -PathType Leaf)) {
    throw "Benchmark assembly was not produced: '$assemblyPath'."
}

$results = [System.Collections.Generic.List[object]]::new()
$extractors = @('managed', 'native')
$extensions = @('.tar.gz', '.tar')

foreach ($fixture in $fixtures) {
    foreach ($extension in $extensions) {
        $archivePath = Join-Path $archiveDirectory ($fixture.BaseName + $extension)
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw "Archive fixture not found: '$archivePath'."
        }

        foreach ($extractor in $extractors) {
            for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
                $targetDirectory = Join-Path $workDirectory (
                    '{0}-{1}-{2}-{3}' -f
                    $fixture.Product.Replace(' ', '-').Replace('.', '').ToLowerInvariant(),
                    $extension.TrimStart('.').Replace('.', '-'),
                    $extractor,
                    $iteration)

                if (Test-Path -LiteralPath $targetDirectory) {
                    Remove-Item -LiteralPath $targetDirectory -Recurse -Force
                }

                Write-Host (
                    '[{0}/{1}] {2} {3} with {4}' -f
                    $iteration,
                    $Iterations,
                    $fixture.Product,
                    $extension,
                    $extractor)

                $output = & $DotnetPath $assemblyPath $extractor $archivePath $targetDirectory
                if ($LASTEXITCODE -ne 0) {
                    throw "Extraction failed for $($fixture.Product) $extension with $extractor."
                }

                $elapsedLine = $output | Where-Object { $_ -match '^elapsed_ms=' } | Select-Object -Last 1
                if ($null -eq $elapsedLine) {
                    throw "Extractor did not report elapsed time."
                }

                $elapsedMilliseconds = [double]::Parse(
                    $elapsedLine.Substring('elapsed_ms='.Length),
                    [Globalization.CultureInfo]::InvariantCulture)
                $validationPath = Join-Path $targetDirectory $fixture.ValidationPath
                if (-not (Test-Path -LiteralPath $validationPath -PathType Leaf)) {
                    throw "Extracted layout validation failed: '$validationPath'."
                }

                $results.Add([pscustomobject]@{
                    Product = $fixture.Product
                    Version = $fixture.Version
                    Format = $extension.TrimStart('.')
                    Extractor = $extractor
                    Iteration = $iteration
                    Milliseconds = $elapsedMilliseconds
                })

                Remove-Item -LiteralPath $targetDirectory -Recurse -Force
            }
        }
    }
}

$summaryRows = foreach ($group in ($results | Group-Object Product, Version, Format, Extractor)) {
    $first = $group.Group[0]
    $values = [double[]]@($group.Group.Milliseconds)
    [pscustomobject]@{
        Product = $first.Product
        Version = $first.Version
        Format = $first.Format
        Extractor = $first.Extractor
        MedianMilliseconds = Get-Median $values
        MinimumMilliseconds = ($values | Measure-Object -Minimum).Minimum
        MaximumMilliseconds = ($values | Measure-Object -Maximum).Maximum
    }
}

$lines = [System.Collections.Generic.List[string]]::new()
$lines.Add('# .NET 11 Windows TAR extraction comparison')
$lines.Add('')
$lines.Add(('Generated: `{0:O}`' -f [DateTimeOffset]::Now))
$lines.Add('')
$lines.Add(('- Machine: `{0}`' -f [Environment]::MachineName))
$lines.Add(('- OS: `{0}`' -f [Environment]::OSVersion.VersionString))
$lines.Add(('- Processor count: `{0}`' -f [Environment]::ProcessorCount))
$lines.Add(('- Iterations per case: `{0}`' -f $Iterations))
$lines.Add('- Runs were serialized; archive download, build, target cleanup, and validation were excluded from timing.')
$lines.Add('- Managed extraction uses `System.Formats.Tar` and `GZipStream`; native extraction uses Windows `tar.exe` from `PATH`.')
$lines.Add('')
$lines.Add('## Summary')
$lines.Add('')
$lines.Add('| Product | Version | Format | Managed median (ms) | Native median (ms) | Faster | Difference |')
$lines.Add('|---|---|---:|---:|---:|---|---:|')

foreach ($fixture in $fixtures) {
    foreach ($format in @('tar.gz', 'tar')) {
        $managed = $summaryRows | Where-Object {
            $_.Product -eq $fixture.Product -and $_.Format -eq $format -and $_.Extractor -eq 'managed'
        }
        $native = $summaryRows | Where-Object {
            $_.Product -eq $fixture.Product -and $_.Format -eq $format -and $_.Extractor -eq 'native'
        }
        $faster = if ($managed.MedianMilliseconds -lt $native.MedianMilliseconds) { 'Managed' } else { 'Native' }
        $slowerMedian = [Math]::Max($managed.MedianMilliseconds, $native.MedianMilliseconds)
        $fasterMedian = [Math]::Min($managed.MedianMilliseconds, $native.MedianMilliseconds)
        $difference = (($slowerMedian - $fasterMedian) / $slowerMedian) * 100
        $lines.Add((
            '| {0} | `{1}` | `{2}` | {3:N1} | {4:N1} | **{5}** | {6:N1}% |' -f
            $fixture.Product,
            $fixture.Version,
            $format,
            $managed.MedianMilliseconds,
            $native.MedianMilliseconds,
            $faster,
            $difference))
    }
}

$lines.Add('')
$lines.Add('## Observations')
$lines.Add('')
$lines.Add('| Product | Format | Extractor | Iteration | Extraction time (ms) |')
$lines.Add('|---|---:|---|---:|---:|')
foreach ($result in $results) {
    $lines.Add((
        '| {0} | `{1}` | {2} | {3} | {4:N3} |' -f
        $result.Product,
        $result.Format,
        $result.Extractor,
        $result.Iteration,
        $result.Milliseconds))
}

$lines.Add('')
$lines.Add('## Ranges')
$lines.Add('')
$lines.Add('| Product | Format | Extractor | Minimum (ms) | Median (ms) | Maximum (ms) |')
$lines.Add('|---|---:|---|---:|---:|---:|')
foreach ($summary in ($summaryRows | Sort-Object Product, Format, Extractor)) {
    $lines.Add((
        '| {0} | `{1}` | {2} | {3:N1} | {4:N1} | {5:N1} |' -f
        $summary.Product,
        $summary.Format,
        $summary.Extractor,
        $summary.MinimumMilliseconds,
        $summary.MedianMilliseconds,
        $summary.MaximumMilliseconds))
}

[IO.File]::WriteAllLines($ResultPath, $lines)
Write-Host "Wrote Markdown report: $ResultPath"
