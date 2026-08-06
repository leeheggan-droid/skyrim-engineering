#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

Set-StrictMode -Version Latest

Describe 'Progressive qualification boundary' {
    BeforeAll {
        $repoRoot = Split-Path -Parent $PSScriptRoot
        $statePath = Join-Path $repoRoot 'qualification\state.json'
        $assessmentPath = Join-Path $repoRoot 'tests\fixtures\evidence\assessment.json'
    }

    It 'keeps live tracks explicit without blocking provisional construction' {
        $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json

        $state.schema | Should -Be 'skyrim-engineering.qualification/v1'
        @($state.tracks.id) | Should -Be @('creation-kit', 'xedit', 'papyrus-runtime', 'together-production')
        @($state.tracks | Where-Object status -NotIn @('verified', 'blocked', 'untested')).Count | Should -Be 0
        $state.provisionalReleaseBlocked | Should -BeFalse
        $state.qualifiedReleaseBlocked | Should -BeTrue
    }

    It 'applies the expertise score only to the qualified release gate' {
        $state = Get-Content -Raw -LiteralPath $statePath | ConvertFrom-Json
        $assessment = Get-Content -Raw -LiteralPath $assessmentPath | ConvertFrom-Json

        $assessment.gateStatus | Should -Be 'BLOCKED'
        $assessment.gateAppliesTo | Should -Be 'v1.0-qualified'
        $state.qualifiedReleaseBlocked | Should -BeTrue
        $state.provisionalReleaseBlocked | Should -BeFalse
    }
}
