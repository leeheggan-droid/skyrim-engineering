#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.9.0' }

Describe 'setup-laptop safe bootstrap' {
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
            if ($WhatIf) { $arguments.WhatIf = $true }
            & $script:setupScript @arguments
        }
    }

    BeforeEach {
        $script:caseRoot = Join-Path $TestDrive ([guid]::NewGuid().ToString('N'))
        $script:gameRoot = Join-Path $caseRoot 'Game'
        $script:profileRoot = Join-Path $caseRoot 'Profiles'
        $script:stateRoot = Join-Path $caseRoot 'State'
        New-Item -ItemType Directory -Path $gameRoot, $profileRoot, $stateRoot -Force | Out-Null
    }

    It 'requires exactly one explicit mode and an anonymous client id' {
        {
            & $setupScript -ClientId client-a -GameRoot $gameRoot -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot
        } | Should -Throw
        {
            & $setupScript -AuditOnly -Plan -ClientId client-a -GameRoot $gameRoot -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot
        } | Should -Throw
        {
            & $setupScript -AuditOnly -ClientId 'Lee-Laptop' -GameRoot $gameRoot -ProfileRoot $profileRoot -CanonicalManifest $canonical -StateDirectory $stateRoot
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
            'mods/Address Library/address-library.synthetic.txt',
            'mods/SKSE/skse.synthetic.txt',
            'mods/Skyrim Together/skyrim-together.synthetic.txt'
        )
        @($audit.differences.hashDifferent.relativePath) | Should -Be @('Data/Skyrim.synthetic.txt')
        @($audit.differences.versionDifferent.relativePath) | Should -Be @('Data/Skyrim.synthetic.txt')
        @($audit.differences.orderDifferent.relativePath) | Should -Be @('Data/Skyrim.synthetic.txt', 'Data/Update.synthetic.txt')
        @($audit.differences.extra.relativePath) | Should -Contain 'Data/plugins.txt'
        $first | Should -Not -Match ([regex]::Escape($caseRoot))
        $first | Should -Not -Match ([regex]::Escape([Environment]::UserName))
        $first | Should -Not -Match '(?i)(password|token|steamid|https?://|\\\\)'
    }

    It 'classifies unlisted profile content as machine-specific and game content as unknown' {
        Copy-Item -Path (Join-Path $fixtureRoot 'client-extra\Game\*') -Destination $gameRoot -Recurse -Force
        Copy-Item -Path (Join-Path $fixtureRoot 'client-extra\Profiles\*') -Destination $profileRoot -Recurse -Force
        $audit = (Invoke-LaptopSetup -Mode AuditOnly -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        @($audit.categories.machineSpecific.relativePath) | Should -Contain 'Existing/profile.txt'
        @($audit.categories.unknownOrIncompatible.relativePath) | Should -Contain 'Data/PersonalWeather.synthetic.txt'
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
        @($plan.actions.type) | Should -Contain 'installApprovedPackage'
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
        Test-Path -LiteralPath (Join-Path $profile 'mods\SKSE\skse.synthetic.txt') | Should -BeTrue

        Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot | Out-Null

        Test-Path -LiteralPath $userFile -PathType Leaf | Should -BeTrue
        Test-Path -LiteralPath (Join-Path $profile 'mods\SKSE\skse.synthetic.txt') | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $profileRoot 'Existing') | Should -BeFalse
    }

    It 'verify reports no shared-package differences after apply' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        $verify = (Invoke-LaptopSetup -Mode Verify -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot) | ConvertFrom-Json

        $verify.schema | Should -Be 'skyrim-engineering.laptop-audit/v1'
        $verify.mode | Should -Be 'verify'
        @($verify.differences.missing.relativePath | Where-Object { $_ -like 'mods/*' }) | Should -BeNullOrEmpty
        @($verify.differences.hashDifferent.relativePath | Where-Object { $_ -like 'mods/*' }) | Should -BeNullOrEmpty
    }

    It 'rejects unsafe manifest paths secrets and reparse-point destinations' {
        $badManifest = Join-Path $caseRoot 'bad.json'
        $bad = Get-Content -LiteralPath $canonical -Raw | ConvertFrom-Json
        $bad.items[2].sourceRelativePath = 'C:/Users/Lee/token.zip'
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
        } | Should -Throw '*reparse point*'
        @(Get-ChildItem -LiteralPath $outside -Force) | Should -BeNullOrEmpty
    }

    It 'refuses rollback when a journaled file was changed after apply' {
        Invoke-LaptopSetup -Mode Apply -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot -ConfirmApply | Out-Null
        Set-Content -LiteralPath (Join-Path $profileRoot 'Anniversary Together\mods\SKSE\skse.synthetic.txt') -Value 'changed' -NoNewline

        {
            Invoke-LaptopSetup -Mode Rollback -GameRoot $gameRoot -ProfileRoot $profileRoot -StateDirectory $stateRoot
        } | Should -Throw '*hash no longer matches*'
        Test-Path -LiteralPath (Join-Path $profileRoot 'Anniversary Together\mods\SKSE\skse.synthetic.txt') | Should -BeTrue
    }
}
