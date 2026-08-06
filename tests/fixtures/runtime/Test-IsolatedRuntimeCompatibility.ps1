[CmdletBinding()]
param(
    [Parameter(Mandatory)] [string] $SkyrimExe,
    [Parameter(Mandatory)] [string] $SkseRoot,
    [Parameter(Mandatory)] [string] $AddressLibraryRoot,
    [Parameter(Mandatory)] [string] $IsolatedProfile,
    [Parameter(Mandatory)]
    [ValidatePattern('^[A-Fa-f0-9]{64}$')]
    [string] $ExpectedSkseSha256,
    [version] $ProbeRuntime
)

$ErrorActionPreference = 'Stop'

$profilePath = [IO.Path]::GetFullPath($IsolatedProfile)
if (-not $profilePath.StartsWith('C:\tmp\', [StringComparison]::OrdinalIgnoreCase)) {
    throw "Refusing non-isolated destination: $profilePath"
}

$exe = Get-Item -LiteralPath $SkyrimExe
$runtime = [version]$exe.VersionInfo.FileVersion
if ($ProbeRuntime -and $ProbeRuntime -ne $runtime) {
    Write-Output "REJECT probe=$ProbeRuntime installed=$runtime reason=runtime-mismatch"
    exit 2
}

$runtimeStem = '{0}-{1}-{2}-{3}' -f $runtime.Major, $runtime.Minor, $runtime.Build, $runtime.Revision
$skseName = 'skse64_{0}_{1}_{2}.dll' -f $runtime.Major, $runtime.Minor, $runtime.Build
$skseCandidates = @(Get-ChildItem -LiteralPath $SkseRoot -Recurse -File -Filter $skseName)
if ($skseCandidates.Count -ne 1) {
    throw "Expected exactly one SKSE runtime DLL named $skseName; found $($skseCandidates.Count)"
}
$skse = $skseCandidates[0]

$skseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $skse.FullName).Hash
if ($skseHash -ne $ExpectedSkseSha256.ToUpperInvariant()) {
    throw "SKSE SHA256 mismatch: expected=$($ExpectedSkseSha256.ToUpperInvariant()) actual=$skseHash"
}

$skseVersion = $skse.VersionInfo.FileVersion -replace '[, ]', '.' -replace '\.+', '.'
if ([version]$skseVersion -ne [version]'0.2.2.6') {
    throw "Unexpected SKSE build: $skseVersion"
}

$plugins = Join-Path $AddressLibraryRoot 'SKSE\Plugins'
$primaryName = "versionlib-$runtimeStem.bin"
$alternateName = "versionlib-$runtimeStem-1.bin"
$primary = Join-Path $plugins $primaryName
$alternate = Join-Path $plugins $alternateName
if (-not (Test-Path -LiteralPath $primary -PathType Leaf)) {
    throw "Missing exact Address Library database: $primaryName"
}
if (-not (Test-Path -LiteralPath $alternate -PathType Leaf)) {
    throw "Missing alternate exact-runtime database: $alternateName"
}

$destination = Join-Path $profilePath 'Data\SKSE\Plugins'
$null = New-Item -ItemType Directory -Path $destination -Force
Copy-Item -LiteralPath $primary, $alternate -Destination $destination -Force

$primaryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $primary).Hash
$alternateHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $alternate).Hash
Write-Output "ACCEPT runtime=$runtime skse=2.2.6 database=$primaryName"
Write-Output "SKSE_SHA256=$skseHash"
Write-Output "PRIMARY_SHA256=$primaryHash"
Write-Output "ALTERNATE_SHA256=$alternateHash"
