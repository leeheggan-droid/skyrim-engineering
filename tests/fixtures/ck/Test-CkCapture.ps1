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

function Assert-FreshTempPath([string]$Path, [bool]$ParentMustExist) {
    Assert-Contract ([IO.Path]::IsPathFullyQualified($Path)) 'output path must be fully qualified'
    $full = [IO.Path]::GetFullPath($Path)
    Assert-Contract ($full.Equals($Path, [StringComparison]::OrdinalIgnoreCase)) 'output path must already be canonical'
    $temp = [IO.Path]::GetFullPath('C:\tmp').TrimEnd('\')
    Assert-Contract ($full.StartsWith($temp + '\', [StringComparison]::OrdinalIgnoreCase)) 'output must be a C:\tmp descendant'
    Assert-Contract (Test-Path -LiteralPath $temp -PathType Container) 'C:\tmp is absent'
    Assert-Contract ((((Get-Item -LiteralPath $temp -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)) 'C:\tmp is a reparse point'
    Assert-Contract (-not (Test-Path -LiteralPath $full)) 'output target already exists'
    $cursor = Split-Path -Parent $full
    if ($ParentMustExist) { Assert-Contract (Test-Path -LiteralPath $cursor -PathType Container) 'output parent is absent' }
    while ($cursor.StartsWith($temp + '\', [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $cursor) {
            $attributes = (Get-Item -LiteralPath $cursor -Force).Attributes
            Assert-Contract (($attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0) 'output has a reparse-point ancestor'
        }
        $cursor = Split-Path -Parent $cursor
    }
    $full
}

function Assert-PublicId([string]$Value, [string]$Name) {
    Assert-Contract ($Value -match '^[A-Za-z][A-Za-z0-9_]{0,127}$') "$Name is not a public-safe identifier"
}

$createdCapture = $false
try {
    $CaptureOutput = Assert-FreshTempPath $CaptureOutput $true
    Assert-Contract (Test-Path -LiteralPath $Submission -PathType Leaf) 'submission JSON is absent'
    $s = Get-Content -Raw -LiteralPath $Submission | ConvertFrom-Json
    Assert-Contract ($s.schema -eq 'skyrim-engineering.qualification.creation-kit-submission/v1') 'submission schema is unsupported'
    Assert-Contract ($s.runId -match '^[a-z][a-z0-9-]{2,63}$') 'run ID is not public-safe'

    $started = [DateTimeOffset]$s.startedAtUtc
    $captured = [DateTimeOffset]$s.capturedAtUtc
    $now = [DateTimeOffset]::UtcNow
    $started = $started.ToUniversalTime()
    $captured = $captured.ToUniversalTime()
    Assert-Contract ($started -le $captured) 'capture predates its run'
    Assert-Contract ((($now - $captured).TotalHours -le 24) -and (($captured - $now).TotalMinutes -le 5)) 'capture is stale or future-dated'

    Assert-Contract ($s.tools.creationKit.version -eq '1.6.1378.1') 'Creation Kit version is not 1.6.1378.1'
    Assert-Contract ($s.tools.xDump64.version -match '^[0-9]+(?:\.[0-9A-Za-z]+){1,4}$') 'xDump version is absent or unsafe'
    foreach ($tool in @($s.tools.creationKit, $s.tools.xDump64)) {
        Assert-Contract ($tool.sha256 -match '^[A-Fa-f0-9]{64}$') 'tool hash is malformed'
        Assert-Contract ((Get-StableHash $tool.path) -eq $tool.sha256) 'tool hash does not match reviewed bytes'
    }

    Assert-Contract ($s.provenance.originalOnly -eq $true) 'plugin is not declared original-only'
    Assert-Contract ($s.provenance.licensedAssetsCommitted -eq $false) 'submission permits licensed assets in Git'
    Assert-Contract ($s.provenance.generator -eq 'CreateOriginalFixture.pas') 'fixture generator provenance is invalid'
    Assert-Contract ($s.provenance.reviewerId -match '^reviewer-[a-z0-9-]{2,64}$') 'anonymous reviewer ID is absent or unsafe'
    Assert-Contract ($s.provenance.reviewFindingCode -eq 'original-only-reviewed') 'review finding code is invalid'

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
        $safeRelative = if ($input.kind -eq 'master') {
            $input.relativeName -match '^[A-Za-z][A-Za-z0-9_-]{0,100}\.(esm|esp|esl)$'
        } else {
            $input.relativeName -match '^[A-Za-z][A-Za-z0-9_-]{0,100}\.ini$'
        }
        Assert-Contract $safeRelative 'protected input name is not public-safe'
        Assert-Contract ($input.sha256 -match '^[A-Fa-f0-9]{64}$') 'protected input hash is malformed'
        Assert-Contract ((Get-StableHash $input.path) -eq $input.sha256) 'protected master or INI changed'
    }
    foreach ($master in @($s.masters)) {
        Assert-Contract ($master -match '^[A-Za-z][A-Za-z0-9_-]{0,100}\.(esm|esp|esl)$') 'master name is not public-safe'
        Assert-Contract ($master -in @($protected | Where-Object kind -eq 'master' | ForEach-Object relativeName)) 'master list is not bound to protected hashes'
    }

    $e = $s.structuredEvidence
    Assert-Contract ($e.rawDumpSha256 -match '^[A-Fa-f0-9]{64}$') 'raw dump hash is malformed'
    foreach ($identifier in @($e.quest.editorId, $e.referenceAlias.editorId, $e.referenceAlias.quest,
        $e.stageObjective.quest, $e.condition.owner, $e.package.editorId, $e.navmesh.cell)) {
        Assert-PublicId $identifier 'structured record identifier'
    }
    Assert-Contract ($e.referenceAlias.fillType -in @('SpecificReference', 'UniqueActor', 'CreatedReference')) 'alias fill type is unsupported'
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
        records = [ordered]@{
            rawDumpSha256 = $e.rawDumpSha256
            quest = [ordered]@{ editorId = $e.quest.editorId; ownerPlugin = $e.quest.ownerPlugin }
            referenceAlias = [ordered]@{ editorId = $e.referenceAlias.editorId; quest = $e.referenceAlias.quest; fillType = $e.referenceAlias.fillType }
            stageObjective = [ordered]@{ quest = $e.stageObjective.quest; stage = $e.stageObjective.stage; objectiveIndex = $e.stageObjective.objectiveIndex }
            condition = [ordered]@{ owner = $e.condition.owner; fieldPath = 'INFO\Conditions\CTDA'; count = $e.condition.count }
            relationships = [ordered]@{ actorPackage = $true; questDialogue = $true; aliasQuest = $true; cellReference = $true }
            package = [ordered]@{ editorId = $e.package.editorId; ownerPlugin = $e.package.ownerPlugin; procedureTreeConfigured = $true }
            navmesh = [ordered]@{ ownerPlugin = $e.navmesh.ownerPlugin; cell = $e.navmesh.cell; finalized = $true }
        }
        review = [ordered]@{ reviewerId = $s.provenance.reviewerId; findingCode = $s.provenance.reviewFindingCode; originalOnly = $true }
        cleanup = [ordered]@{ required = $true; instruction = 'Delete only the named disposable run root after retaining this sanitized capture.' }
    }
    $json = $capture | ConvertTo-Json -Depth 12
    $stream = [IO.File]::Open($CaptureOutput, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $createdCapture = $true
    try {
        $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
        try { $writer.Write($json) } finally { $writer.Dispose() }
    } finally { if ($stream) { $stream.Dispose() } }
    'RESULT=UNVERIFIED_SUBMISSION'
}
catch {
    if ($createdCapture -and (Test-Path -LiteralPath $CaptureOutput)) { Remove-Item -LiteralPath $CaptureOutput -Force }
    Write-Error $_
    exit 2
}
