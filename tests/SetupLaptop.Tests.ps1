#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.9.0' }

Describe 'setup-laptop safe bootstrap' {
    BeforeAll {
        $script:setupScript = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\setup-laptop.ps1'
        $script:fixtureRoot = Join-Path $PSScriptRoot 'fixtures\laptop'
        $script:canonical = Join-Path $fixtureRoot 'canonical\manifest.json'

        function Import-SetupFunction([string]$Name) {
            $tokens = $null; $errors = $null
            $ast = [Management.Automation.Language.Parser]::ParseFile($script:setupScript, [ref]$tokens, [ref]$errors)
            $definition = $ast.Find({ param($node) $node -is [Management.Automation.Language.FunctionDefinitionAst] -and $node.Name -ceq $Name }, $true)
            if ($null -eq $definition) { throw "Missing setup function: $Name" }
            Invoke-Expression ($definition.Extent.Text -replace ('^function\s+' + [regex]::Escape($Name)), ('function script:' + $Name))
        }
        foreach ($name in @('Convert-ToPortablePath', 'Assert-SafeRelativePath', 'Get-NormalizedPath', 'Assert-NoReparseAncestor', 'Get-LowerHash', 'Assert-ContainedPath', 'Assert-SourcePackage', 'Write-ApprovedZipEntry')) {
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
        New-Item -ItemType Directory -Path $gameRoot, $profileRoot, $stateRoot, $packageCache -Force | Out-Null
        $archives = [ordered]@{
            'skse-2.2.6.zip' = 'UEsDBBQAAAAIAAAAISiXPmDqGgAAABUAAAARAAAAc2tzZTY0X2xvYWRlci5leGUBFQDq/3N5bnRoZXRpYy1za3NlLWxvYWRlclBLAQIUABQAAAAIAAAAISiXPmDqGgAAABUAAAARAAAAAAAAAAAAAAAAAAAAAABza3NlNjRfbG9hZGVyLmV4ZVBLBQYAAAAAAQABAD8AAABJAAAAAAA='
            'address-library-11.zip' = 'UEsDBBQAAAAIAAAAISj51lYXHgAAABkAAAAZAAAAdmVyc2lvbmxpYi0xLTYtMTE3MC0wLmJpbgEZAOb/c3ludGhldGljLWFkZHJlc3MtbGlicmFyeVBLAQIUABQAAAAIAAAAISj51lYXHgAAABkAAAAZAAAAAAAAAAAAAAAAAAAAAAB2ZXJzaW9ubGliLTEtNi0xMTcwLTAuYmluUEsFBgAAAAABAAEARwAAAFUAAAAAAA=='
            'skyrim-together-1.7.1.zip' = 'UEsDBBQAAAAIAAAAISiApSvtHgAAABkAAAASAAAAU2t5cmltVG9nZXRoZXIuZXhlARkA5v9zeW50aGV0aWMtdG9nZXRoZXItY2xpZW50UEsBAhQAFAAAAAgAAAAhKIClK+0eAAAAGQAAABIAAAAAAAAAAAAAAAAAAAAAAFNreXJpbVRvZ2V0aGVyLmV4ZVBLBQYAAAAAAQABAEAAAABOAAAAAAA='
        }
        foreach ($archive in $archives.GetEnumerator()) {
            [IO.File]::WriteAllBytes((Join-Path $packageCache $archive.Key), [Convert]::FromBase64String($archive.Value))
        }
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
        @($audit.differences.missing.relativePath) | Should -Be @(
            'mods/Address Library/versionlib-1-6-1170-0.bin',
            'mods/SKSE/skse64_loader.exe',
            'mods/Skyrim Together/SkyrimTogether.exe'
        )
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
        @($plan.actions.type) | Should -Contain 'installApprovedZipEntry'
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
        Test-Path -LiteralPath (Join-Path $profile 'mods\SKSE\skse64_loader.exe') | Should -BeTrue

        Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot | Out-Null

        Test-Path -LiteralPath $userFile -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $profile 'mods\SKSE\skse64_loader.exe') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $profileRoot 'Existing') | Should -BeFalse
    }

    It 'verify reports no shared-package differences after apply' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        $verify = (Invoke-LaptopSetup -Mode Verify -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        $verify.schema | Should -Be 'skyrim-engineering.laptop-audit/v1'
        $verify.mode | Should -Be 'verify'
        $verify.domains.skse.status | Should -Be 'exact'
        $verify.domains.addressLibrary.status | Should -Be 'exact'
        $verify.domains.skyrimTogether.status | Should -Be 'exact'
        @($verify.differences.missing.relativePath | Where-Object { $_ -like 'mods/*' }) | Should -BeNullOrEmpty
        @($verify.differences.hashDifferent.relativePath | Where-Object { $_ -like 'mods/*' }) | Should -BeNullOrEmpty
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
        Set-Content -LiteralPath (Join-Path $profileRoot 'Anniversary Together\mods\SKSE\skse64_loader.exe') -Value 'changed' -NoNewline

        {
            Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        } | Should -Throw '*hash no longer matches*'
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together\mods\SKSE\skse64_loader.exe') | Should -BeTrue
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
        $audit.domains.runtime.actualVersion | Should -Be '1.6.1170.0'
        $audit.domains.modManager.actualVersion | Should -Be '2.5.2'
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
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together\mods\SKSE\skse64_loader.exe') | Should -BeFalse
    }

    It 'never removes unrelated files placed at predictable temporary journal names' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        $unownedPayload = Join-Path $stateRoot '.client-a.skse-2-2-6.payload.tmp'
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
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together\mods\SKSE\skse64_loader.exe') | Should -BeFalse
    }

    It 'refuses missing mismatched and unsupported local package archives before profile mutation' {
        Remove-Item -LiteralPath (Join-Path $packageCache 'skse-2.2.6.zip')
        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply } |
            Should -Throw '*package cache*missing*'
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse

        [IO.File]::WriteAllBytes((Join-Path $packageCache 'skse-2.2.6.zip'), [byte[]](1,2,3))
        { Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply } |
            Should -Throw '*pinned archive hash*'
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together') | Should -BeFalse
    }

    It 'rejects traversal entries and unsupported archive types without writing outside the destination' {
        $malicious = Join-Path $packageCache 'malicious.zip'
        $archiveStream = [IO.File]::Open($malicious, [IO.FileMode]::CreateNew)
        $archive = New-Object IO.Compression.ZipArchive($archiveStream, [IO.Compression.ZipArchiveMode]::Create, $false)
        try {
            $entry = $archive.CreateEntry('../escape.exe')
            $writer = New-Object IO.StreamWriter($entry.Open())
            try { $writer.Write('escape') } finally { $writer.Dispose() }
        }
        finally { $archive.Dispose(); $archiveStream.Dispose() }
        $package = [pscustomobject]@{ entryRelativePath = '../escape.exe'; sha256 = ('0' * 64) }
        { Write-ApprovedZipEntry $package $malicious (Join-Path $profileRoot 'payload.exe') } | Should -Throw '*safe relative path*'
        Test-Path -LiteralPath (Join-Path $caseRoot 'escape.exe') | Should -BeFalse

        $unsupported = [pscustomobject]@{ archiveType = '7z' }
        { Assert-SourcePackage $unsupported $packageCache } | Should -Throw '*Unsupported archive type*only ZIP*'
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
