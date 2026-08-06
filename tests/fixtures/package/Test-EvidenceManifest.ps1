[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RepositoryRoot,
    [Parameter(Mandatory)][string]$Manifest,
    [Parameter(Mandatory)][string]$Destination,
    [switch]$SimulateMismatch,
    [switch]$Rollback
)
$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath($RepositoryRoot)
$destinationFull = [IO.Path]::GetFullPath($Destination)
$tmpRoot = [IO.Path]::GetFullPath('C:\tmp')
if (-not $destinationFull.StartsWith($tmpRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'Destination must be an isolated child of C:\tmp'
}
$quarantine = "$destinationFull.quarantine"
if ($Rollback) {
    foreach ($target in @($destinationFull, $quarantine)) {
        if (Test-Path -LiteralPath $target) { Remove-Item -LiteralPath $target -Recurse -Force }
    }
    Write-Output 'ROLLBACK=PASS'
    exit 0
}
$m = Get-Content -Raw -LiteralPath $Manifest | ConvertFrom-Json
if ($m.algorithm -ne 'SHA256' -or $m.license.spdx -ne 'GPL-3.0-or-later') { throw 'Manifest algorithm or licence mismatch' }
$listed = @($m.files.path)
for($i=1;$i -lt $listed.Count;$i++){ if([StringComparer]::Ordinal.Compare($listed[$i-1],$listed[$i]) -ge 0){ throw 'Manifest paths are not unique ordinal-sort order' } }
$discovered = @(@(Get-Item (Join-Path $root 'LICENSE')) + @(Get-ChildItem (Join-Path $root 'docs\expertise'), (Join-Path $root 'tests') -Recurse -File) |
    ForEach-Object { [IO.Path]::GetRelativePath($root, $_.FullName).Replace('\','/') } |
    Where-Object { $_ -notin @($m.excludedControlFiles) })
if ($discovered.Count -ne $listed.Count -or @(Compare-Object $discovered $listed -CaseSensitive).Count) { throw 'Manifest is not the exact release file set' }
if (Test-Path -LiteralPath $destinationFull) { throw 'Destination already exists' }
New-Item -ItemType Directory -Path $destinationFull | Out-Null
foreach ($entry in $m.files) {
    $source = Join-Path $root $entry.path
    $actual = Get-FileHash -Algorithm SHA256 -LiteralPath $source
    if ($actual.Hash -ne $entry.sha256 -or (Get-Item $source).Length -ne $entry.bytes) { throw "Source byte mismatch: $($entry.path)" }
    $target = Join-Path $destinationFull $entry.path
    New-Item -ItemType Directory -Path (Split-Path -Parent $target) -Force | Out-Null
    Copy-Item -LiteralPath $source -Destination $target
}
if ($SimulateMismatch) { Add-Content -LiteralPath (Join-Path $destinationFull $m.files[0].path) -Value 'tamper' }
$bad = @($m.files | Where-Object {
    $staged = Join-Path $destinationFull $_.path
    (Get-FileHash -Algorithm SHA256 -LiteralPath $staged).Hash -ne $_.sha256 -or (Get-Item $staged).Length -ne $_.bytes
})
if ($bad.Count) {
    Move-Item -LiteralPath $destinationFull -Destination $quarantine
    Write-Output "QUARANTINE=PASS count=$($bad.Count) path=$quarantine"
    exit 2
}
Write-Output "ACCEPT=PASS files=$($m.files.Count) destination=$destinationFull"
