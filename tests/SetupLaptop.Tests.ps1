#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.9.0' }

Describe 'setup-laptop safe bootstrap' {
    BeforeAll {
        $script:setupScript = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\setup-laptop.ps1'
        $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures\laptop'
        $script:canonical = Join-Path $fixtureRoot 'canonical\manifest.json'
        $script:officialSkseArchive = 'C:\tmp\skse64_2_02_06.7z'
        $script:sevenZip = 'C:\Program Files\7-Zip\7z.exe'

        function Import-SetupFunction([string]$Name) {
            $tokens = $null; $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile($script:setupScript, [ref]$tokens, [ref]$errors)
            $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name }, $true)
            if ($null -eq $definition) { throw "Missing setup function: $Name" }
            Invoke-Expression ($definition.Extent.Text -replace ('^function\s+' + [regex]::Escape($Name)), ('function script:' + $Name))
        }
        foreach ($name in @('Convert-ToPortablePath', 'Assert-SafeRelativePath', 'Get-NormalizedPath', 'Assert-NoReparseAncestor', 'Get-LowerHash', 'Assert-ContainedPath', 'Assert-SourcePackage', 'Initialize-PhysicalIdentityApi', 'Open-PhysicalRootAnchor', 'Open-DirectoryLease', 'Get-FilePhysicalIdentity')) {
            Import-SetupFunction $name
        }

        function Invoke-LaptopSetup {
            param(
                [Parameter(Mandatory = $true)][string]$Mode,
                [Parameter(Mandatory = $true)][string]$GameRoot,
                [Parameter(Mandatory = $true)][string]$ProfileRoot,
                [Parameter(Mandatory = $true)][string]$StateDirectory,
                [string]$Manifest = $script:canonical,
                [string]$PackageCache = $script:packageCache,
                [string]$ToolRoot,
                [string]$InterruptAfter,
                [int]$InterruptMutationIndex = -1,
                [switch]$ConfirmApply,
                [switch]$WhatIf
            )
            $arguments = @{
                ClientId = 'client-a'
                GameRoot = $GameRoot
                ProfileRoot = $ProfileRoot
                CanonicalManifest = $Manifest
                StateDirectory = $StateDirectory
                Confirm = $false
            }
            $arguments[$Mode] = $true
            if ($ConfirmApply) { $arguments.ConfirmApply = $true }
            if ($Mode -eq 'Apply') { $arguments.PackageCache = $PackageCache }
            if (-not [string]::IsNullOrWhiteSpace($ToolRoot)) { $arguments.ToolRoot = $ToolRoot }
            if (-not [string]::IsNullOrWhiteSpace($InterruptAfter)) { $arguments.InterruptAfter = $InterruptAfter }
            if ($InterruptMutationIndex -ge 0) { $arguments.InterruptMutationIndex = $InterruptMutationIndex }
            if ($WhatIf) { $arguments.WhatIf = $true }
            & $script:setupScript @arguments
        }
    }

    BeforeEach {
        $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:gameRoot = Join-Path $caseRoot 'Game'
        $script:profileRoot = Join-Path $caseRoot 'Profiles'
        $script:stateRoot = Join-Path $caseRoot 'State'
        $script:packageCache = Join-Path $caseRoot 'PackageCache'
        $script:toolRoot = Join-Path $caseRoot 'Tools'
        New-Item -ItemType Directory -Path $gameRoot, $profileRoot, $stateRoot, $packageCache, $toolRoot -Force | Out-Null
        if (Test-Path -LiteralPath $officialSkseArchive) { Copy-Item -LiteralPath $officialSkseArchive -Destination (Join-Path $packageCache 'skse64_2_02_06.7z') }
    }

    It 'requires exactly one explicit mode and an anonymous client id' {
        {
            & $setupScript -ClientId client-a -GameRoot $gameRoot -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot
        } | Should -Throw
        {
            & $setupScript -AuditOnly -Plan -ClientId client-a -GameRoot $gameRoot -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot
        } | Should -Throw
        {
            & $setupScript -AuditOnly -ClientId 'named-laptop' -GameRoot $gameRoot -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot
        } | Should -Throw
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
        @($audit.differences.missing.relativePath) | Should -Contain 'skse64_1_6_1170.dll'
        @($audit.differences.missing.relativePath) | Should -Contain 'Data/Scripts/skse.pex'
        @($audit.differences.hashDifferent.relativePath) | Should -Be @('Data/Skyrim.synthetic.txt')
        @($audit.differences.versionDifferent.relativePath) | Should -Be @('Data/Skyrim.synthetic.txt')
        @($audit.differences.orderDifferent.relativePath) | Should -Be @('Data/Skyrim.synthetic.txt', 'Data/Update.synthetic.txt')
        @($audit.differences.extra.opaqueId) | Should -Not -BeNullOrEmpty
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

    It 'produces a deterministic plan without changing existing profiles or add-ons' {
        Copy-Item -Path (Join-Path $fixtureRoot 'client-extra\Game\*') -Destination $gameRoot -Recurse -Force
        Copy-Item -Path (Join-Path $fixtureRoot 'client-extra\Profiles\*') -Destination $profileRoot -Recurse -Force
        $before = (Get-FileHash -LiteralPath (Join-Path $profileRoot 'Existing\profile.txt')).Hash

        $first = Invoke-LaptopSetup -Mode Plan -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        $second = Invoke-LaptopSetup -Mode Plan -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        $plan = $first | ConvertFrom-Json

        $first | Should -BeExactly $second
        $plan.schema | Should -Be 'skyrim-engineering.laptop-plan/v1'
        @($plan.actions.type) | Should -Contain 'createProfile'
        @($plan.actions.type) | Should -Contain 'installApproved7zEntry'
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse
        (Get-FileHash -LiteralPath (Join-Path $profileRoot 'Existing\profile.txt')).Hash | Should -Be $before
    }

    It 'refuses apply without separate confirmation and honors WhatIf' {
        {
            Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        } | Should -Throw '*ConfirmApply*'
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply -WhatIf | Out-Null

        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $stateRoot 'client-a.state.json') | Should -BeFalse
    }

    It 'applies only pinned hash-verified packages and rolls back only journaled changes' {
        $stateJson = Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply
        $state = $stateJson | ConvertFrom-Json
        $profile = Join-Path $profileRoot 'Anniversary Together'
        $userFile = Join-Path $profile 'keep-user-file.txt'
        Set-Content -LiteralPath $userFile -Value 'not journaled' -NoNewline

        $state.schema | Should -Be 'skyrim-engineering.laptop-state/v1'
        @($state.mutations).Count | Should -BeGreaterThan 0
        @($state.mutations.relativePath) | Should -Not -Contain 'keep-user-file.txt'
        Test-Path -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') | Should -BeTrue

        Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot | Out-Null

        Test-Path -LiteralPath $userFile -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $profileRoot 'Existing') | Should -BeFalse
    }

    It 'verify reports no shared-package differences after apply' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        $verify = (Invoke-LaptopSetup -Mode Verify -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        $verify.schema | Should -Be 'skyrim-engineering.laptop-audit/v1'
        $verify.mode | Should -Be 'verify'
        $verify.domains.skse.status | Should -Be 'exact'
        $verify.domains.addressLibrary.status | Should -Be 'unsupportedPendingIntake'
        $verify.domains.skyrimTogether.status | Should -Be 'unsupportedPendingIntake'
        @($verify.differences.missing.relativePath | Where-Object { $_ -notin @('Data/Skyrim.synthetic.txt', 'Data/Update.synthetic.txt') }) | Should -BeNullOrEmpty
        @($verify.differences.hashDifferent.relativePath | Where-Object { $_ -notin @('Data/Skyrim.synthetic.txt', 'Data/Update.synthetic.txt') }) | Should -BeNullOrEmpty
    }

    It 'rejects unsafe manifest paths secrets and reparse-point destinations' {
        $badManifest = Join-Path $caseRoot 'bad.json'
        $bad = Get-Content -LiteralPath $canonical -Raw | ConvertFrom-Json
        $bad.items[2] | Add-Member -NotePropertyName sourceRelativePath -NotePropertyValue ('C:' + '/Users/Owner/private.zip')
        $bad | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $badManifest
        {
            Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -Manifest $badManifest
        } | Should -Throw '*safe relative path*'

        $outside = Join-Path $caseRoot 'outside'
        $profile = Join-Path $profileRoot 'Anniversary Together'
        New-Item -ItemType Directory -Path $outside, $profile | Out-Null
        New-Item -ItemType Junction -Path (Join-Path $profile 'mods') -Target $outside | Out-Null
        {
            Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply
        } | Should -Throw '*already exists*'
        @(Get-ChildItem -LiteralPath $outside -Force) | Should -BeNullOrEmpty
    }

    It 'refuses rollback when a journaled file was changed after apply' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        Set-Content -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') -Value 'changed' -NoNewline

        {
            Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        } | Should -Throw '*hash no longer matches*'
        Test-Path -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') | Should -BeTrue
    }

    It 'projects untrusted discovered names and metadata as opaque sanitized records' {
        $privateProfile = Join-Path $profileRoot 'Owner-Private\private-host'
        New-Item -ItemType Directory -Path $privateProfile -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $privateProfile 'account-secret-profile.txt') -Value 'local'
        New-Item -ItemType Directory -Path (Join-Path $gameRoot 'Data') | Out-Null
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\plugins.txt') -Value ('*' + ('7656119' + '1234567890') + '.esp')
        $metadata = @{ 'Data/Skyrim.synthetic.txt' = ('http' + 's://private-host/token') }
        $metadata | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $gameRoot 'versions.json')
        @{
            schema = 'skyrim-engineering.mod-manager/v1'
            name = 'private-host'
            version = 'account-secret'
            activeProfile = 'Owner-Private'
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profileRoot '.mod-manager.json')

        $json = Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        $audit = $json | ConvertFrom-Json

        $json | Should -Not -Match 'Owner-Private|private-host|account-secret|7656119|https?://|token'
        @($audit.categories.machineSpecific.opaqueId) | Should -Not -BeNullOrEmpty
        @($audit.categories.machineSpecific | Where-Object { $null -ne $_.PSObject.Properties['relativePath'] }).Count | Should -Be 0
    }

    It 'reports required runtime tool component and profile domains from actual evidence' {
        Set-Content -LiteralPath (Join-Path $gameRoot 'SkyrimSE.exe') -Value 'synthetic runtime' -NoNewline
        @{ schema = 'skyrim-engineering.synthetic-version/v1'; version = '1.6.1170.0' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $gameRoot 'SkyrimSE.exe.version.json')
        @{ schema = 'skyrim-engineering.mod-manager/v1'; name = 'MO2'; version = '2.5.2'; activeProfile = 'Existing' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $profileRoot '.mod-manager.json')

        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        @($audit.domains.PSObject.Properties.Name) | Should -Be @(
            'runtime', 'creations', 'plugins', 'archives', 'skse', 'addressLibrary', 'skyrimTogether', 'modManager', 'profiles', 'loadOrder'
        )
        $audit.domains.runtime.status | Should -Be 'missing'
        $audit.domains.runtime.actualVersion | Should -BeNullOrEmpty
        $audit.domains.modManager.status | Should -Be 'unavailable'
    }

    It 'derives runtime plugin archive and tool inventory from the explicit roots rather than sidecar claims' {
        Copy-Item -LiteralPath (Get-Command pwsh).Source -Destination (Join-Path $gameRoot 'SkyrimSE.exe')
        @{ schema = 'skyrim-engineering.synthetic-version/v1'; version = '9.9.9.9' } |
            ConvertTo-Json | Set-Content -LiteralPath (Join-Path $gameRoot 'SkyrimSE.exe.version.json')
        New-Item -ItemType Directory -Path (Join-Path $gameRoot 'Data') | Out-Null
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\Observed.esm') -Value 'plugin' -NoNewline
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\Observed.bsa') -Value 'archive' -NoNewline

        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        $audit.domains.runtime.actualVersion | Should -Not -Be '9.9.9.9'
        @($audit.domains.plugins.items).Count | Should -Be 1
        @($audit.domains.archives.items).Count | Should -Be 1
        $audit.domains.plugins.items[0].sha256 | Should -Match '^[0-9a-f]{64}$'
        $audit.domains.archives.items[0].sha256 | Should -Match '^[0-9a-f]{64}$'
    }

    It 'uses the exact canonical Creation classifier and excludes cc-prefixed BA2 archives' {
        Copy-Item -LiteralPath (Get-Command pwsh).Source -Destination (Join-Path $toolRoot 'ModOrganizer.exe')
        New-Item -ItemType Directory -Path (Join-Path $profileRoot 'Profile One'), (Join-Path $gameRoot 'Data') -Force | Out-Null
        foreach ($name in @(
            'ccApproved.esl', 'ccApproved.esm', 'ccApproved.esp', 'ccApproved.bsa',
            'ccBGSSSE001-Fish.esm', 'ccBGSSSE025-AdvDSGS.esm',
            'ccBGSSSE037-Curios.esl', 'ccQDRSSE001-SurvivalMode.esl'
        )) {
            Set-Content -LiteralPath (Join-Path $gameRoot ('Data\' + $name)) -Value $name -NoNewline
        }
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\ccNotACreation.ba2') -Value 'excluded cc archive' -NoNewline
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\Ordinary.esp') -Value 'ordinary plugin' -NoNewline
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\Another.esl') -Value 'ordinary light plugin' -NoNewline
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\Ordinary.bsa') -Value 'ordinary archive' -NoNewline
        Set-Content -LiteralPath (Join-Path $gameRoot 'Data\Textures.ba2') -Value 'ordinary archive' -NoNewline
        Set-Content -LiteralPath (Join-Path $profileRoot 'Profile One\NotInstalled.esp') -Value 'profile metadata' -NoNewline

        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ToolRoot $toolRoot) | ConvertFrom-Json

        $audit.domains.modManager.status | Should -Be 'observed'
        $audit.domains.modManager.executable.sha256 | Should -Match '^[0-9a-f]{64}$'
        @($audit.domains.profiles.items).Count | Should -Be 1
        @($audit.domains.creations.items).Count | Should -Be 8
        @($audit.domains.creations.items | Where-Object kind -eq 'plugin').Count | Should -Be 7
        @($audit.domains.creations.items | Where-Object kind -eq 'archive').Count | Should -Be 1
        @($audit.domains.plugins.items).Count | Should -Be 9
        @($audit.domains.archives.items).Count | Should -Be 4
        $audit.domains.addressLibrary.status | Should -Be 'unsupportedPendingIntake'
        $audit.domains.skyrimTogether.status | Should -Be 'unsupportedPendingIntake'
    }

    It 'installs the complete official SKSE 2.2.6 runtime payload at its readme-required game paths' {
        $officialSkseArchive | Should -Exist
        $sevenZip | Should -Exist
        $state = (Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply) | ConvertFrom-Json
        $profile = Join-Path $profileRoot 'Anniversary Together'

        $state.operation | Should -Be 'approved7zInstall'
        (Get-FileHash -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') -Algorithm SHA256).Hash.ToLowerInvariant() |
            Should -Be '730c2743f6871fbaeb8606c1d3b7a55feca045c3d74858a41b0c6d03cd989fbc'
        (Get-FileHash -LiteralPath (Join-Path $gameRoot 'skse64_1_6_1170.dll') -Algorithm SHA256).Hash.ToLowerInvariant() |
            Should -Be 'c9a2c8a80df6bf2372c5f49468bb2e5ab67786157265b6f29ece9f4eac075d54'
        $scripts = @(Get-ChildItem -LiteralPath (Join-Path $gameRoot 'Data\Scripts') -File -Filter '*.pex')
        $scripts.Count | Should -Be 62
        @($scripts.Name) | Should -Contain 'skse.pex'
        @($scripts.Name) | Should -Contain 'wornobject.pex'
        @($state.mutations | Where-Object { $_.type -eq 'createFile' -and $_.status -eq 'complete' }).Count | Should -Be 64
        @(Get-ChildItem -LiteralPath $profile -File -Recurse -Force).Count | Should -Be 0
        @(Get-ChildItem -LiteralPath $stateRoot -Directory -Force | Where-Object Name -like '.skyrim-engineering-stage-*').Count | Should -Be 0
    }

    It 'refuses a mismatched existing SKSE destination after confirmation and before any other mutation' {
        Set-Content -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') -Value 'user-owned mismatch' -NoNewline

        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply } |
            Should -Throw '*existing*hash*refuse*overwrite*'

        Test-Path -LiteralPath (Join-Path $gameRoot 'skse64_1_6_1170.dll') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $stateRoot 'client-a.state.json') | Should -BeFalse
    }

    It 'reuses an exact existing SKSE file and rollback never deletes it' {
        & $sevenZip e -y ("-o$gameRoot") -- $officialSkseArchive 'skse64_2_02_06\skse64_loader.exe' | Out-Null
        $LASTEXITCODE | Should -Be 0
        $existing = Join-Path $gameRoot 'skse64_loader.exe'
        $before = (Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash.ToLowerInvariant()

        $state = (Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply) | ConvertFrom-Json
        @($state.mutations | Where-Object { $_.relativePath -eq 'skse64_loader.exe' }).status | Should -Be 'preExisting'
        Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot | Out-Null

        Test-Path -LiteralPath $existing -PathType Leaf | Should -BeTrue
        (Get-FileHash -LiteralPath $existing -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $before
    }

    It 'recovers a crash at the exact post-file-move pre-status boundary' -ForEach @(0, 63) {
        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply -InterruptAfter filePublishedBeforeStatus -InterruptMutationIndex $_ } |
            Should -Throw '*simulated interruption*filePublishedBeforeStatus*'

        $interrupted = Get-Content -LiteralPath (Join-Path $stateRoot 'client-a.state.json') -Raw | ConvertFrom-Json
        @($interrupted.mutations | Where-Object status -eq 'publishing').Count | Should -Be 1
        { Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $gameRoot 'Data\Scripts\wornobject.pex') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse
    }

    It 'recovers a crash at the exact post-profile-move pre-status boundary' {
        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply -InterruptAfter profilePublishedBeforeStatus } |
            Should -Throw '*simulated interruption*profilePublishedBeforeStatus*'
        { Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') | Should -BeFalse
    }

    It 'recovers a crash after each game directory is published but before completion is recorded' -ForEach @(0, 1) {
        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply -InterruptAfter directoryPublishedBeforeStatus -InterruptMutationIndex $_ } |
            Should -Throw '*simulated interruption*directoryPublishedBeforeStatus*'

        $interrupted = Get-Content -LiteralPath (Join-Path $stateRoot 'client-a.state.json') -Raw | ConvertFrom-Json
        @($interrupted.mutations | Where-Object { $_.type -eq 'createDirectory' -and $_.status -eq 'publishing' }).Count | Should -Be 1
        { Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $gameRoot 'Data\Scripts') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $gameRoot 'Data') | Should -BeFalse
    }

    It 'recovers journal-owned staging after interruption at every transaction boundary' -ForEach @(
        'journalCreated', 'stageCreated', 'payloadExtracted', 'payloadVerified', 'profilePublished'
    ) {
        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply -InterruptAfter $_ } |
            Should -Throw '*simulated interruption*'
        { Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot } | Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse
        @(Get-ChildItem -LiteralPath $stateRoot -Force | Where-Object Name -like '.skyrim-engineering-stage-*').Count | Should -Be 0
    }

    It 'classifies path matches with bad evidence as unknown and reports root-qualified expected and actual values' {
        Copy-Item -Path (Join-Path $fixtureRoot 'client-mismatch\Game\*') -Destination $gameRoot -Recurse -Force
        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        @($audit.categories.anniversaryBaseline.relativePath) | Should -Not -Contain 'Data/Skyrim.synthetic.txt'
        @($audit.categories.unknownOrIncompatible.relativePath) | Should -Contain 'Data/Skyrim.synthetic.txt'
        $difference = @($audit.differences.hashDifferent | Where-Object relativePath -eq 'Data/Skyrim.synthetic.txt')[0]
        $difference.root | Should -Be 'game'
        $difference.expected | Should -Match '^[0-9a-f]{64}$'
        $difference.actual | Should -Match '^[0-9a-f]{64}$'
    }

    It 'refuses a tampered journal that inserts duplicate wrong-root or unrelated mutations' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        $unrelated = Join-Path $profileRoot 'Anniversary Together\unrelated.txt'
        Set-Content -LiteralPath $unrelated -Value 'unrelated' -NoNewline
        $statePath = Join-Path $stateRoot 'client-a.state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $hash = (Get-FileHash -LiteralPath $unrelated -Algorithm SHA256).Hash.ToLowerInvariant()
        $state.mutations = @($state.mutations) + @(
            [pscustomobject]@{ type = 'createFile'; root = 'game'; relativePath = 'Anniversary Together/unrelated.txt'; sha256 = $hash },
            $state.mutations[0]
        )
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath

        { Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot } | Should -Throw '*journal*'
        Test-Path -LiteralPath $unrelated -PathType Leaf | Should -BeTrue
    }

    It 'rolls back a recoverable applying transaction without touching unjournaled files' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        $statePath = Join-Path $stateRoot 'client-a.state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $state.status = 'applying'
        $state | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $statePath
        $unrelated = Join-Path $profileRoot 'Anniversary Together\keep.txt'
        Set-Content -LiteralPath $unrelated -Value 'keep' -NoNewline

        Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot | Out-Null

        Test-Path -LiteralPath $unrelated -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') | Should -BeFalse
    }

    It 'detects a pre-existing ownership status flip and never deletes the exact user-owned SKSE file' {
        & $sevenZip e -y ("-o$gameRoot") -- $officialSkseArchive 'skse64_2_02_06\skse64_loader.exe' | Out-Null
        $LASTEXITCODE | Should -Be 0
        $existing = Join-Path $gameRoot 'skse64_loader.exe'
        $identityAnchor = Open-PhysicalRootAnchor $gameRoot
        try { $beforeIdentity = Get-FilePhysicalIdentity $existing $identityAnchor }
        finally { $identityAnchor.Dispose() }
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        $statePath = Join-Path $stateRoot 'client-a.state.json'
        $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
        $loader = @($state.mutations | Where-Object relativePath -eq 'skse64_loader.exe')[0]
        $loader.status | Should -Be 'preExisting'
        $loader.status = 'complete'
        $state | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $statePath

        { Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot } |
            Should -Throw '*ownership*'
        Test-Path -LiteralPath $existing -PathType Leaf | Should -BeTrue
        $identityAnchor = Open-PhysicalRootAnchor $gameRoot
        try { (Get-FilePhysicalIdentity $existing $identityAnchor) | Should -BeExactly $beforeIdentity }
        finally { $identityAnchor.Dispose() }
    }

    It 'never removes unrelated files placed at predictable temporary journal names' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        $unownedPayload = Join-Path $stateRoot '.client-a.skse-ae-2-2-6-official.payload.tmp'
        $unownedNext = Join-Path $stateRoot 'client-a.state.json.next'
        Set-Content -LiteralPath $unownedPayload -Value 'unowned' -NoNewline
        Set-Content -LiteralPath $unownedNext -Value 'unowned' -NoNewline

        Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot | Out-Null

        Test-Path -LiteralPath $unownedPayload -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath $unownedNext -PathType Leaf | Should -BeTrue
    }

    It 'continues deterministically when a valid previous journal copy remains after replacement' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        $statePath = Join-Path $stateRoot 'client-a.state.json'
        Copy-Item -LiteralPath $statePath -Destination ($statePath + '.backup')

        { Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot } |
            Should -Not -Throw
        Test-Path -LiteralPath (Join-Path $gameRoot 'skse64_loader.exe') | Should -BeFalse
    }

    It 'refuses missing mismatched and unsupported local package archives before profile mutation' {
        Remove-Item -LiteralPath (Join-Path $packageCache 'skse64_2_02_06.7z')
        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply } |
            Should -Throw '*package cache*missing*'
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse

        [IO.File]::WriteAllBytes((Join-Path $packageCache 'skse64_2_02_06.7z'), [byte[]](1,2,3))
        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply } |
            Should -Throw '*pinned archive hash*'
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse
    }

    It 'rejects traversal mappings and unsupported archive types without writing outside the destination' {
        { Assert-SafeRelativePath '../escape.exe' } | Should -Throw '*safe relative path*'
        $unsupported = [pscustomobject]@{ archiveType = '7z' }
        $unsupported.archiveType = 'zip'
        { Assert-SourcePackage $unsupported $packageCache } | Should -Throw '*Unsupported archive type*only 7z*'
    }

    It 'refuses relative overlapping and ancestor-reparse explicit roots' {
        { & $setupScript -AuditOnly -ClientId client-a -GameRoot '.' -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot } |
            Should -Throw '*fully qualified*'

        $nestedState = Join-Path $profileRoot 'State'
        New-Item -ItemType Directory -Path $nestedState | Out-Null
        { Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $nestedState } |
            Should -Throw '*overlap*'

        $realParent = Join-Path $caseRoot 'real-parent'
        $linkedParent = Join-Path $caseRoot 'linked-parent'
        New-Item -ItemType Directory -Path $realParent | Out-Null
        New-Item -ItemType Junction -Path $linkedParent -Target $realParent | Out-Null
        $nestedProfiles = Join-Path $linkedParent 'profiles'
        New-Item -ItemType Directory -Path $nestedProfiles | Out-Null
        { Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $nestedProfiles -StateDirectory $stateRoot } |
            Should -Throw '*reparse*ancestor*'
    }

    It 'holds a no-delete-share identity lease across the destination parent mutation window' {
        $leaseRoot = Join-Path $caseRoot 'lease-root'
        $parent = Join-Path $leaseRoot 'leased-parent'
        New-Item -ItemType Directory -Path $parent | Out-Null
        $anchor = Open-PhysicalRootAnchor $leaseRoot
        $lease = Open-DirectoryLease $parent $anchor
        try {
            { Rename-Item -LiteralPath $parent -NewName 'raced-parent' -ErrorAction Stop } | Should -Throw
            { $lease.AssertPathStillSame($parent) } | Should -Not -Throw
        }
        finally { $lease.Dispose(); $anchor.Dispose() }

        { Rename-Item -LiteralPath $parent -NewName 'released-parent' -ErrorAction Stop } | Should -Not -Throw
    }

    It 'rejects a parent handle reached through a redirected higher ancestor outside its anchored physical root' {
        Initialize-PhysicalIdentityApi
        $intendedRoot = Join-Path $caseRoot 'anchored-game'
        $data = Join-Path $intendedRoot 'Data'
        $outside = Join-Path $caseRoot 'outside-tree'
        New-Item -ItemType Directory -Path $data, (Join-Path $outside 'Scripts') -Force | Out-Null
        $anchor = [SkyrimEngineering.DirectoryLease]::OpenRoot($intendedRoot)
        try {
            Rename-Item -LiteralPath $data -NewName 'Data-original'
            New-Item -ItemType Junction -Path $data -Target $outside | Out-Null

            { [SkyrimEngineering.DirectoryLease]::OpenContained((Join-Path $data 'Scripts'), $anchor) } |
                Should -Throw '*outside the anchored physical root*'
        }
        finally { $anchor.Dispose() }
    }

    It 'does not let a caller manifest self-authorize arbitrary saves archives or packages' {
        foreach ($extension in @('.ess', '.zip', '.exe')) {
            $manifestPath = Join-Path $caseRoot ('arbitrary-' + $extension.TrimStart('.') + '.json')
            $manifestDirectory = Split-Path -Parent $manifestPath
            $sourceName = 'arbitrary' + $extension
            $sourcePath = Join-Path $manifestDirectory $sourceName
            Set-Content -LiteralPath $sourcePath -Value 'caller-controlled' -NoNewline
            $manifest = Get-Content -LiteralPath $canonical -Raw | ConvertFrom-Json
            $manifest.items = @($manifest.items) + [pscustomobject]@{
                id = 'caller-approved'; category = 'approvedShared'; root = 'profile'
                relativePath = ('mods/Caller/' + $sourceName)
                sha256 = (Get-FileHash -LiteralPath $sourcePath -Algorithm SHA256).Hash.ToLowerInvariant()
                version = '1.0'; approved = $true; free = $true; sourceRelativePath = $sourceName
            }
            $manifest | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $manifestPath

            { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -Manifest $manifestPath -ConfirmApply } |
                Should -Throw '*catalog*'
            Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together\mods\Caller') | Should -BeFalse
        }
    }

    It 'refuses to merge into a pre-existing Anniversary Together profile and preserves every file' {
        $existingProfile = Join-Path $profileRoot 'Anniversary Together'
        New-Item -ItemType Directory -Path (Join-Path $existingProfile 'mods\Existing') -Force | Out-Null
        Set-Content -LiteralPath (Join-Path $existingProfile 'profile.ini') -Value 'owned=true' -NoNewline
        Set-Content -LiteralPath (Join-Path $existingProfile 'mods\Existing\addon.txt') -Value 'addon' -NoNewline
        $before = @(Get-ChildItem -LiteralPath $existingProfile -File -Recurse | ForEach-Object {
            '{0}:{1}' -f $_.FullName.Substring($existingProfile.Length), (Get-FileHash -LiteralPath $_.FullName).Hash
        }) -join '|'

        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply } |
            Should -Throw '*already exists*'

        $after = @(Get-ChildItem -LiteralPath $existingProfile -File -Recurse | ForEach-Object {
            '{0}:{1}' -f $_.FullName.Substring($existingProfile.Length), (Get-FileHash -LiteralPath $_.FullName).Hash
        }) -join '|'
        $after | Should -BeExactly $before
        Test-Path -LiteralPath (Join-Path $stateRoot 'client-a.state.json') | Should -BeFalse
    }
}
