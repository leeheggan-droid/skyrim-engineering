[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$V1Pex,
    [Parameter(Mandatory)][string]$V2Pex,
    [Parameter(Mandatory)][string]$StagingRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-ExistingFile {
    param([string]$Path, [string]$Role)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Role does not exist: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-SafeTempDestination {
    param([string]$Path)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not $full.StartsWith('C:\tmp\', [StringComparison]::OrdinalIgnoreCase)) {
        throw "staging root must be a child of C:\tmp"
    }
    $full
}

$v1 = Resolve-ExistingFile $V1Pex 'V1 PEX'
$v2 = Resolve-ExistingFile $V2Pex 'V2 PEX'
if ([IO.Path]::GetFileName($v1) -cne 'SEG_RuntimeMigration.pex') { throw 'V1 PEX filename must be SEG_RuntimeMigration.pex' }
if ([IO.Path]::GetFileName($v2) -cne 'SEG_RuntimeMigration.pex') { throw 'V2 PEX filename must be SEG_RuntimeMigration.pex' }

$v1Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $v1).Hash
$v2Hash = (Get-FileHash -Algorithm SHA256 -LiteralPath $v2).Hash
if ($v1Hash -eq $v2Hash) { throw 'V1 and V2 PEX inputs are byte-identical' }

$destination = Resolve-SafeTempDestination $StagingRoot
if (Test-Path -LiteralPath $destination) { throw "staging root already exists: $destination" }

$v1Source = Join-Path $PSScriptRoot 'runtime-v1\SEG_RuntimeMigration.psc'
$v2Source = Join-Path $PSScriptRoot 'runtime-v2\SEG_RuntimeMigration.psc'
$v1Source = Resolve-ExistingFile $v1Source 'V1 source fixture'
$v2Source = Resolve-ExistingFile $v2Source 'V2 source fixture'

try {
    $v1Relative = 'versions\V1\Scripts\SEG_RuntimeMigration.pex'
    $v2Relative = 'versions\V2\Scripts\SEG_RuntimeMigration.pex'
    [IO.Directory]::CreateDirectory((Join-Path $destination 'versions\V1\Scripts')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $destination 'versions\V2\Scripts')) | Out-Null
    [IO.Directory]::CreateDirectory((Join-Path $destination 'capture')) | Out-Null
    Copy-Item -LiteralPath $v1 -Destination (Join-Path $destination $v1Relative)
    Copy-Item -LiteralPath $v2 -Destination (Join-Path $destination $v2Relative)

    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $destination $v1Relative)).Hash -ne $v1Hash) { throw 'staged V1 PEX hash mismatch' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $destination $v2Relative)).Hash -ne $v2Hash) { throw 'staged V2 PEX hash mismatch' }

    $manifest = [ordered]@{
        contractVersion = 1
        status = 'PREPARED'
        runtimeEvidenceCaptured = $false
        scriptName = 'SEG_RuntimeMigration'
        sources = [ordered]@{
            V1 = [ordered]@{ relativePath = 'tests/fixtures/papyrus/runtime-v1/SEG_RuntimeMigration.psc'; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $v1Source).Hash }
            V2 = [ordered]@{ relativePath = 'tests/fixtures/papyrus/runtime-v2/SEG_RuntimeMigration.psc'; sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $v2Source).Hash }
        }
        versions = [ordered]@{
            V1 = [ordered]@{ relativePath = $v1Relative; sha256 = $v1Hash; byteLength = (Get-Item -LiteralPath $v1).Length }
            V2 = [ordered]@{ relativePath = $v2Relative; sha256 = $v2Hash; byteLength = (Get-Item -LiteralPath $v2).Length }
        }
        requiredMarkers = [ordered]@{
            V1 = @('SEG_EVENT_OK', 'SEG_MIGRATION_OLD')
            V2 = @('SEG_MIGRATION_NEW')
        }
        limitations = 'Prepared original fixtures and hashes only; game launch, save/load, and migration remain human-operated and uncaptured.'
    }
    $manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $destination 'runtime-migration-manifest.json') -Encoding UTF8
    'RESULT=PASS status=PREPARED versions=V1,V2 runtime-evidence=false'
}
catch {
    if (Test-Path -LiteralPath $destination) { Remove-Item -LiteralPath $destination -Recurse -Force }
    throw
}
