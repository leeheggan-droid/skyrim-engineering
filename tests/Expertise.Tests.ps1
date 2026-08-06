#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Set-StrictMode -Version Latest

Describe 'Step zero expertise evidence integrity' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $evidenceRoot = Join-Path $PSScriptRoot 'fixtures\evidence'
        $assessment = Get-Content -Raw (Join-Path $evidenceRoot 'assessment.json') | ConvertFrom-Json
        $reviews = Get-Content -Raw (Join-Path $evidenceRoot 'review-state.json') | ConvertFrom-Json
        $release = Get-Content -Raw (Join-Path $evidenceRoot 'release-state.json') | ConvertFrom-Json
    }

    It 'has the required evidence documents and machine-readable state' {
        @(
            'docs/expertise/syllabus.md'
            'docs/expertise/source-register.md'
            'docs/expertise/toolchain-audit.md'
            'docs/expertise/architecture-traces.md'
            'docs/expertise/practicals.md'
            'docs/expertise/assessment-rubric.md'
            'docs/expertise/assessment-results.md'
            'docs/expertise/package-intake.md'
            'tests/fixtures/evidence/assessment.json'
            'tests/fixtures/evidence/artifacts.json'
            'tests/fixtures/evidence/review-state.json'
            'tests/fixtures/evidence/release-state.json'
            'tests/fixtures/evidence/gate-requirements.json'
        ) | ForEach-Object { Join-Path $repoRoot $_ | Should -Exist }
    }

    It 'derives every domain score and status from atomic rubric items' {
        $assessment.domains.Count | Should -Be 8
        foreach ($domain in $assessment.domains) {
            ($domain.items.awarded | Measure-Object -Sum).Sum | Should -Be $domain.awarded
            ($domain.items.maximum | Measure-Object -Sum).Sum | Should -Be $domain.maximum
            $meetsThreshold = (100 * $domain.awarded) -ge ($assessment.domainThresholdPercent * $domain.maximum)
            $derivedStatus = if ($meetsThreshold -and -not $domain.automaticBlock) { 'PASS' } else { 'BLOCKED' }
            $domain.status | Should -Be $derivedStatus
            foreach ($item in $domain.items) {
                $item.awarded | Should -BeLessOrEqual $item.maximum
                $item.evidence.Count | Should -BeGreaterThan 0
                $item.evidence | ForEach-Object { Join-Path $repoRoot $_ | Should -Exist }
            }
        }

        $awarded = ($assessment.domains.awarded | Measure-Object -Sum).Sum
        $maximum = ($assessment.domains.maximum | Measure-Object -Sum).Sum
        $awarded | Should -Be $assessment.awarded
        $maximum | Should -Be $assessment.maximum
        $maximum | Should -Be 100

        $humanResults = Get-Content -Raw (Join-Path $repoRoot 'docs\expertise\assessment-results.md')
        $humanResults | Should -Match ([regex]::Escape("Overall result: **$awarded/$maximum"))
        foreach ($domain in $assessment.domains) {
            $humanResults | Should -Match ([regex]::Escape("| $($domain.id) | $($domain.awarded)/$($domain.maximum) | $($domain.status) |"))
        }

        $allDomainsPass = @($assessment.domains | Where-Object status -ne 'PASS').Count -eq 0
        $meetsOverall = (100 * $awarded) -ge ($assessment.overallThresholdPercent * $maximum)
        $approvedScopes = @($reviews.reviews | Where-Object { $_.verdict -eq 'PASS' -and $_.approved }).scope | Select-Object -Unique
        $releaseReady = $release.repositoryLicenseSelected -and $release.deterministicPackageVerified
        $derivedGate = if ($allDomainsPass -and $meetsOverall -and $approvedScopes.Count -ge 2 -and $releaseReady) { 'PASS' } else { 'BLOCKED' }
        $assessment.gateStatus | Should -Be $derivedGate
    }

    It 'verifies every frozen artefact hash instead of trusting prose' {
        $manifest = Get-Content -Raw (Join-Path $evidenceRoot 'artifacts.json') | ConvertFrom-Json
        $manifest.algorithm | Should -Be 'SHA256'
        $manifest.artifacts.Count | Should -BeGreaterThan 0
        foreach ($artifact in $manifest.artifacts) {
            $path = Join-Path $repoRoot $artifact.path
            $path | Should -Exist
            (Get-FileHash -Algorithm SHA256 -LiteralPath $path).Hash | Should -Be $artifact.sha256
        }
    }

    It 'executes the substantive portable fixture checks' {
        $pwsh = (Get-Process -Id $PID).Path
        foreach ($script in @(
            'tests\fixtures\data-model\Test-DataModelCases.ps1'
            'tests\fixtures\preparation\Test-PreparationContracts.ps1'
            'tests\fixtures\together\Test-DesyncEdge.ps1'
        )) {
            $output = & $pwsh -NoProfile -File (Join-Path $repoRoot $script) 2>&1
            $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
            ($output -join [Environment]::NewLine) | Should -Match 'RESULT=PASS'
        }

        $destination = "C:\tmp\skyrim-engineering-release-$([guid]::NewGuid().ToString('N'))"
        $verifier = Join-Path $repoRoot 'tests\fixtures\package\Test-EvidenceManifest.ps1'
        $manifest = Join-Path $repoRoot 'tests\fixtures\package\release-manifest.json'
        $output = & $pwsh -NoProfile -File $verifier -RepositoryRoot $repoRoot -Manifest $manifest -Destination $destination 2>&1
        $LASTEXITCODE | Should -Be 0 -Because ($output -join [Environment]::NewLine)
        ($output -join [Environment]::NewLine) | Should -Match 'ACCEPT=PASS'
        & $pwsh -NoProfile -File $verifier -RepositoryRoot $repoRoot -Manifest $manifest -Destination $destination -Rollback | Out-Null
        $badDestination = "C:\tmp\skyrim-engineering-release-$([guid]::NewGuid().ToString('N'))"
        $output = & $pwsh -NoProfile -File $verifier -RepositoryRoot $repoRoot -Manifest $manifest -Destination $badDestination -SimulateMismatch 2>&1
        $LASTEXITCODE | Should -Be 2
        ($output -join [Environment]::NewLine) | Should -Match 'QUARANTINE=PASS'
        & $pwsh -NoProfile -File $verifier -RepositoryRoot $repoRoot -Manifest $manifest -Destination $badDestination -Rollback | Out-Null
    }

    It 'derives source, practical and review state from pinned machine-readable evidence' {
        $requirements = Get-Content -Raw (Join-Path $evidenceRoot 'gate-requirements.json') | ConvertFrom-Json
        @($requirements.primarySources | Where-Object domain -eq 'papyrus').Count | Should -BeGreaterOrEqual $requirements.sourceMinimums.papyrus
        foreach($source in $requirements.primarySources){ $source.publisher | Should -Not -BeNullOrEmpty; $source.version | Should -Not -BeNullOrEmpty; $source.sha256 | Should -Match '^[A-F0-9]{64}$' }
        foreach($practical in $requirements.practicals){ Join-Path $repoRoot $practical.contract | Should -Exist; if($practical.automaticBlock){$practical.status | Should -Be 'BLOCKED'} }
        foreach($review in $reviews.reviews){
            $report=Join-Path $repoRoot $review.reportPath
            (Get-FileHash -Algorithm SHA256 -LiteralPath $report).Hash | Should -Be $review.reportSha256
            $text=Get-Content -Raw -LiteralPath $report
            foreach($id in @($review.criticalFindingIds)+@($review.importantFindingIds)){ $text | Should -Match ([regex]::Escape("### $id")) }
            $review.criticalOpen | Should -Be @($review.criticalFindingIds).Count
            $review.importantOpen | Should -Be @($review.importantFindingIds).Count
            $review.approved | Should -Be ($review.verdict -eq 'PASS' -and $review.criticalOpen -eq 0 -and $review.importantOpen -eq 0)
        }
        $xedit = Get-Content -Raw (Join-Path $repoRoot 'tests\fixtures\xedit\fresh-replay.json') | ConvertFrom-Json
        $xedit.toolVersion | Should -Be '4.1.5f'
        $xedit.toolSha256 | Should -Be '659FADDD8DC061A9D2EDDD20DE925821B87E377284CE179F4538FF78BB2420CD'
        @($xedit.inputs | Where-Object { -not $_.equal -or $_.before -ne $_.after }).Count | Should -Be 0
        $xedit.interpretation.authoritativeDiskHashDeltaCount | Should -Be 0
        $xedit.modifiedFileCount | Should -Be 2
        $xedit.interpretation.modifiedFileCountMeaning | Should -Match 'in-memory'
    }

    It 'rejects personal, credential, save, dump, executable, plugin and archive payloads' {
        $allowedExtensions = @('.md', '.txt', '.json', '.ps1', '.pas', '.psc', '.patch', '.sha256', '.sseviewsettings')
        $files = @(Get-ChildItem (Join-Path $repoRoot 'docs\expertise'), (Join-Path $repoRoot 'tests') -Recurse -File)
        foreach ($file in $files) {
            $file.Extension.ToLowerInvariant() | Should -BeIn $allowedExtensions
            $file.Name | Should -Not -Match '(?i)\.(sav|ess|skse|dmp|mdmp|dll|exe|pex|esp|esm|esl|bsa|ba2|zip|7z|rar)$'
            $text = Get-Content -Raw -LiteralPath $file.FullName
            $text | Should -Not -Match 'C:\\Users\\'
            $text | Should -Not -Match '(?i)\b(gh[pousr]_[A-Za-z0-9_]{20,}|AKIA[0-9A-Z]{16})\b'
            $privateKeyMarker = '-----BEGIN ' + '[A-Z ]*PRIVATE KEY-----'
            $text | Should -Not -Match $privateKeyMarker
            $text | Should -Not -Match '\b7656119\d{10}\b'
        }
    }

    It 'requires a selected repository licence and deterministic original-only package' {
        $release.repositoryLicenseSelected | Should -BeTrue
        $release.deterministicPackageVerified | Should -BeTrue
        $release.includesLicensedGameOrModPayload | Should -BeFalse
    }

    It 'requires two explicit independent PASS approvals' {
        $approvedScopes = @($reviews.reviews | Where-Object { $_.verdict -eq 'PASS' -and $_.approved }).scope | Select-Object -Unique
        $approvedScopes.Count | Should -BeGreaterOrEqual 2
        @($reviews.reviews | Where-Object { $_.criticalOpen -gt 0 -or $_.importantOpen -gt 0 }).Count | Should -Be 0
    }
}
