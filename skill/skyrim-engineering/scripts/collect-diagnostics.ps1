[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$InputPath,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputDirectory,

    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commonModule = Join-Path $PSScriptRoot 'SkyrimEngineering.Common.psm1'
Import-Module -Name $commonModule -Force -ErrorAction Stop

$maximumBytes = [Int64](25 * 1024 * 1024)
$allowedExtensions = @('.log', '.txt', '.ini', '.json', '.toml')

function Get-AbsolutePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    return [System.IO.Path]::GetFullPath($Path)
}

function Test-PathInside {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Candidate,

        [Parameter(Mandatory = $true)]
        [string]$Root
    )

    $trimmedRoot = $Root.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    if ($Candidate.Equals($trimmedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return $true
    }

    $prefix = $trimmedRoot + [System.IO.Path]::DirectorySeparatorChar
    return $Candidate.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase)
}

function Get-SanitizedRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath
    )

    # A typed redaction marker uses ':' for readability in text, but ':' is not
    # legal in a Windows filename. Keep the redaction type while making it safe.
    return (Protect-DiagnosticText -Text $RelativePath).Replace(':', '-')
}

$inputRecords = New-Object System.Collections.ArrayList
foreach ($requestedPath in $InputPath) {
    if (-not (Test-Path -LiteralPath $requestedPath)) {
        throw "Input path does not exist: $requestedPath"
    }

    $fullPath = Get-AbsolutePath -Path $requestedPath
    if (Test-Path -LiteralPath $fullPath -PathType Container) {
        $sourceRoot = $fullPath
        $candidateFiles = @(Get-ChildItem -LiteralPath $fullPath -Recurse -File -Force | Sort-Object -Property @{ Expression = { $_.FullName.ToLowerInvariant() } }, FullName)
    }
    else {
        $sourceRoot = $fullPath
        $candidateFiles = @(Get-Item -LiteralPath $fullPath -Force)
    }

    foreach ($file in $candidateFiles) {
        $extension = [System.IO.Path]::GetExtension($file.Name).ToLowerInvariant()
        if ($allowedExtensions -notcontains $extension) {
            throw "Input file type is not permitted: $($file.Name)"
        }
        if ([Int64]$file.Length -gt $maximumBytes) {
            throw "Input file exceeds the 25 MiB limit: $($file.Name)"
        }

        $relativePath = if ($sourceRoot -eq $file.FullName) { $file.Name } else { Get-RelativeSafePath -Root $sourceRoot -Path $file.FullName }
        $sanitizedRelativePath = Get-SanitizedRelativePath -RelativePath $relativePath
        [void]$inputRecords.Add([pscustomobject]@{
                fullPath = $file.FullName
                sourceRoot = $sourceRoot
                relativePath = $sanitizedRelativePath
            })
    }
}

if ($inputRecords.Count -eq 0) {
    throw 'No diagnostic files were found in the supplied input paths.'
}

$outputFull = Get-AbsolutePath -Path $OutputDirectory
foreach ($record in $inputRecords) {
    if ((Test-Path -LiteralPath $record.sourceRoot -PathType Container) -and (Test-PathInside -Candidate $outputFull -Root $record.sourceRoot)) {
        throw 'OutputDirectory must not be inside an input source directory.'
    }
}

$duplicateRelativePaths = @($inputRecords | Group-Object -Property relativePath | Where-Object { $_.Count -gt 1 })
if ($duplicateRelativePaths.Count -gt 0) {
    throw 'Input files resolve to duplicate sanitized relative paths.'
}

if (Test-Path -LiteralPath $outputFull) {
    $existingItems = @(Get-ChildItem -LiteralPath $outputFull -Force)
    if ($existingItems.Count -gt 0 -and -not $Force) {
        throw 'OutputDirectory already exists and contains files. Pass -Force to replace the bundle.'
    }
    if ($existingItems.Count -gt 0 -and $Force) {
        $existingItems | Remove-Item -Recurse -Force
    }
}
else {
    $null = New-Item -ItemType Directory -Path $outputFull -Force
}

$manifestFiles = New-Object System.Collections.ArrayList
foreach ($record in @($inputRecords | Sort-Object -Property @{ Expression = { $_.relativePath.ToLowerInvariant() } }, relativePath)) {
    $outputPath = Join-Path $outputFull ($record.relativePath.Replace('/', [System.IO.Path]::DirectorySeparatorChar))
    $outputParent = Split-Path -Path $outputPath -Parent
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        $null = New-Item -ItemType Directory -Path $outputParent -Force
    }

    $sanitizedText = Protect-DiagnosticText -Text ([System.IO.File]::ReadAllText($record.fullPath))
    [System.IO.File]::WriteAllText($outputPath, $sanitizedText, (New-Object System.Text.UTF8Encoding($false)))
    [void]$manifestFiles.Add([pscustomobject][ordered]@{
            relativePath = $record.relativePath
            size = [Int64](Get-Item -LiteralPath $outputPath).Length
            sha256 = Get-StableSha256 -Path $outputPath
        })
}

$manifest = [pscustomobject][ordered]@{
    schema = 'skyrim-engineering.diagnostics/v1'
    files = @($manifestFiles)
}
$manifestPath = Join-Path $outputFull 'diagnostic-manifest.json'
[System.IO.File]::WriteAllText($manifestPath, ($manifest | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding($false)))
