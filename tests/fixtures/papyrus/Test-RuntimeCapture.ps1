[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$V1PapyrusLog,
    [Parameter(Mandatory)][string]$V2PapyrusLog,
    [Parameter(Mandatory)][string]$SaveBefore,
    [Parameter(Mandatory)][string]$SaveAfter,
    [Parameter(Mandatory)][string]$StageManifest,
    [Parameter(Mandatory)][string]$RuntimeEvidence,
    [Parameter(Mandatory)][string]$ProfileEvidence,
    [Parameter(Mandatory)][ValidatePattern('^[a-z0-9-]{8,64}$')][string]$RunId,
    [Parameter(Mandatory)][datetimeoffset]$V1PhaseUtc,
    [Parameter(Mandatory)][datetimeoffset]$V2PhaseUtc,
    [Parameter(Mandatory)][string]$CaptureOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
$minimumEssBytes = 1048576

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
function Resolve-ExistingFile { param([string]$Path,[string]$Role) if(-not(Test-Path -LiteralPath $Path -PathType Leaf)){throw "$Role does not exist"}; Assert-NoReparsePoint $Path; (Resolve-Path -LiteralPath $Path).Path }
function Read-Json { param([string]$Path,[string]$Role) try { Get-Content -Raw -LiteralPath (Resolve-ExistingFile $Path $Role) | ConvertFrom-Json -ErrorAction Stop } catch { throw "$Role is not valid JSON" } }
function Get-Sha256 { param([string]$Path) (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash }
function Require-ExactLine { param([string]$Text,[string]$Line,[string]$Phase) if($Text -notmatch ('(?m)^' + [regex]::Escape($Line) + '\r?$')){throw "$Phase log is missing exact marker $Line"} }
function Reject-Text { param([string]$Text,[string]$Marker,[string]$Phase) if($Text -match [regex]::Escape($Marker)){throw "$Phase log contains out-of-phase marker $Marker"} }
function Assert-Ess {
    param([string]$Path,[datetime]$NotBefore,[datetime]$Before,[string]$Role)
    if ([IO.Path]::GetExtension($Path) -cne '.ess') { throw "$Role must use .ess extension" }
    $item = Get-Item -LiteralPath $Path
    if ($item.Length -lt $minimumEssBytes) { throw "$Role is below conservative ESS minimum size 1048576" }
    $stream = [IO.File]::OpenRead($Path)
    try { $bytes = New-Object byte[] 13; if($stream.Read($bytes,0,13)-ne 13 -or [Text.Encoding]::ASCII.GetString($bytes)-cne 'TESV_SAVEGAME'){throw "$Role lacks TESV_SAVEGAME signature"} }
    finally { $stream.Dispose() }
    if ($item.LastWriteTimeUtc -lt $NotBefore -or $item.LastWriteTimeUtc -ge $Before) { throw "$Role LastWriteTimeUtc is outside its phase" }
}

$v1Utc = $V1PhaseUtc.UtcDateTime
$v2Utc = $V2PhaseUtc.UtcDateTime
if ($v2Utc -le $v1Utc) { throw 'phase timestamps must be ordered UTC values' }
$v1LogPath=Resolve-ExistingFile $V1PapyrusLog 'V1 Papyrus log'; $v2LogPath=Resolve-ExistingFile $V2PapyrusLog 'V2 Papyrus log'
$beforePath=Resolve-ExistingFile $SaveBefore 'pre-migration save'; $afterPath=Resolve-ExistingFile $SaveAfter 'post-migration save'; $manifestPath=Resolve-ExistingFile $StageManifest 'stage manifest'
$manifest=Read-Json $manifestPath 'stage manifest'; $runtime=Read-Json $RuntimeEvidence 'runtime evidence'; $profile=Read-Json $ProfileEvidence 'profile evidence'
if($manifest.contractVersion-ne 2-or$manifest.status-ne'PREPARED'-or$manifest.runtimeEvidenceCaptured-ne$false){throw 'stage manifest is not an unclaimed PREPARED v2 contract'}
if($runtime.runtimeVersion-cne'1.6.1170.0'-or$runtime.executableSha256-cnotmatch'^[A-F0-9]{64}$'){throw 'runtimeVersion/executableSha256 evidence is invalid'}
if($profile.anonymousProfileId-cnotmatch'^[a-z0-9-]{8,64}$'-or$profile.profileIsolated-ne$true-or$profile.liveDataModified-ne$false-or$profile.bEnableLogging-ne$true-or$profile.bEnableTrace-ne$true){throw 'anonymous isolated profile/logging evidence is invalid'}
if(@($profile.loadOrder)-notcontains[IO.Path]::GetFileName($manifest.plugin.relativePath)){throw 'loadOrder omits the bound plugin'}

$stageRoot=Split-Path -Parent $manifestPath
foreach($version in @('V1','V2')){$entry=$manifest.versions.$version;$staged=[IO.Path]::GetFullPath((Join-Path $stageRoot $entry.relativePath));if(-not$staged.StartsWith(([IO.Path]::GetFullPath($stageRoot).TrimEnd('\')+'\'),[StringComparison]::OrdinalIgnoreCase)){throw 'staged path escapes root'};Assert-NoReparsePoint $staged;if((Get-Sha256 $staged)-cne$entry.pexSha256){throw "$version staged PEX hash mismatch"}}

$v1Text=Get-Content -Raw -LiteralPath $v1LogPath; $v2Text=Get-Content -Raw -LiteralPath $v2LogPath
Require-ExactLine $v1Text 'SEG_EVENT_OK schema=1' 'V1'; Require-ExactLine $v1Text 'SEG_MIGRATION_OLD schema=1' 'V1'; Reject-Text $v1Text 'SEG_MIGRATION_NEW' 'V1'; Reject-Text $v1Text 'schema=2' 'V1'
Require-ExactLine $v2Text 'SEG_EVENT_OK schema=2' 'V2'; Require-ExactLine $v2Text 'SEG_MIGRATION_NEW from=1 to=2' 'V2'; Reject-Text $v2Text 'SEG_MIGRATION_OLD' 'V2'; Reject-Text $v2Text 'schema=1' 'V2'
if((Get-Item $v1LogPath).LastWriteTimeUtc-lt$v1Utc-or(Get-Item $v1LogPath).LastWriteTimeUtc-ge$v2Utc){throw 'V1 log freshness is outside phase'}
$captureTime=[datetime]::UtcNow.AddMinutes(5); if((Get-Item $v2LogPath).LastWriteTimeUtc-lt$v2Utc-or(Get-Item $v2LogPath).LastWriteTimeUtc-ge$captureTime){throw 'V2 log freshness is outside phase'}
Assert-Ess $beforePath $v1Utc $v2Utc 'pre-migration save'; Assert-Ess $afterPath $v2Utc $captureTime 'post-migration save'
$beforeHash=Get-Sha256 $beforePath; $afterHash=Get-Sha256 $afterPath;if($beforeHash-eq$afterHash){throw 'pre/post save hashes are identical'}

$capturePath=[IO.Path]::GetFullPath($CaptureOutput);if(-not$capturePath.StartsWith('C:\tmp\',[StringComparison]::OrdinalIgnoreCase)){throw 'capture output must be a child of C:\tmp'};Assert-NoReparsePoint $capturePath;if(Test-Path -LiteralPath $capturePath){throw 'capture output already exists'};[IO.Directory]::CreateDirectory((Split-Path -Parent $capturePath))|Out-Null
$capture=[ordered]@{contractVersion=2;result='UNVERIFIED_SUBMISSION';humanReviewRequired=$true;runId=$RunId;anonymousProfileId=$profile.anonymousProfileId;phaseUtc=[ordered]@{V1=$v1Utc.ToString('o');V2=$v2Utc.ToString('o')};runtime=[ordered]@{runtimeVersion=$runtime.runtimeVersion;executableSha256=$runtime.executableSha256};stageManifestSha256=Get-Sha256 $manifestPath;plugin=$manifest.plugin;pex=$manifest.versions;markers=[ordered]@{SEG_EVENT_OK='V1-and-V2-exact-schema';SEG_MIGRATION_OLD='V1';SEG_MIGRATION_NEW='V2'};logs=[ordered]@{V1=[ordered]@{sha256=Get-Sha256 $v1LogPath};V2=[ordered]@{sha256=Get-Sha256 $v2LogPath}};saves=[ordered]@{before=[ordered]@{sha256=$beforeHash;byteLength=(Get-Item $beforePath).Length};after=[ordered]@{sha256=$afterHash;byteLength=(Get-Item $afterPath).Length}};limitations='Byte and metadata validation cannot prove human operation, plugin construction, runtime provenance, or successful migration; named human review remains required.'}
$capture|ConvertTo-Json -Depth 10|Set-Content -LiteralPath $capturePath -Encoding UTF8
"RESULT=PASS contract=UNVERIFIED_SUBMISSION run=$RunId"
