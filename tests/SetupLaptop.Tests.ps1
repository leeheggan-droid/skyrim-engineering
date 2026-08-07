#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.9.0' }

Describe 'setup-laptop provisional read-only bootstrap' {
    BeforeAll {
        $script:setupScript = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\setup-laptop.ps1'
        $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures\laptop'
        $script:canonical = Join-Path $fixtureRoot 'canonical\manifest.json'

        function Invoke-LaptopSetup {
            param(
                [Parameter(Mandatory = $true)][string]$Mode,
                [Parameter(Mandatory = $true)][string]$GameRoot,
                [Parameter(Mandatory = $true)][string]$ProfileRoot,
                [Parameter(Mandatory = $true)][string]$StateDirectory,
                [string]$Manifest = $script:canonical,
                [string]$ToolRoot
            )
            $arguments = @{
                ClientId = 'client-a'
                GameRoot = $GameRoot
                ProfileRoot = $ProfileRoot
                CanonicalManifest = $Manifest
                StateDirectory = $StateDirectory
            }
            $arguments[$Mode] = $true
            if (-not [string]::IsNullOrWhiteSpace($ToolRoot)) { $arguments.ToolRoot = $ToolRoot }
            & $script:setupScript @arguments
        }

        function Get-CaseTreeSnapshot {
            param([Parameter(Mandatory = $true)][string]$Root)
            return (@(Get-ChildItem -LiteralPath $Root -Recurse -Force | Sort-Object FullName | ForEach-Object {
                $relative = $_.FullName.Substring($Root.Length + 1).Replace('\', '/')
                if ($_.PSIsContainer) { 'D|{0}' -f $relative }
                else { 'F|{0}|{1}|{2}' -f $relative, $_.Length, (Get-FileHash -LiteralPath $_.FullName -Algorithm SHA256).Hash }
            }) -join "`n")
        }

        function Invoke-LaptopSetupProcess {
            param(
                [Parameter(Mandatory = $true)][ValidateSet('Apply', 'Rollback')][string]$Mode
            )
            $arguments = @(
                '-NoProfile', '-File', $script:setupScript, ('-' + $Mode),
                '-ClientId', 'client-a', '-GameRoot', '.\hostile-relative-game',
                '-ProfileRoot', (Join-Path $script:caseRoot 'missing-profile'),
                '-CanonicalManifest', (Join-Path $script:caseRoot 'missing-manifest.json'),
                '-StateDirectory', '\\hostile.invalid\missing-state'
            )
            $output = @(& (Get-Command pwsh).Source @arguments 2>&1 | ForEach-Object { $_.ToString() })
            return [pscustomobject]@{ exitCode = $LASTEXITCODE; output = ($output -join "`n") }
        }
    }

    BeforeEach {
        $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:gameRoot = Join-Path $caseRoot 'Game'
        $script:profileRoot = Join-Path $caseRoot 'Profiles'
        $script:stateRoot = Join-Path $caseRoot 'State'
        $script:toolRoot = Join-Path $caseRoot 'Tools'
        New-Item -ItemType Directory -Path $gameRoot, $profileRoot, $stateRoot, $toolRoot -Force | Out-Null
    }

    It 'requires exactly one explicit mode and an anonymous client id' {
        { & $setupScript -ClientId client-a -GameRoot $gameRoot -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot } | Should -Throw
        { & $setupScript -AuditOnly -Plan -ClientId client-a -GameRoot $gameRoot -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot } | Should -Throw
        { & $setupScript -AuditOnly -ClientId 'named-laptop' -GameRoot $gameRoot -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot } | Should -Throw
    }

    It 'contains no component mutation engine or mutation-only parameter surface' {
        $source = Get-Content -LiteralPath $setupScript -Raw

        $source | Should -Not -Match '(?im)^\s*(?:Remove|Copy|Move)-Item\b|\bExpand-Archive\b|\bStart-Process\b|\bInvoke-Expression\b'
        $source | Should -Not -Match '(?i)\[IO\.(?:File|Directory)\]::(?:Copy|Move|Delete|CreateDirectory|WriteAllBytes|WriteAllText|Replace|Open)\b'
        $source | Should -Not -Match '(?i)function\s+(?:Initialize-PhysicalIdentityApi|Get-PhysicalRootAnchor|Open-PhysicalRootAnchor|Open-DirectoryLease|Get-FilePhysicalIdentity|Get-DirectoryPhysicalIdentity|Invoke-GuardedFileMove|Invoke-GuardedDirectoryMove|Get-ExpectedMutations|Write-BytesExclusively|Write-StateAtomic|Get-PreflightOwnershipSha256|Assert-SourcePackage|Assert-ArchiveTool|Assert-NoReparseTree|Assert-Official7zLayout|Test-QualificationInterrupt|Remove-OwnedStage|Get-MutationPath|Set-MutationPreflight|New-GuardedDirectory|Invoke-ApplyTransaction|Assert-JournalAllowlist|Move-Verify-DeleteFile|Invoke-RollbackTransaction)\b'
        $source | Should -Not -Match '(?i)\$(?:PackageCache|ArchiveToolPath|ConfirmApply|InterruptAfter|InterruptMutationIndex)\b|skyrim-engineering\.laptop-state/v1|approved7zInstall|\$script:PhysicalRootAnchors'
        $source | Should -Not -Match '(?im)^\s*&\s+\$|\.ShouldProcess\('
    }

    It 'describes package provenance as verified intake evidence rather than install approval' {
        $catalogPath = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\references\laptop-package-catalog.json'
        $rawCatalog = Get-Content -LiteralPath $catalogPath -Raw
        $catalog = $rawCatalog | ConvertFrom-Json

        @($catalog.policy.verifiedArchiveTypes) | Should -Be @('7z')
        $catalog.packages[0].intakeVerified | Should -BeTrue
        $rawCatalog | Should -Not -Match '"approved"\s*:|allowedArchiveTypes|approved 7z|installApproved'
    }

    It 'emits deterministic sanitized audit categories and all difference types' {
        Copy-Item -Path (Join-Path $fixtureRoot 'client-mismatch\Game\*') -Destination $gameRoot -Recurse -Force
        $first = Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        $second = Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        $audit = $first | ConvertFrom-Json

        $first | Should -BeExactly $second
        $audit.schema | Should -Be 'skyrim-engineering.laptop-audit/v1'
        $audit.clientId | Should -Be 'client-a'
        @($audit.categories.PSObject.Properties.Name) | Should -Be @('anniversaryBaseline', 'approvedShared', 'machineSpecific', 'unknownOrIncompatible')
        @($audit.differences.missing.relativePath).Count | Should -Be 64
        @($audit.differences.hashDifferent.relativePath) | Should -Be @('Data/Skyrim.synthetic.txt')
        @($audit.differences.versionDifferent.relativePath) | Should -Be @('Data/Skyrim.synthetic.txt')
        @($audit.differences.orderDifferent.relativePath) | Should -Be @('Data/Skyrim.synthetic.txt', 'Data/Update.synthetic.txt')
        $first | Should -Not -Match ([regex]::Escape($caseRoot))
        $first | Should -Not -Match ([regex]::Escape([Environment]::UserName))
        $first | Should -Not -Match '(?i)(password|token|steamid|https?://|\\\\)'
    }

    It 'classifies unlisted profile content as machine-specific and game content as unknown' {
        Copy-Item -Path (Join-Path $fixtureRoot 'client-extra\Game\*') -Destination $gameRoot -Recurse -Force
        Copy-Item -Path (Join-Path $fixtureRoot 'client-extra\Profiles\*') -Destination $profileRoot -Recurse -Force
        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        @($audit.categories.machineSpecific.opaqueId) | Should -Not -BeNullOrEmpty
        @($audit.categories.unknownOrIncompatible.opaqueId) | Should -Not -BeNullOrEmpty
    }

    It 'produces a deterministic read-only plan while retaining verified package intake evidence' {
        Copy-Item -Path (Join-Path $fixtureRoot 'client-extra\Game\*') -Destination $gameRoot -Recurse -Force
        Copy-Item -Path (Join-Path $fixtureRoot 'client-extra\Profiles\*') -Destination $profileRoot -Recurse -Force
        $before = Get-CaseTreeSnapshot $caseRoot

        $first = Invoke-LaptopSetup -Mode Plan -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        $second = Invoke-LaptopSetup -Mode Plan -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        $plan = $first | ConvertFrom-Json

        $first | Should -BeExactly $second
        $plan.schema | Should -Be 'skyrim-engineering.laptop-plan/v1'
        $plan.operation | Should -Be 'readOnlyAssessment'
        @($plan.actions).Count | Should -Be 0
        @($plan.supportedModes) | Should -Be @('AuditOnly', 'Plan', 'Verify')
        $plan.deferred.schema | Should -Be 'skyrim-engineering.laptop-deferred/v1'
        @($plan.deferred.modes) | Should -Be @('Apply', 'Rollback')
        $plan.packageIntake[0].catalogId | Should -Be 'skse-ae-2-2-6-official'
        $plan.packageIntake[0].status | Should -Be 'verifiedIntakeEvidence'
        $plan.packageIntake[0].expectedFileCount | Should -Be 64
        $first | Should -Not -Match 'installApproved7zEntry|approved7zInstall'
        (Get-CaseTreeSnapshot $caseRoot) | Should -BeExactly $before
    }

    It 'fails closed before validating or traversing hostile nonexistent roots' -ForEach @(
        @{ mode = 'Apply' },
        @{ mode = 'Rollback' }
    ) {
        Set-Content -LiteralPath (Join-Path $gameRoot 'game-canary.txt') -Value 'game-owned' -NoNewline
        Set-Content -LiteralPath (Join-Path $profileRoot 'profile-canary.txt') -Value 'profile-owned' -NoNewline
        $before = Get-CaseTreeSnapshot $caseRoot

        $result = Invoke-LaptopSetupProcess -Mode $mode

        $result.exitCode | Should -Not -Be 0
        $result.output | Should -Match '"schema":"skyrim-engineering\.laptop-deferred/v1"'
        $result.output | Should -Match ('"mode":"' + $mode + '"')
        $result.output | Should -Match 'native Windows handle-relative writer'
        $result.output | Should -Match 'OS-protected journal'
        $result.output | Should -Match 'AuditOnly.*Plan.*Verify'
        (Get-CaseTreeSnapshot $caseRoot) | Should -BeExactly $before
    }

    It 'verifies observed state without changing any supplied root' {
        Copy-Item -Path (Join-Path $fixtureRoot 'client-mismatch\Game\*') -Destination $gameRoot -Recurse -Force
        $before = Get-CaseTreeSnapshot $caseRoot

        $verify = (Invoke-LaptopSetup -Mode Verify -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        $verify.schema | Should -Be 'skyrim-engineering.laptop-audit/v1'
        $verify.mode | Should -Be 'verify'
        @($verify.differences.missing.relativePath) | Should -Contain 'skse64_loader.exe'
        (Get-CaseTreeSnapshot $caseRoot) | Should -BeExactly $before
    }

    It 'rejects unsafe caller manifest package authorization during read-only validation' {
        $badManifest = Join-Path $caseRoot 'bad.json'
        $bad = Get-Content -LiteralPath $canonical -Raw | ConvertFrom-Json
        $bad.items[2] | Add-Member -NotePropertyName sourceRelativePath -NotePropertyValue ('C:' + '/Users/Owner/private.zip')
        $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $badManifest

        { Invoke-LaptopSetup -Mode Plan -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -Manifest $badManifest } |
            Should -Throw '*safe relative path*'
    }

    It 'projects untrusted discovered names and metadata as opaque sanitized records' {
        $privateProfile = Join-Path $profileRoot 'Owner-Private\private-host'
        New-Item -ItemType Directory -Path $privateProfile -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $privateProfile 'account-secret-profile.txt') -Value 'local'
        New-Item -ItemType Directory -Path (Join-Path $gameRoot 'Data') | Out-Null
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\plugins.txt') -Value ('*' + ('7656119' + '1234567890') + '.esp')
        @{ 'Data/Skyrim.synthetic.txt' = ('http' + 's://private-host/token') } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $gameRoot 'versions.json')

        $json = Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        $audit = $json | ConvertFrom-Json

        $json | Should -Not -Match 'Owner-Private|private-host|account-secret|7656119|https?://|token'
        @($audit.categories.machineSpecific.opaqueId) | Should -Not -BeNullOrEmpty
    }

    It 'reports required runtime tool component and profile domains from actual evidence' {
        Set-Content -LiteralPath (Join-Path $gameRoot 'SkyrimSE.exe') -Value 'synthetic runtime' -NoNewline
        @{ schema = 'skyrim-engineering.synthetic-version/v1'; version = '1.6.1170.0' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $gameRoot 'SkyrimSE.exe.version.json')

        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        @($audit.domains.PSObject.Properties.Name) | Should -Be @('runtime', 'creations', 'plugins', 'archives', 'skse', 'addressLibrary', 'skyrimTogether', 'modManager', 'profiles', 'loadOrder')
        $audit.domains.runtime.status | Should -Be 'missing'
        $audit.domains.addressLibrary.status | Should -Be 'unsupportedPendingIntake'
        $audit.domains.skyrimTogether.status | Should -Be 'unsupportedPendingIntake'
    }

    It 'derives runtime plugin archive and tool inventory from explicit roots rather than sidecar claims' {
        Copy-Item -LiteralPath (Get-Command pwsh).Source -Destination (Join-Path $gameRoot 'SkyrimSE.exe')
        Copy-Item -LiteralPath (Get-Command pwsh).Source -Destination (Join-Path $toolRoot 'ModOrganizer.exe')
        @{ schema = 'skyrim-engineering.synthetic-version/v1'; version = '9.9.9.9' } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $gameRoot 'SkyrimSE.exe.version.json')
        New-Item -ItemType Directory -Path (Join-Path $gameRoot 'Data') | Out-Null
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\Observed.esm') -Value 'plugin' -NoNewline
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\Observed.bsa') -Value 'archive' -NoNewline

        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ToolRoot $toolRoot) | ConvertFrom-Json

        $audit.domains.runtime.actualVersion | Should -Not -Be '9.9.9.9'
        @($audit.domains.plugins.items).Count | Should -Be 1
        @($audit.domains.archives.items).Count | Should -Be 1
        $audit.domains.modManager.status | Should -Be 'observed'
    }

    It 'uses the exact canonical Creation classifier and excludes cc-prefixed BA2 archives' {
        New-Item -ItemType Directory -Path (Join-Path $gameRoot 'Data') -Force | Out-Null
        foreach ($name in @('ccApproved.esl', 'ccApproved.esm', 'ccApproved.esp', 'ccApproved.bsa', 'ccBGSSSE001-Fish.esm', 'ccBGSSSE025-AdvDSGS.esm', 'ccBGSSSE037-Curios.esl', 'ccQDRSSE001-SurvivalMode.esl')) {
            Set-Content -LiteralPath (Join-Path $gameRoot ('Data\' + $name)) -Value $name -NoNewline
        }
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\ccNotACreation.ba2') -Value 'excluded' -NoNewline

        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        @($audit.domains.creations.items).Count | Should -Be 8
        @($audit.domains.creations.items | Where-Object kind -eq 'plugin').Count | Should -Be 7
        @($audit.domains.creations.items | Where-Object kind -eq 'archive').Count | Should -Be 1
    }

    It 'classifies path matches with bad evidence as unknown and reports root-qualified values' {
        Copy-Item -Path (Join-Path $fixtureRoot 'client-mismatch\Game\*') -Destination $gameRoot -Recurse -Force
        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        @($audit.categories.anniversaryBaseline.relativePath) | Should -Not -Contain 'Data/Skyrim.synthetic.txt'
        @($audit.categories.unknownOrIncompatible.relativePath) | Should -Contain 'Data/Skyrim.synthetic.txt'
        $difference = @($audit.differences.hashDifferent | Where-Object relativePath -eq 'Data/Skyrim.synthetic.txt')[0]
        $difference.root | Should -Be 'game'
        $difference.expected | Should -Match '^[0-9a-f]{64}$'
        $difference.actual | Should -Match '^[0-9a-f]{64}$'
    }

    It 'refuses relative overlapping and ancestor-reparse explicit roots' {
        { & $setupScript -AuditOnly -ClientId client-a -GameRoot '.' -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot } | Should -Throw '*fully qualified*'
        $nestedState = Join-Path $profileRoot 'State'
        New-Item -ItemType Directory -Path $nestedState | Out-Null
        { Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $nestedState } | Should -Throw '*overlap*'

        $realParent = Join-Path $caseRoot 'real-parent'
        $linkedParent = Join-Path $caseRoot 'linked-parent'
        New-Item -ItemType Directory -Path $realParent | Out-Null
        New-Item -ItemType Junction -Path $linkedParent -Target $realParent | Out-Null
        $nestedProfiles = Join-Path $linkedParent 'profiles'
        New-Item -ItemType Directory -Path $nestedProfiles | Out-Null
        { Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $nestedProfiles -StateDirectory $stateRoot } | Should -Throw '*reparse*ancestor*'
    }

    It 'preserves every existing profile file across Plan and Verify' {
        $existingProfile = Join-Path $profileRoot 'Anniversary Together'
        New-Item -ItemType Directory -Path (Join-Path $existingProfile 'mods\Existing') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existingProfile 'profile.ini') -Value 'owned=true' -NoNewline
        Set-Content -LiteralPath (Join-Path $existingProfile 'mods\Existing\addon.txt') -Value 'addon' -NoNewline
        $before = Get-CaseTreeSnapshot $caseRoot

        Invoke-LaptopSetup -Mode Plan -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot | Out-Null
        Invoke-LaptopSetup -Mode Verify -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot | Out-Null

        (Get-CaseTreeSnapshot $caseRoot) | Should -BeExactly $before
    }
}
