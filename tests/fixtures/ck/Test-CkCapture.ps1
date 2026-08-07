[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Submission,
    [Parameter(Mandatory)][string]$CaptureOutput
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-Contract([bool]$Condition, [string]$Message) {
    if (-not $Condition) { throw "CK capture rejected: $Message" }
}

function Get-StableHash([string]$Path) {
    Assert-Contract (Test-Path -LiteralPath $Path -PathType Leaf) 'a required input file is absent'
    (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
}

function Get-TextHash([string]$Text) {
    $bytes = [Text.UTF8Encoding]::new($false).GetBytes($Text)
    $sha = [Security.Cryptography.SHA256]::Create()
    try { ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '') }
    finally { $sha.Dispose() }
}

try {
    Assert-Contract (Test-Path -LiteralPath $Submission -PathType Leaf) 'submission JSON is absent'
    $s = Get-Content -Raw -LiteralPath $Submission | ConvertFrom-Json
    Assert-Contract ($s.schema -eq 'skyrim-engineering.qualification.creation-kit-submission/v1') 'submission schema is unsupported'

    $started = [DateTimeOffset]$s.startedAtUtc
    $captured = [DateTimeOffset]$s.capturedAtUtc
    $now = [DateTimeOffset]::UtcNow
    $started = $started.ToUniversalTime()
    $captured = $captured.ToUniversalTime()
    Assert-Contract ($started -le $captured) 'capture predates its run'
    Assert-Contract ((($now - $captured).TotalHours -le 24) -and (($captured - $now).TotalMinutes -le 5)) 'capture is stale or future-dated'

    Assert-Contract ($s.tools.creationKit.version -eq '1.6.1378.1') 'Creation Kit version is not 1.6.1378.1'
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($s.tools.xDump64.version)) 'xDump version is absent'
    foreach ($tool in @($s.tools.creationKit, $s.tools.xDump64)) {
        Assert-Contract ((Get-StableHash $tool.path) -eq $tool.sha256) 'tool hash does not match reviewed bytes'
    }

    Assert-Contract ($s.provenance.originalOnly -eq $true) 'plugin is not declared original-only'
    Assert-Contract ($s.provenance.licensedAssetsCommitted -eq $false) 'submission permits licensed assets in Git'
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($s.provenance.generator)) 'fixture generator provenance is absent'
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($s.provenance.reviewer)) 'named reviewer is absent'
    Assert-Contract (-not [string]::IsNullOrWhiteSpace($s.provenance.reviewFinding)) 'review finding is absent'

    Assert-Contract ($s.plugin.relativeName -eq 'SEG_CK_Practical3.esp') 'unexpected plugin identity'
    Assert-Contract ($s.plugin.activeFile -eq $s.plugin.relativeName) 'saved plugin was not the active file'
    Assert-Contract ($s.plugin.fullCloseConfirmed -eq $true -and $s.plugin.reopenConfirmed -eq $true) 'full close and reopen are not confirmed'
    Assert-Contract ((Get-StableHash $s.plugin.seedPath) -eq $s.plugin.seedSha256) 'seed hash changed'
    Assert-Contract ($s.plugin.seedSha256 -ne $s.plugin.postSaveSha256) 'CK save did not change the seed'
    Assert-Contract ($s.plugin.postSaveSha256 -eq $s.plugin.postReopenSha256) 'post-save and post-reopen plugin hashes differ'
    Assert-Contract ((Get-StableHash $s.plugin.path) -eq $s.plugin.postReopenSha256) 'current plugin is not the reviewed reopened file'

    Assert-Contract (@($s.masters).Count -gt 0) 'master list is absent'
    $protected = @($s.protectedInputs)
    Assert-Contract (@($protected | Where-Object kind -eq 'master').Count -gt 0) 'protected master hashes are absent'
    Assert-Contract (@($protected | Where-Object kind -eq 'ini').Count -gt 0) 'protected INI hashes are absent'
    foreach ($input in $protected) {
        Assert-Contract ($input.kind -in @('master', 'ini')) 'unsupported protected-input kind'
        Assert-Contract (-not [IO.Path]::IsPathRooted($input.relativeName)) 'protected evidence contains an absolute display path'
        Assert-Contract ((Get-StableHash $input.path) -eq $input.sha256) 'protected master or INI changed'
    }
    foreach ($master in @($s.masters)) {
        Assert-Contract ($master -in @($protected | Where-Object kind -eq 'master' | ForEach-Object relativeName)) 'master list is not bound to protected hashes'
    }

    $e = $s.structuredEvidence
    Assert-Contract ($e.quest.ownerPlugin -eq $s.plugin.relativeName -and -not [string]::IsNullOrWhiteSpace($e.quest.editorId)) 'quest ownership is incomplete'
    Assert-Contract ($e.referenceAlias.quest -eq $e.quest.editorId -and -not [string]::IsNullOrWhiteSpace($e.referenceAlias.fillType)) 'reference alias relationship is incomplete'
    Assert-Contract ($e.stageObjective.quest -eq $e.quest.editorId -and $e.stageObjective.stage -ge 0 -and $e.stageObjective.objectiveIndex -ge 0) 'stage/objective evidence is incomplete'
    Assert-Contract ($e.condition.count -gt 0 -and $e.condition.fieldPath -match 'CTDA') 'condition evidence is incomplete'
    Assert-Contract ($e.relationships.actorPackage -and $e.relationships.questDialogue -and $e.relationships.aliasQuest -and $e.relationships.cellReference) 'record relationships are incomplete'
    Assert-Contract ($e.package.ownerPlugin -eq $s.plugin.relativeName -and $e.package.procedureTreeConfigured) 'package ownership or procedure tree is incomplete'
    Assert-Contract ($e.navmesh.ownerPlugin -eq $s.plugin.relativeName -and $e.navmesh.finalized -and -not [string]::IsNullOrWhiteSpace($e.navmesh.cell)) 'navmesh ownership/finalization is incomplete'

    $check = & $s.tools.xDump64.path -check $s.plugin.path 2>&1
    Assert-Contract ($LASTEXITCODE -eq 0) ("xDump check failed: " + ($check -join ' '))
    $dump = & $s.tools.xDump64.path -dump $s.plugin.path 2>&1
    Assert-Contract ($LASTEXITCODE -eq 0) ("xDump dump failed: " + ($dump -join ' '))
    $dumpText = $dump -join [Environment]::NewLine
    Assert-Contract ((Get-TextHash $dumpText) -eq $e.rawDumpSha256) 'structured evidence is not bound to the xDump output'
    Assert-Contract ((Get-StableHash $s.plugin.path) -eq $s.plugin.postReopenSha256) 'xDump modified the plugin'

    $capture = [ordered]@{
        schema = 'skyrim-engineering.qualification.creation-kit/v1'
        result = 'UNVERIFIED_SUBMISSION'
        runId = $s.runId
        startedAtUtc = $started.ToUniversalTime().ToString('o')
        capturedAtUtc = $captured.ToUniversalTime().ToString('o')
        tools = [ordered]@{
            creationKit = [ordered]@{ version = $s.tools.creationKit.version; sha256 = $s.tools.creationKit.sha256 }
            xDump64 = [ordered]@{ version = $s.tools.xDump64.version; sha256 = $s.tools.xDump64.sha256 }
        }
        plugin = [ordered]@{
            relativeName = $s.plugin.relativeName; seedSha256 = $s.plugin.seedSha256
            postSaveSha256 = $s.plugin.postSaveSha256; postReopenSha256 = $s.plugin.postReopenSha256
            activeFile = $s.plugin.activeFile; fullCloseConfirmed = $true; reopenConfirmed = $true
        }
        masters = @($s.masters)
        protectedInputs = @($protected | ForEach-Object { [ordered]@{ kind = $_.kind; relativeName = $_.relativeName; sha256 = $_.sha256 } })
        records = $e
        review = [ordered]@{ reviewer = $s.provenance.reviewer; finding = $s.provenance.reviewFinding; originalOnly = $true }
        cleanup = [ordered]@{ required = $true; instruction = 'Delete only the named disposable run root after retaining this sanitized capture.' }
    }
    $parent = Split-Path -Parent ([IO.Path]::GetFullPath($CaptureOutput))
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    $capture | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $CaptureOutput -Encoding UTF8
    'RESULT=UNVERIFIED_SUBMISSION'
}
catch {
    if (Test-Path -LiteralPath $CaptureOutput) { Remove-Item -LiteralPath $CaptureOutput -Force }
    Write-Error $_
    exit 2
}
