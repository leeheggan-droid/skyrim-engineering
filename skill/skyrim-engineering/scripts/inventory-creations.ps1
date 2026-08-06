[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataPath,

    [string]$LoadOrderPath,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$commonModule = Join-Path $PSScriptRoot 'SkyrimEngineering.Common.psm1'
Import-Module $commonModule -Force

function Test-ApprovedCreationFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    # These four are supplied free with current Special Edition releases.  Keep
    # the explicit set so the supported inventory scope is auditable if naming
    # conventions ever change.
    $freeCreationIdentifiers = @(
        'ccBGSSSE001-Fish.esm',
        'ccBGSSSE025-AdvDSGS.esm',
        'ccBGSSSE037-Curios.esl',
        'ccQDRSSE001-SurvivalMode.esl'
    )

    if ($freeCreationIdentifiers -icontains $Name) {
        return $true
    }

    return $Name -imatch '^cc.*\.(esl|esm|esp|bsa)$'
}

if (-not (Test-Path -LiteralPath $DataPath -PathType Container)) {
    throw 'DataPath must be an existing Skyrim Data directory.'
}

$dataRoot = [System.IO.Path]::GetFullPath($DataPath)
$entries = New-Object System.Collections.ArrayList

Get-ChildItem -LiteralPath $dataRoot -File | Where-Object {
    Test-ApprovedCreationFile -Name $_.Name
} | Sort-Object -Property @{ Expression = { $_.Name.ToLowerInvariant() } }, Name | ForEach-Object {
    $extension = [System.IO.Path]::GetExtension($_.Name).ToLowerInvariant()
    $kind = if ($extension -eq '.bsa') { 'archive' } else { 'plugin' }
    $pluginType = if ($kind -eq 'plugin') { $extension.TrimStart('.') } else { $null }
    $entry = [ordered]@{
        name = $_.Name
        kind = $kind
        size = [Int64]$_.Length
        sha256 = Get-StableSha256 -Path $_.FullName
        pluginType = $pluginType
        internalFlag = if ($kind -eq 'plugin') { 'notInspected' } else { $null }
        relativePath = Get-RelativeSafePath -Root $dataRoot -Path $_.FullName
    }
    [void]$entries.Add([pscustomobject]$entry)
}

$pluginsByName = @{}
foreach ($entry in $entries) {
    if ($entry.kind -eq 'plugin') {
        $pluginsByName[$entry.name.ToLowerInvariant()] = $entry.name
    }
}

$loadOrder = New-Object System.Collections.ArrayList
if (-not [string]::IsNullOrWhiteSpace($LoadOrderPath)) {
    if (-not (Test-Path -LiteralPath $LoadOrderPath -PathType Leaf)) {
        throw 'LoadOrderPath must be an existing text file.'
    }

    foreach ($line in (Get-Content -LiteralPath $LoadOrderPath)) {
        $candidate = $line.Trim()
        if ($candidate.StartsWith('#') -or [string]::IsNullOrWhiteSpace($candidate)) {
            continue
        }
        $candidate = $candidate.TrimStart('*')
        $key = $candidate.ToLowerInvariant()
        if ($pluginsByName.ContainsKey($key)) {
            [void]$loadOrder.Add($pluginsByName[$key])
        }
    }
}

$manifest = [pscustomobject][ordered]@{
    schema = 'skyrim-engineering.creations/v1'
    files = @($entries)
    loadOrder = @($loadOrder)
}

if ($Json) {
    $manifest | ConvertTo-Json -Depth 5 -Compress
}
else {
    $manifest
}
