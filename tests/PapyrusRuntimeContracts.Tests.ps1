#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Describe 'Papyrus runtime qualification contracts' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $papyrusRoot = Join-Path $PSScriptRoot 'fixtures\papyrus'
        $prepare = Get-Content -Raw (Join-Path $papyrusRoot 'Prepare-RuntimeMigration.ps1')
        $capture = Get-Content -Raw (Join-Path $papyrusRoot 'Test-RuntimeCapture.ps1')
        $contract = Get-Content -Raw (Join-Path $papyrusRoot 'papyrus-runtime-contract.json') | ConvertFrom-Json
        $runbook = Get-Content -Raw (Join-Path $papyrusRoot 'papyrus-runtime-runbook.md')
    }

    It 'binds an original plugin and exact Quest activation contract during preparation' {
        foreach ($parameter in @('Plugin', 'PluginEvidence', 'CompilerEvidence')) {
            $prepare | Should -Match ([regex]::Escape("`$$parameter"))
        }
        foreach ($field in @('originalOnly', 'questFormId', 'scriptName', 'attachment', 'activation', 'pluginSha256')) {
            $prepare | Should -Match $field
        }
        $prepare | Should -Match 'start-game-enabled'
        $prepare | Should -Match 'SEG_RuntimeMigration'
    }

    It 'binds runtime profile load order logging and anonymous run provenance' {
        foreach ($parameter in @('RuntimeEvidence', 'ProfileEvidence', 'RunId', 'V1PhaseUtc', 'V2PhaseUtc')) {
            $capture | Should -Match ([regex]::Escape("`$$parameter"))
        }
        foreach ($field in @('runtimeVersion', 'executableSha256', 'anonymousProfileId', 'loadOrder', 'bEnableLogging', 'bEnableTrace')) {
            $capture | Should -Match $field
        }
        $capture | Should -Match '1\.6\.1170\.0'
    }

    It 'requires conservative ESS structure freshness and exact phase markers' {
        $capture | Should -Match 'TESV_SAVEGAME'
        $capture | Should -Match '1048576'
        $capture | Should -Match 'LastWriteTimeUtc'
        $capture | Should -Match 'SEG_EVENT_OK schema=1'
        $capture | Should -Match 'SEG_EVENT_OK schema=2'
        $capture | Should -Match 'SEG_MIGRATION_NEW from=1 to=2'
        $capture | Should -Match 'SEG_MIGRATION_OLD schema=1'
    }

    It 'documents a deterministic isolated human run without live-tree or save copying' {
        $runbook | Should -Match 'isolated'
        $runbook | Should -Match 'profile-specific INI'
        $runbook | Should -Match 'Start Game Enabled Quest'
        $runbook | Should -Match 'V1'
        $runbook | Should -Match 'V2'
        $runbook | Should -Match 'Never copy.*save'
        $runbook | Should -Match 'human review'
        $runbook | Should -Match 'do not.*live.*Data'
    }

    It 'keeps the live qualification state blocked and review-gated' {
        $state = Get-Content -Raw (Join-Path $repoRoot 'qualification\state.json') | ConvertFrom-Json
        $track = $state.tracks | Where-Object id -eq 'papyrus-runtime'
        $track.status | Should -Be 'blocked'
        $track.humanReviewRequired | Should -BeTrue
        $contract.status | Should -Be 'BLOCKED'
        $contract.runtimeReplayCaptured | Should -BeFalse
    }

    It 'refuses reparse points and binds compiler source and PEX hashes' {
        $prepare | Should -Match 'ReparsePoint'
        $capture | Should -Match 'ReparsePoint'
        foreach ($field in @('compilerSha256', 'sourceSha256', 'pexSha256', 'commandSha256')) {
            $prepare | Should -Match $field
        }
    }
}
