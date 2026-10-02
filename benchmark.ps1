[CmdletBinding()]
param(
    [ValidateRange(1, 20)]
    [int]$Iterations = 5,

    [ValidateRange(0, 10)]
    [int]$WarmupIterations = 1,

    [string]$DotnetPath = 'dotnet',

    [string]$ResultPath = (Join-Path $PSScriptRoot 'results\latest.md'),

    [switch]$PrepareArchivesOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$projectPath = Join-Path $PSScriptRoot 'src\DotnetWinTarCompare\DotnetWinTarCompare.csproj'
$archiveDirectory = Join-Path $PSScriptRoot 'archives'
$workDirectory = Join-Path $PSScriptRoot 'work'
$publishDirectory = Join-Path $PSScriptRoot 'artifacts\publish\DotnetWinTarCompare\release_win-x64'
$releaseMetadataUri = 'https://builds.dotnet.microsoft.com/dotnet/release-metadata/11.0/releases.json'

$fixtures = @(
    [pscustomobject]@{
        Product = '.NET SDK'
        Component = 'sdk'
        AssetName = 'dotnet-sdk-win-x64.tar.gz'
        Version = '11.0.100-rc.1.26425.128'
        ValidationPath = 'sdk\11.0.100-rc.1.26425.128\dotnet.dll'
        BaseName = 'dotnet-sdk-11.0.100-rc.1.26425.128-win-x64'
    },
    [pscustomobject]@{
        Product = '.NET Runtime'
        Component = 'runtime'
        AssetName = 'dotnet-runtime-win-x64.tar.gz'
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

function Get-ReleaseAsset {
    param(
        [Parameter(Mandatory)]
        [object]$ReleaseMetadata,

        [Parameter(Mandatory)]
        [object]$Fixture
    )

    $release = $ReleaseMetadata.releases |
        Where-Object { $_.($Fixture.Component).version -eq $Fixture.Version } |
        Select-Object -First 1
    if ($null -eq $release) {
        throw "Version '$($Fixture.Version)' was not found in '$releaseMetadataUri'."
    }

    $asset = $release.($Fixture.Component).files |
        Where-Object { $_.rid -eq 'win-x64' -and $_.name -eq $Fixture.AssetName } |
        Select-Object -First 1
    if ($null -eq $asset) {
        throw "Asset '$($Fixture.AssetName)' was not found in '$releaseMetadataUri'."
    }

    if ([string]::IsNullOrWhiteSpace($asset.url) -or
        [string]::IsNullOrWhiteSpace($asset.hash)) {
        throw "Asset '$($Fixture.AssetName)' has incomplete release metadata."
    }

    $expectedFileName = "$($Fixture.BaseName).tar.gz"
    $actualFileName = [IO.Path]::GetFileName(([Uri]$asset.url).AbsolutePath)
    if (-not [string]::Equals(
            $actualFileName,
            $expectedFileName,
            [StringComparison]::Ordinal)) {
        throw "Asset '$($Fixture.AssetName)' resolved to '$actualFileName', expected '$expectedFileName'."
    }

    return $asset
}

function Assert-ArchiveHash {
    param(
        [Parameter(Mandatory)]
        [string]$Path,

        [Parameter(Mandatory)]
        [string]$ExpectedHash
    )

    $actualHash = (Get-FileHash -LiteralPath $Path -Algorithm SHA512).Hash
    if (-not [string]::Equals(
            $actualHash,
            $ExpectedHash,
            [StringComparison]::OrdinalIgnoreCase)) {
        throw "SHA-512 mismatch for '$Path'. Expected '$ExpectedHash', found '$actualHash'."
    }
}

function Expand-GzipArchive {
    param(
        [Parameter(Mandatory)]
        [string]$SourcePath,

        [Parameter(Mandatory)]
        [string]$DestinationPath
    )

    $temporaryPath = "$DestinationPath.partial"
    Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue

    try {
        $source = [IO.File]::OpenRead($SourcePath)
        try {
            $gzip = [IO.Compression.GZipStream]::new(
                $source,
                [IO.Compression.CompressionMode]::Decompress,
                $false)
            try {
                $destination = [IO.File]::Create($temporaryPath)
                try {
                    $gzip.CopyTo($destination)
                }
                finally {
                    $destination.Dispose()
                }
            }
            finally {
                $gzip.Dispose()
            }
        }
        finally {
            $source.Dispose()
        }

        Move-Item -LiteralPath $temporaryPath -Destination $DestinationPath
    }
    finally {
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
    }
}

function Initialize-ArchiveFixture {
    param(
        [Parameter(Mandatory)]
        [object]$ReleaseMetadata,

        [Parameter(Mandatory)]
        [object]$Fixture
    )

    $asset = Get-ReleaseAsset -ReleaseMetadata $ReleaseMetadata -Fixture $Fixture
    $compressedPath = Join-Path $archiveDirectory "$($Fixture.BaseName).tar.gz"
    $uncompressedPath = Join-Path $archiveDirectory "$($Fixture.BaseName).tar"

    if (-not (Test-Path -LiteralPath $compressedPath -PathType Leaf)) {
        $temporaryPath = "$compressedPath.download"
        Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        try {
            Write-Host "Downloading $($Fixture.Product) $($Fixture.Version) from release metadata..."
            Invoke-WebRequest -Uri $asset.url -OutFile $temporaryPath
            Assert-ArchiveHash -Path $temporaryPath -ExpectedHash $asset.hash
            Move-Item -LiteralPath $temporaryPath -Destination $compressedPath
        }
        finally {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
    else {
        Assert-ArchiveHash -Path $compressedPath -ExpectedHash $asset.hash
    }

    if (-not (Test-Path -LiteralPath $uncompressedPath -PathType Leaf)) {
        Write-Host "Decompressing $($Fixture.Product) fixture..."
        Expand-GzipArchive -SourcePath $compressedPath -DestinationPath $uncompressedPath
    }
}

function Get-ExtractionManifest {
    param(
        [Parameter(Mandatory)]
        [string]$Path
    )

    $root = [IO.Path]::TrimEndingDirectorySeparator([IO.Path]::GetFullPath($Path))
    return [string[]]@(
        Get-ChildItem -LiteralPath $root -Recurse -Force |
            ForEach-Object {
                $relativePath = $_.FullName.Substring($root.Length).TrimStart(
                    [IO.Path]::DirectorySeparatorChar).Replace(
                    [IO.Path]::DirectorySeparatorChar,
                    '/')
                if ($_.PSIsContainer) {
                    "D|$relativePath"
                }
                else {
                    "F|$relativePath|$($_.Length)"
                }
            } |
            Sort-Object
    )
}

function Assert-EquivalentManifest {
    param(
        [Parameter(Mandatory)]
        [string[]]$Expected,

        [Parameter(Mandatory)]
        [string[]]$Actual,

        [Parameter(Mandatory)]
        [string]$CaseDescription
    )

    if ($Expected.Count -ne $Actual.Count) {
        throw "Extracted layout mismatch for ${CaseDescription}: expected $($Expected.Count) entries, found $($Actual.Count)."
    }

    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if (-not [string]::Equals($Expected[$index], $Actual[$index], [StringComparison]::Ordinal)) {
            throw "Extracted layout mismatch for ${CaseDescription}: expected '$($Expected[$index])', found '$($Actual[$index])'."
        }
    }
}

function Get-ExtractorDisplayName {
    param(
        [Parameter(Mandatory)]
        [string]$Extractor
    )

    switch ($Extractor) {
        'dotnet' { return '.NET implementation' }
        'windows-tar' { return 'Windows tar.exe (bsdtar)' }
        default { throw "Unknown extractor '$Extractor'." }
    }
}

function Invoke-ExtractionCase {
    param(
        [Parameter(Mandatory)]
        [string]$ExecutablePath,

        [Parameter(Mandatory)]
        [object]$Fixture,

        [Parameter(Mandatory)]
        [string]$Extension,

        [Parameter(Mandatory)]
        [string]$Extractor,

        [Parameter(Mandatory)]
        [string]$RunLabel,

        [Parameter(Mandatory)]
        [hashtable]$ExpectedManifests
    )

    $archivePath = Join-Path $archiveDirectory ($Fixture.BaseName + $Extension)
    $targetDirectory = Join-Path $workDirectory (
        '{0}-{1}-{2}-{3}' -f
        $Fixture.Product.Replace(' ', '-').Replace('.', '').ToLowerInvariant(),
        $Extension.TrimStart('.').Replace('.', '-'),
        $Extractor,
        $RunLabel)

    if (Test-Path -LiteralPath $targetDirectory) {
        Remove-Item -LiteralPath $targetDirectory -Recurse -Force
    }

    try {
        $output = @(& $ExecutablePath $Extractor $archivePath $targetDirectory)
        if ($LASTEXITCODE -ne 0) {
            throw "Extraction failed for $($Fixture.Product) $Extension with $Extractor."
        }

        $elapsedLine = $output | Where-Object { $_ -match '^elapsed_ms=' } | Select-Object -Last 1
        if ($null -eq $elapsedLine) {
            throw "Extractor did not report elapsed time."
        }

        $validationPath = Join-Path $targetDirectory $Fixture.ValidationPath
        if (-not (Test-Path -LiteralPath $validationPath -PathType Leaf)) {
            throw "Extracted layout validation failed: '$validationPath'."
        }

        $caseKey = $Fixture.BaseName
        $extractorDisplayName = Get-ExtractorDisplayName -Extractor $Extractor
        $caseDescription = "$($Fixture.Product) $Extension with $extractorDisplayName"
        $manifest = Get-ExtractionManifest -Path $targetDirectory
        if ($ExpectedManifests.ContainsKey($caseKey)) {
            Assert-EquivalentManifest `
                -Expected $ExpectedManifests[$caseKey] `
                -Actual $manifest `
                -CaseDescription $caseDescription
        }
        else {
            $ExpectedManifests[$caseKey] = $manifest
        }

        return [double]::Parse(
            $elapsedLine.Substring('elapsed_ms='.Length),
            [Globalization.CultureInfo]::InvariantCulture)
    }
    finally {
        if (Test-Path -LiteralPath $targetDirectory) {
            Remove-Item -LiteralPath $targetDirectory -Recurse -Force
        }
    }
}

New-Item -ItemType Directory -Force -Path $archiveDirectory | Out-Null
New-Item -ItemType Directory -Force -Path $workDirectory | Out-Null
New-Item -ItemType Directory -Force -Path (Split-Path -Parent $ResultPath) | Out-Null

$releaseMetadata = Invoke-RestMethod -Uri $releaseMetadataUri
foreach ($fixture in $fixtures) {
    Initialize-ArchiveFixture -ReleaseMetadata $releaseMetadata -Fixture $fixture
}

if ($PrepareArchivesOnly) {
    Write-Host "Archive fixtures are ready in '$archiveDirectory'."
    return
}

Invoke-Checked -FilePath $DotnetPath -ArgumentList @(
    'publish',
    $projectPath,
    '--configuration',
    'Release',
    '--runtime',
    'win-x64',
    '--self-contained',
    'true',
    '--output',
    $publishDirectory,
    '--nologo'
)

$executablePath = Join-Path $publishDirectory 'DotnetWinTarCompare.exe'
if (-not (Test-Path -LiteralPath $executablePath -PathType Leaf)) {
    throw "Native AOT benchmark executable was not produced: '$executablePath'."
}

$inboxTarPath = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path -LiteralPath $inboxTarPath -PathType Leaf)) {
    throw "Windows inbox TAR executable was not found: '$inboxTarPath'."
}

$dotnetVersion = (& $DotnetPath --version | Select-Object -First 1).Trim()
if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($dotnetVersion)) {
    throw "Could not determine the .NET SDK version."
}

$results = [System.Collections.Generic.List[object]]::new()
$dotnetExtractor = 'dotnet'
$windowsTarExtractor = 'windows-tar'
$extractors = @($dotnetExtractor, $windowsTarExtractor)
$extensions = @('.tar.gz', '.tar')
$expectedManifests = @{}
$sequence = 0
$caseIndex = 0

foreach ($fixture in $fixtures) {
    foreach ($extension in $extensions) {
        $archivePath = Join-Path $archiveDirectory ($fixture.BaseName + $extension)
        if (-not (Test-Path -LiteralPath $archivePath -PathType Leaf)) {
            throw "Archive fixture not found: '$archivePath'."
        }

        for ($warmup = 1; $warmup -le $WarmupIterations; $warmup++) {
            $warmupOrder = if (($caseIndex + $warmup) % 2 -eq 0) {
                $extractors
            }
            else {
                @($extractors[1], $extractors[0])
            }

            foreach ($extractor in $warmupOrder) {
                $extractorDisplayName = Get-ExtractorDisplayName -Extractor $extractor
                Write-Host (
                    '[warmup {0}/{1}] {2} {3} with {4}' -f
                    $warmup,
                    $WarmupIterations,
                    $fixture.Product,
                    $extension,
                    $extractorDisplayName)

                Invoke-ExtractionCase `
                    -ExecutablePath $executablePath `
                    -Fixture $fixture `
                    -Extension $extension `
                    -Extractor $extractor `
                    -RunLabel "warmup-$warmup" `
                    -ExpectedManifests $expectedManifests | Out-Null
            }
        }

        for ($iteration = 1; $iteration -le $Iterations; $iteration++) {
            $measurementOrder = if (($caseIndex + $iteration) % 2 -eq 0) {
                $extractors
            }
            else {
                @($extractors[1], $extractors[0])
            }

            foreach ($extractor in $measurementOrder) {
                $sequence++
                $extractorDisplayName = Get-ExtractorDisplayName -Extractor $extractor
                Write-Host (
                    '[{0}/{1}] {2} {3} with {4}' -f
                    $iteration,
                    $Iterations,
                    $fixture.Product,
                    $extension,
                    $extractorDisplayName)

                $elapsedMilliseconds = Invoke-ExtractionCase `
                    -ExecutablePath $executablePath `
                    -Fixture $fixture `
                    -Extension $extension `
                    -Extractor $extractor `
                    -RunLabel "iteration-$iteration" `
                    -ExpectedManifests $expectedManifests

                $results.Add([pscustomobject]@{
                    Sequence = $sequence
                    Product = $fixture.Product
                    Version = $fixture.Version
                    Format = $extension.TrimStart('.')
                    Extractor = $extractor
                    Iteration = $iteration
                    Milliseconds = $elapsedMilliseconds
                })
            }
        }

        $caseIndex++
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
$lines.Add(('- OS: `{0}`' -f [Environment]::OSVersion.VersionString))
$lines.Add(('- Processor count: `{0}`' -f [Environment]::ProcessorCount))
$lines.Add(('- Build SDK: `{0}`' -f $dotnetVersion))
$lines.Add(('- Iterations per case: `{0}`' -f $Iterations))
$lines.Add(('- Warmup iterations per case: `{0}`' -f $WarmupIterations))
$lines.Add('- Runs were serialized with alternating extractor order; archive download, Native AOT publish, warmup, target cleanup, and validation were excluded from timing.')
$lines.Add('- The benchmark host is a trimmed, self-contained `win-x64` Native AOT executable published in `Release` with `OptimizationPreference=Speed`.')
$lines.Add('- The .NET implementation runs `TarFile.ExtractToDirectory` and `GZipStream` in process; the Windows tar.exe (bsdtar) implementation launches the inbox `System32\tar.exe`.')
$lines.Add('- Windows tar.exe (bsdtar) measurements include child-process startup and inter-process synchronization.')
$lines.Add('- Every extraction, including compressed and uncompressed forms, is validated against the first complete path/type/size manifest for that product fixture.')
$lines.Add('')
$lines.Add('## Summary')
$lines.Add('')
$lines.Add('| Product | Version | Format | .NET implementation median (ms) | Windows tar.exe (bsdtar) median (ms) | Faster | Difference |')
$lines.Add('|---|---|---:|---:|---:|---|---:|')

foreach ($fixture in $fixtures) {
    foreach ($format in @('tar.gz', 'tar')) {
        $dotnet = $summaryRows | Where-Object {
            $_.Product -eq $fixture.Product -and $_.Format -eq $format -and $_.Extractor -eq $dotnetExtractor
        }
        $windowsTar = $summaryRows | Where-Object {
            $_.Product -eq $fixture.Product -and $_.Format -eq $format -and $_.Extractor -eq $windowsTarExtractor
        }
        $faster = if ($dotnet.MedianMilliseconds -lt $windowsTar.MedianMilliseconds) {
            '.NET implementation'
        }
        else {
            'Windows tar.exe (bsdtar)'
        }
        $slowerMedian = [Math]::Max($dotnet.MedianMilliseconds, $windowsTar.MedianMilliseconds)
        $fasterMedian = [Math]::Min($dotnet.MedianMilliseconds, $windowsTar.MedianMilliseconds)
        $difference = (($slowerMedian - $fasterMedian) / $slowerMedian) * 100
        $lines.Add((
            '| {0} | `{1}` | `{2}` | {3:N1} | {4:N1} | **{5}** | {6:N1}% |' -f
            $fixture.Product,
            $fixture.Version,
            $format,
            $dotnet.MedianMilliseconds,
            $windowsTar.MedianMilliseconds,
            $faster,
            $difference))
    }
}

$lines.Add('')
$lines.Add('## Observations')
$lines.Add('')
$lines.Add('| Sequence | Product | Format | Extractor | Iteration | Extraction time (ms) |')
$lines.Add('|---:|---|---:|---|---:|---:|')
foreach ($result in $results) {
    $lines.Add((
        '| {0} | {1} | `{2}` | {3} | {4} | {5:N3} |' -f
        $result.Sequence,
        $result.Product,
        $result.Format,
        (Get-ExtractorDisplayName -Extractor $result.Extractor),
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
        (Get-ExtractorDisplayName -Extractor $summary.Extractor),
        $summary.MinimumMilliseconds,
        $summary.MedianMilliseconds,
        $summary.MaximumMilliseconds))
}

[IO.File]::WriteAllLines($ResultPath, $lines)
Write-Host "Wrote Markdown report: $ResultPath"
