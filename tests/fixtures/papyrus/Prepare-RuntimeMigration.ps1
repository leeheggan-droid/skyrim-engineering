[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$V1Pex,
    [Parameter(Mandatory)][string]$V2Pex,
    [Parameter(Mandatory)][string]$Plugin,
    [Parameter(Mandatory)][string]$PluginEvidence,
    [Parameter(Mandatory)][string]$CompilerEvidence,
    [Parameter(Mandatory)][string]$StagingRoot
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-NoReparsePoint {
    param([string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    if (-not (Test-Path -LiteralPath $current)) { $current = Split-Path -Parent $current }
    while ($current) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'ReparsePoint paths are refused' }
        }
        $parent = Split-Path -Parent $current
        if (-not $parent -or $parent -eq $current) { break }
        $current = $parent
    }
}

function Resolve-ExistingFile {
    param([string]$Path, [string]$Role)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Role does not exist" }
    Assert-NoReparsePoint $Path
    (Resolve-Path -LiteralPath $Path).Path
}

function Read-EvidenceJson {
    param([string]$Path, [string]$Role)
    $resolved = Resolve-ExistingFile $Path $Role
    try { Get-Content -Raw -LiteralPath $resolved | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "$Role is not valid JSON" }
}

function Get-Sha256 { param([string]$Path) (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }

$destination = [IO.Path]::GetFullPath($StagingRoot).TrimEnd('\')
if (-not $destination.StartsWith('C:\tmp\', [StringComparison]::OrdinalIgnoreCase)) { throw 'staging root must be a child of C:\tmp' }
Assert-NoReparsePoint $destination
if (Test-Path -LiteralPath $destination) { throw 'staging root already exists' }

$v1 = Resolve-ExistingFile $V1Pex 'V1 PEX'
$v2 = Resolve-ExistingFile $V2Pex 'V2 PEX'
$pluginPath = Resolve-ExistingFile $Plugin 'original plugin'
if ([IO.Path]::GetFileName($v1) -cne 'SEG_RuntimeMigration.pex' -or [IO.Path]::GetFileName($v2) -cne 'SEG_RuntimeMigration.pex') { throw 'PEX filenames must be SEG_RuntimeMigration.pex' }
if ([IO.Path]::GetExtension($pluginPath) -cne '.esp') { throw 'original plugin must be an ESP' }
$pluginHeader = [IO.File]::ReadAllBytes($pluginPath)[0..3]
if ([Text.Encoding]::ASCII.GetString($pluginHeader) -cne 'TES4') { throw 'plugin lacks a TES4 header' }

$v1Hash = Get-Sha256 $v1
$v2Hash = Get-Sha256 $v2
$pluginHash = Get-Sha256 $pluginPath
if ($v1Hash -eq $v2Hash) { throw 'V1 and V2 PEX inputs are byte-identical' }

$pluginRecord = Read-EvidenceJson $PluginEvidence 'plugin evidence'
if ($pluginRecord.originalOnly -ne $true -or $pluginRecord.pluginSha256 -cne $pluginHash -or
    $pluginRecord.questFormId -cnotmatch '^0x[0-9A-F]{8}$' -or $pluginRecord.scriptName -cne 'SEG_RuntimeMigration' -or
    $pluginRecord.attachment -cne 'Quest' -or $pluginRecord.activation -cne 'start-game-enabled') {
    throw 'plugin evidence does not bind the required original Start Game Enabled Quest attachment'
}

$v1Source = Resolve-ExistingFile (Join-Path $PSScriptRoot 'runtime-v1\SEG_RuntimeMigration.psc') 'V1 source fixture'
$v2Source = Resolve-ExistingFile (Join-Path $PSScriptRoot 'runtime-v2\SEG_RuntimeMigration.psc') 'V2 source fixture'
$compiler = Read-EvidenceJson $CompilerEvidence 'compiler evidence'
if ($compiler.compilerSha256 -cnotmatch '^[A-F0-9]{64}$' -or $compiler.commandSha256 -cnotmatch '^[A-F0-9]{64}$') { throw 'compiler provenance hashes are invalid' }
foreach ($phase in @(@('V1',$v1Source,$v1Hash), @('V2',$v2Source,$v2Hash))) {
    $entry = $compiler.versions.($phase[0])
    if ($entry.sourceSha256 -cne (Get-Sha256 $phase[1]) -or $entry.pexSha256 -cne $phase[2]) { throw "$($phase[0]) compiler/source/PEX provenance mismatch" }
}

try {
    $pluginName = [IO.Path]::GetFileName($pluginPath)
    foreach ($version in @('V1','V2')) {
        [IO.Directory]::CreateDirectory((Join-Path $destination "versions\$version\Scripts")) | Out-Null
        Copy-Item -LiteralPath $pluginPath -Destination (Join-Path $destination "versions\$version\$pluginName")
    }
    Copy-Item -LiteralPath $v1 -Destination (Join-Path $destination 'versions\V1\Scripts\SEG_RuntimeMigration.pex')
    Copy-Item -LiteralPath $v2 -Destination (Join-Path $destination 'versions\V2\Scripts\SEG_RuntimeMigration.pex')
    [IO.Directory]::CreateDirectory((Join-Path $destination 'capture')) | Out-Null

    $manifest = [ordered]@{
        contractVersion = 2; status = 'PREPARED'; runtimeEvidenceCaptured = $false; scriptName = 'SEG_RuntimeMigration'
        requiredRuntime = [ordered]@{ runtimeVersion = '1.6.1170.0' }
        plugin = [ordered]@{ relativePath = "versions/V1/$pluginName"; pluginSha256 = $pluginHash; originalOnly = $true; questFormId = $pluginRecord.questFormId; attachment = 'Quest'; activation = 'start-game-enabled' }
        compiler = [ordered]@{ compilerSha256 = $compiler.compilerSha256; commandSha256 = $compiler.commandSha256 }
        sources = [ordered]@{ V1 = [ordered]@{ sourceSha256 = Get-Sha256 $v1Source }; V2 = [ordered]@{ sourceSha256 = Get-Sha256 $v2Source } }
        versions = [ordered]@{
            V1 = [ordered]@{ relativePath = 'versions/V1/Scripts/SEG_RuntimeMigration.pex'; pexSha256 = $v1Hash; byteLength = (Get-Item $v1).Length }
            V2 = [ordered]@{ relativePath = 'versions/V2/Scripts/SEG_RuntimeMigration.pex'; pexSha256 = $v2Hash; byteLength = (Get-Item $v2).Length }
        }
        requiredMarkers = [ordered]@{ V1 = @('SEG_EVENT_OK schema=1','SEG_MIGRATION_OLD schema=1'); V2 = @('SEG_EVENT_OK schema=2','SEG_MIGRATION_NEW from=1 to=2') }
        limitations = 'Preparation binds submitted metadata and bytes; a human reviewer must verify original plugin construction, compiler provenance, and live operation.'
    }
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $destination 'runtime-migration-manifest.json') -Encoding UTF8
    'RESULT=PASS status=PREPARED contract=2 runtime-evidence=false'
}
catch {
    if (Test-Path -LiteralPath $destination) {
        $item = Get-Item -LiteralPath $destination -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'refusing cleanup of ReparsePoint staging root' }
        Remove-Item -LiteralPath $destination -Recurse -Force
    }
    throw
}
