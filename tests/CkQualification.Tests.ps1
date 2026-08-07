#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Set-StrictMode -Version Latest

Describe 'Creation Kit qualification capture contract' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $captureScript = Join-Path $repoRoot 'tests\fixtures\ck\Test-CkCapture.ps1'
        $prepareScript = Join-Path $repoRoot 'tests\fixtures\ck\Prepare-CkQualification.ps1'
        $script:ckTestRoots = [Collections.Generic.List[string]]::new()

        function Get-Hash([string]$Path) {
            (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
        }

        function New-CkCase([string]$Root, [hashtable]$Mutation = @{}) {
            $Root = Join-Path 'C:\tmp' ("seg-ck-test-{0}" -f [guid]::NewGuid().ToString('N'))
            $script:ckTestRoots.Add($Root)
            New-Item -ItemType Directory -Path $Root -Force | Out-Null
            $seed = Join-Path $Root 'seed.esp'
            $plugin = Join-Path $Root 'SEG_CK_Practical3.esp'
            $ck = Join-Path $Root 'CreationKit.exe'
            $master = Join-Path $Root 'Skyrim.esm'
            $ini = Join-Path $Root 'CreationKit.ini'
            $dumpText = Join-Path $Root 'dump.txt'
            $xdump = Join-Path $Root 'xDump64.cmd'
            [IO.File]::WriteAllBytes($seed, [byte[]](1, 2, 3))
            [IO.File]::WriteAllBytes($plugin, [byte[]](4, 5, 6, 7))
            [IO.File]::WriteAllBytes($ck, [byte[]](8, 9))
            [IO.File]::WriteAllBytes($master, [byte[]](10, 11))
            [IO.File]::WriteAllText($ini, '[General]')
            [IO.File]::WriteAllText($dumpText, 'structured CK dump evidence')
            @"
@echo off
if "%1"=="-check" exit /b 0
if "%1"=="-dump" type "$dumpText" & exit /b 0
exit /b 3
"@ | Set-Content -LiteralPath $xdump -Encoding Ascii

            $now = [DateTime]::UtcNow
            $submission = [ordered]@{
                schema = 'skyrim-engineering.qualification.creation-kit-submission/v1'
                runId = 'ck-test-run'
                startedAtUtc = $now.AddMinutes(-10).ToString('o')
                capturedAtUtc = $now.ToString('o')
                plugin = [ordered]@{
                    path = $plugin; relativeName = 'SEG_CK_Practical3.esp'; activeFile = 'SEG_CK_Practical3.esp'
                    seedPath = $seed; seedSha256 = Get-Hash $seed
                    postSaveSha256 = Get-Hash $plugin; postReopenSha256 = Get-Hash $plugin
                    fullCloseConfirmed = $true; reopenConfirmed = $true
                }
                tools = [ordered]@{
                    creationKit = [ordered]@{ path = $ck; version = '1.6.1378.1'; sha256 = Get-Hash $ck }
                    xDump64 = [ordered]@{ path = $xdump; version = '4.1.5f'; sha256 = Get-Hash $xdump }
                }
                provenance = [ordered]@{
                    originalOnly = $true; licensedAssetsCommitted = $false
                    generator = 'CreateOriginalFixture.pas'; reviewerId = 'reviewer-ck-01'
                    reviewFindingCode = 'original-only-reviewed'
                }
                masters = @('Skyrim.esm')
                protectedInputs = @(
                    [ordered]@{ kind = 'master'; path = $master; relativeName = 'Skyrim.esm'; sha256 = Get-Hash $master },
                    [ordered]@{ kind = 'ini'; path = $ini; relativeName = 'CreationKit.ini'; sha256 = Get-Hash $ini }
                )
                structuredEvidence = [ordered]@{
                    rawDumpSha256 = Get-Hash $dumpText
                    quest = [ordered]@{ editorId = 'SEG_ExpertiseQuest'; ownerPlugin = 'SEG_CK_Practical3.esp' }
                    referenceAlias = [ordered]@{ editorId = 'SEG_ExpertiseAlias'; quest = 'SEG_ExpertiseQuest'; fillType = 'SpecificReference' }
                    stageObjective = [ordered]@{ quest = 'SEG_ExpertiseQuest'; stage = 10; objectiveIndex = 10 }
                    condition = [ordered]@{ owner = 'SEG_ExpertiseDialogue'; fieldPath = 'INFO\Conditions\CTDA'; count = 1 }
                    relationships = [ordered]@{ actorPackage = $true; questDialogue = $true; aliasQuest = $true; cellReference = $true }
                    package = [ordered]@{ editorId = 'SEG_ExpertisePackage'; ownerPlugin = 'SEG_CK_Practical3.esp'; procedureTreeConfigured = $true }
                    navmesh = [ordered]@{ ownerPlugin = 'SEG_CK_Practical3.esp'; cell = 'SEG_ExpertiseCell'; finalized = $true }
                }
            }

            foreach ($key in $Mutation.Keys) {
                & $Mutation[$key] $submission $xdump
            }
            $submissionPath = Join-Path $Root 'submission.json'
            $submission | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $submissionPath -Encoding UTF8
            [pscustomobject]@{ Submission = $submissionPath; Output = Join-Path $Root 'capture.json'; XDump = $xdump }
        }
    }

    AfterAll {
        foreach ($root in $script:ckTestRoots) {
            if ((Test-Path -LiteralPath $root) -and $root.StartsWith('C:\tmp\seg-ck-test-', [StringComparison]::OrdinalIgnoreCase)) {
                Remove-Item -LiteralPath $root -Recurse -Force
            }
        }
    }

    It 'emits a sanitized unverified capture bound to a complete reviewed CK round trip' {
        $case = New-CkCase (Join-Path $TestDrive 'valid')
        $messages = & pwsh -NoProfile -File $captureScript -Submission $case.Submission -CaptureOutput $case.Output 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($messages -join "`n")
        ($messages -join "`n") | Should -Not -Match 'RESULT=PASS'
        $capture = Get-Content -Raw -LiteralPath $case.Output | ConvertFrom-Json
        $capture.schema | Should -Be 'skyrim-engineering.qualification.creation-kit/v1'
        $capture.result | Should -Be 'UNVERIFIED_SUBMISSION'
        $capture.records.stageObjective.stage | Should -Be 10
        $capture.records.condition.fieldPath | Should -Be 'INFO\Conditions\CTDA'
        $capture.review.reviewerId | Should -Be 'reviewer-ck-01'
        (Get-Content -Raw -LiteralPath $case.Output) | Should -Not -Match ([regex]::Escape($TestDrive))
    }

    It 'rejects incomplete structured record semantics' {
        $case = New-CkCase (Join-Path $TestDrive 'missing-condition') @{
            mutate = { param($s, $x) $s.structuredEvidence.condition.count = 0 }
        }
        & pwsh -NoProfile -File $captureScript -Submission $case.Submission -CaptureOutput $case.Output 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        $case.Output | Should -Not -Exist
    }

    It 'rejects failed xDump dump execution even when check succeeds' {
        $case = New-CkCase (Join-Path $TestDrive 'dump-fails') @{
            mutate = { param($s, $x) @'
@echo off
if "%1"=="-check" exit /b 0
exit /b 7
'@ | Set-Content -LiteralPath $x -Encoding Ascii; $s.tools.xDump64.sha256 = Get-Hash $x }
        }
        & pwsh -NoProfile -File $captureScript -Submission $case.Submission -CaptureOutput $case.Output 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'rejects stale, unreviewed, non-original, or non-reopened submissions' -ForEach @(
        @{ Name = 'stale'; Change = { param($s, $x) $s.capturedAtUtc = ([DateTime]::UtcNow.AddDays(-3)).ToString('o') } },
        @{ Name = 'reviewer'; Change = { param($s, $x) $s.provenance.reviewerId = '' } },
        @{ Name = 'provenance'; Change = { param($s, $x) $s.provenance.originalOnly = $false } },
        @{ Name = 'reopen'; Change = { param($s, $x) $s.plugin.reopenConfirmed = $false } },
        @{ Name = 'version'; Change = { param($s, $x) $s.tools.creationKit.version = '1.0.0.0' } }
    ) {
        $case = New-CkCase (Join-Path $TestDrive $Name) @{ mutate = $Change }
        & pwsh -NoProfile -File $captureScript -Submission $case.Submission -CaptureOutput $case.Output 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'refuses an existing capture target without changing it' {
        $case = New-CkCase 'ignored'
        [IO.File]::WriteAllText($case.Output, 'DO-NOT-OVERWRITE')
        & pwsh -NoProfile -File $captureScript -Submission $case.Submission -CaptureOutput $case.Output 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        (Get-Content -Raw -LiteralPath $case.Output) | Should -Be 'DO-NOT-OVERWRITE'
    }

    It 'rejects unsafe values instead of copying them into public capture output' -ForEach @(
        @{ Name = 'path'; Change = { param($s, $x) $s.runId = ('C:' + '\Use' + 'rs\Private\run') } },
        @{ Name = 'steam'; Change = { param($s, $x) $s.provenance.reviewerId = ('7656119' + '9012345678') } },
        @{ Name = 'network'; Change = { param($s, $x) $s.masters = @(('10.' + '2.3.4') + '.esm') } },
        @{ Name = 'token'; Change = { param($s, $x) $s.structuredEvidence.quest.editorId = ('token' + '=secret-value') } },
        @{ Name = 'finding'; Change = { param($s, $x) $s.provenance.reviewFindingCode = ('Reviewed by Jane at C:' + '\Use' + 'rs\Jane') } }
    ) {
        $case = New-CkCase 'ignored' @{ mutate = $Change }
        & pwsh -NoProfile -File $captureScript -Submission $case.Submission -CaptureOutput $case.Output 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        $case.Output | Should -Not -Exist
    }

    It 'rejects changed seed/current plugin, master, INI, or tool bytes' -ForEach @(
        @{ Name = 'seed'; Change = { param($s, $x) [IO.File]::AppendAllText($s.plugin.seedPath, 'changed') } },
        @{ Name = 'plugin'; Change = { param($s, $x) [IO.File]::AppendAllText($s.plugin.path, 'changed') } },
        @{ Name = 'master'; Change = { param($s, $x) [IO.File]::AppendAllText($s.protectedInputs[0].path, 'changed') } },
        @{ Name = 'ini'; Change = { param($s, $x) [IO.File]::AppendAllText($s.protectedInputs[1].path, 'changed') } },
        @{ Name = 'tool'; Change = { param($s, $x) [IO.File]::AppendAllText($s.tools.creationKit.path, 'changed') } }
    ) {
        $case = New-CkCase (Join-Path $TestDrive $Name) @{ mutate = $Change }
        & pwsh -NoProfile -File $captureScript -Submission $case.Submission -CaptureOutput $case.Output 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
    }

    It 'prepares only a private runbook and unverified submission template' {
        $root = Join-Path 'C:\tmp' ("seg-ck-test-{0}" -f [guid]::NewGuid().ToString('N'))
        $script:ckTestRoots.Add($root)
        New-Item -ItemType Directory -Path $root | Out-Null
        $ck = Join-Path $root 'CreationKit.exe'; [IO.File]::WriteAllBytes($ck, [byte[]](1))
        $xdump = Join-Path $root 'xDump64.exe'; [IO.File]::WriteAllBytes($xdump, [byte[]](2))
        $prepared = Join-Path 'C:\tmp' ("seg-ck-test-{0}" -f [guid]::NewGuid().ToString('N'))
        $script:ckTestRoots.Add($prepared)
        & pwsh -NoProfile -File $prepareScript -RunRoot $prepared -CreationKit $ck -XDump64 $xdump
        $LASTEXITCODE | Should -Be 0
        $plan = Get-Content -Raw -LiteralPath (Join-Path $prepared 'ck-runbook.json') | ConvertFrom-Json
        $plan.status | Should -Be 'PREPARED'
        $plan.runtimeEvidenceCaptured | Should -BeFalse
        $plan.guiLaunchAuthorized | Should -BeFalse
        $plan.steps | Should -Contain 'Human: fully close Creation Kit, reopen the active plugin, inspect, save, and close.'
    }

    It 'refuses an existing preparation root without changing it' {
        $tools = Join-Path 'C:\tmp' ("seg-ck-test-{0}" -f [guid]::NewGuid().ToString('N'))
        $script:ckTestRoots.Add($tools)
        New-Item -ItemType Directory -Path $tools | Out-Null
        $ck = Join-Path $tools 'CreationKit.exe'; [IO.File]::WriteAllBytes($ck, [byte[]](1))
        $xdump = Join-Path $tools 'xDump64.exe'; [IO.File]::WriteAllBytes($xdump, [byte[]](2))
        $existing = Join-Path 'C:\tmp' ("seg-ck-test-{0}" -f [guid]::NewGuid().ToString('N'))
        $script:ckTestRoots.Add($existing)
        New-Item -ItemType Directory -Path $existing | Out-Null
        [IO.File]::WriteAllText((Join-Path $existing 'sentinel.txt'), 'KEEP')
        & pwsh -NoProfile -File $prepareScript -RunRoot $existing -CreationKit $ck -XDump64 $xdump 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        (Get-Content -Raw -LiteralPath (Join-Path $existing 'sentinel.txt')) | Should -Be 'KEEP'
    }

    It 'rejects a capture output below a reparse-point ancestor' {
        $case = New-CkCase 'ignored'
        $target = Join-Path 'C:\tmp' ("seg-ck-test-{0}" -f [guid]::NewGuid().ToString('N'))
        $link = Join-Path 'C:\tmp' ("seg-ck-test-{0}-link" -f [guid]::NewGuid().ToString('N'))
        $script:ckTestRoots.Add($target); $script:ckTestRoots.Add($link)
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        $output = Join-Path $link 'capture.json'
        & pwsh -NoProfile -File $captureScript -Submission $case.Submission -CaptureOutput $output 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        $output | Should -Not -Exist
    }

    It 'rejects a preparation root below a reparse-point ancestor' {
        $tools = New-CkCase 'ignored'
        $target = Join-Path 'C:\tmp' ("seg-ck-test-{0}" -f [guid]::NewGuid().ToString('N'))
        $link = Join-Path 'C:\tmp' ("seg-ck-test-{0}-link" -f [guid]::NewGuid().ToString('N'))
        $script:ckTestRoots.Add($target); $script:ckTestRoots.Add($link)
        New-Item -ItemType Directory -Path $target | Out-Null
        New-Item -ItemType Junction -Path $link -Target $target | Out-Null
        $runRoot = Join-Path $link 'new-run'
        $submission = Get-Content -Raw -LiteralPath $tools.Submission | ConvertFrom-Json
        & pwsh -NoProfile -File $prepareScript -RunRoot $runRoot -CreationKit $submission.tools.creationKit.path -XDump64 $submission.tools.xDump64.path 2>&1 | Out-Null
        $LASTEXITCODE | Should -Not -Be 0
        $runRoot | Should -Not -Exist
    }
}
