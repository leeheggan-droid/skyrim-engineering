[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$V1PapyrusLog,
    [Parameter(Mandatory)][string]$V2PapyrusLog,
    [Parameter(Mandatory)][string]$SaveBefore,
    [Parameter(Mandatory)][string]$SaveAfter,
    [Parameter(Mandatory)][string]$StageManifest,
    [Parameter(Mandatory)][string]$CaptureOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Resolve-ExistingFile {
    param([string]$Path, [string]$Role)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Role does not exist: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}

function Require-Marker {
    param([string]$Text, [string]$Marker, [string]$Phase)
    if ($Text -notmatch [regex]::Escape($Marker)) { throw "$Phase log is missing $Marker" }
}

function Reject-Marker {
    param([string]$Text, [string]$Marker, [string]$Phase)
    if ($Text -match [regex]::Escape($Marker)) { throw "$Phase log contains out-of-phase marker $Marker" }
}

$v1LogPath = Resolve-ExistingFile $V1PapyrusLog 'V1 Papyrus log'
$v2LogPath = Resolve-ExistingFile $V2PapyrusLog 'V2 Papyrus log'
$beforePath = Resolve-ExistingFile $SaveBefore 'pre-migration save'
$afterPath = Resolve-ExistingFile $SaveAfter 'post-migration save'
$manifestPath = Resolve-ExistingFile $StageManifest 'stage manifest'
$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.contractVersion -ne 1 -or $manifest.status -ne 'PREPARED' -or $manifest.runtimeEvidenceCaptured -ne $false) {
    throw 'stage manifest is not an unclaimed PREPARED contract'
}
if ($manifest.scriptName -ne 'SEG_RuntimeMigration') { throw 'stage manifest names the wrong script' }
if ($manifest.versions.V1.sha256 -notmatch '^[A-F0-9]{64}$' -or $manifest.versions.V2.sha256 -notmatch '^[A-F0-9]{64}$') { throw 'stage manifest contains an invalid PEX hash' }
if ($manifest.versions.V1.sha256 -eq $manifest.versions.V2.sha256) { throw 'stage manifest binds V1 and V2 to identical PEX bytes' }

$stageRoot = Split-Path -Parent $manifestPath
foreach ($version in @('V1', 'V2')) {
    $entry = $manifest.versions.$version
    $stagedPath = [IO.Path]::GetFullPath((Join-Path $stageRoot $entry.relativePath))
    $safePrefix = [IO.Path]::GetFullPath($stageRoot).TrimEnd('\') + '\'
    if (-not $stagedPath.StartsWith($safePrefix, [StringComparison]::OrdinalIgnoreCase)) { throw "$version staged path escapes stage root" }
    if (-not (Test-Path -LiteralPath $stagedPath -PathType Leaf)) { throw "$version staged PEX is missing" }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $stagedPath).Hash -ne $entry.sha256) { throw "$version staged PEX hash mismatch" }
}

$v1LogText = Get-Content -Raw -LiteralPath $v1LogPath
$v2LogText = Get-Content -Raw -LiteralPath $v2LogPath
Require-Marker $v1LogText 'SEG_EVENT_OK' 'V1'
Require-Marker $v1LogText 'SEG_MIGRATION_OLD' 'V1'
Reject-Marker $v1LogText 'SEG_MIGRATION_NEW' 'V1'
Require-Marker $v2LogText 'SEG_MIGRATION_NEW' 'V2'
Reject-Marker $v2LogText 'SEG_MIGRATION_OLD' 'V2'

$beforeHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $beforePath).Hash
$afterHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $afterPath).Hash
if ($beforeHash -eq $afterHash) { throw 'pre/post save hashes are identical' }

$capturePath = [IO.Path]::GetFullPath($CaptureOutput)
if (-not $capturePath.StartsWith('C:\tmp\', [StringComparison]::OrdinalIgnoreCase)) { throw 'capture output must be a child of C:\tmp' }
if (Test-Path -LiteralPath $capturePath) { throw 'capture output already exists' }
$captureParent = Split-Path -Parent $capturePath
if (-not (Test-Path -LiteralPath $captureParent -PathType Container)) { [IO.Directory]::CreateDirectory($captureParent) | Out-Null }

$capture = [ordered]@{
    contractVersion = 1
    result = 'UNVERIFIED_SUBMISSION'
    humanOperatedRuntimeRequired = $true
    stageManifestSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $manifestPath).Hash
    pex = [ordered]@{
        V1 = [ordered]@{ sha256 = $manifest.versions.V1.sha256; byteLength = $manifest.versions.V1.byteLength }
        V2 = [ordered]@{ sha256 = $manifest.versions.V2.sha256; byteLength = $manifest.versions.V2.byteLength }
    }
    markers = [ordered]@{
        SEG_EVENT_OK = 'V1'
        SEG_MIGRATION_OLD = 'V1'
        SEG_MIGRATION_NEW = 'V2'
    }
    logs = [ordered]@{
        V1 = [ordered]@{ sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $v1LogPath).Hash }
        V2 = [ordered]@{ sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $v2LogPath).Hash }
    }
    saves = [ordered]@{
        before = [ordered]@{ sha256 = $beforeHash; byteLength = (Get-Item -LiteralPath $beforePath).Length }
        after = [ordered]@{ sha256 = $afterHash; byteLength = (Get-Item -LiteralPath $afterPath).Length }
    }
    limitations = 'Validates staged bytes, phase-separated markers, and save hashes; it cannot independently prove who operated the game or that hash change alone represents a successful migration.'
}
$capture | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $capturePath -Encoding UTF8
"RESULT=PASS contract=UNVERIFIED_SUBMISSION before=$beforeHash after=$afterHash"
