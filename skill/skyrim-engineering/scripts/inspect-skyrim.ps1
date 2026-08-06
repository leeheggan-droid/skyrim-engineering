[CmdletBinding()]
param(
    [string]$SteamRoot,
    [string]$GameRoot,
    [switch]$Json
)

Set-StrictMode -Version Latest

$commonModule = Join-Path $PSScriptRoot 'SkyrimEngineering.Common.psm1'
Import-Module -Name $commonModule -Force -ErrorAction Stop

if (-not [string]::IsNullOrWhiteSpace($SteamRoot)) {
    $null = Resolve-SkyrimInstall -SteamRoot $SteamRoot
}

if ([string]::IsNullOrWhiteSpace($GameRoot)) {
    $GameRoot = (Resolve-SkyrimInstall -SteamRoot $SteamRoot).FullName
}

$gameRootFull = [System.IO.Path]::GetFullPath($GameRoot)
$executablePath = Join-Path $gameRootFull 'SkyrimSE.exe'

if (Test-Path -LiteralPath $executablePath -PathType Leaf) {
    $runtime = (Get-Item -LiteralPath $executablePath -ErrorAction Stop).VersionInfo.FileVersion
    if ([string]::IsNullOrWhiteSpace($runtime)) {
        throw 'SkyrimSE.exe does not expose a file version.'
    }
}
else {
    $repositoryRoot = Split-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) -Parent
    $fixtureRoot = [System.IO.Path]::GetFullPath((Join-Path $repositoryRoot 'tests\fixtures'))
    $fixturePrefix = $fixtureRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $gameRootFull.StartsWith($fixturePrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'SkyrimSE.exe was not found. Synthetic version data is permitted only below tests/fixtures.'
    }

    $syntheticVersionPath = Join-Path $gameRootFull 'SkyrimSE.exe.version.json'
    if (-not (Test-Path -LiteralPath $syntheticVersionPath -PathType Leaf)) {
        throw 'SkyrimSE.exe was not found and the approved synthetic version fixture is absent.'
    }

    $runtime = (Get-Content -LiteralPath $syntheticVersionPath -Raw -ErrorAction Stop | ConvertFrom-Json).fileVersion
    if ([string]::IsNullOrWhiteSpace($runtime)) {
        throw 'Synthetic Skyrim version fixture does not contain fileVersion.'
    }
}

$inspection = [ordered]@{
    schema = 'skyrim-engineering.inspect/v1'
    store = 'Steam'
    runtime = [string]$runtime
    executable = 'SkyrimSE.exe'
}

if ($Json) {
    $inspection | ConvertTo-Json -Depth 3 -Compress
}
else {
    [pscustomobject]$inspection
}
