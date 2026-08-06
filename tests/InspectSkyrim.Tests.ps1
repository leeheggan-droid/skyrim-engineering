Describe 'inspect-skyrim' {
    BeforeAll {
        $script:inspectorPath = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\inspect-skyrim.ps1'
        $script:steamFixture = Join-Path $PSScriptRoot 'fixtures\steam'
        $script:gameFixture = Join-Path $PSScriptRoot 'fixtures\game'
    }

    It 'emits deterministic, privacy-safe Steam inspection JSON from explicit paths' {
        if (-not (Test-Path -LiteralPath $inspectorPath)) {
            $false | Should -BeTrue
            return
        }

        $first = & $inspectorPath -SteamRoot $steamFixture -GameRoot $gameFixture -Json
        $second = & $inspectorPath -SteamRoot $steamFixture -GameRoot $gameFixture -Json
        $inspection = $first | ConvertFrom-Json

        $inspection.schema | Should -Be 'skyrim-engineering.inspect/v1'
        $inspection.store | Should -Be 'Steam'
        $inspection.runtime | Should -Be '1.6.1170.0'
        $inspection.executable | Should -Be 'SkyrimSE.exe'
        $first | Should -Be $second
        $first | Should -Not -Match ([regex]::Escape($gameFixture))
        $first | Should -Not -Match '\d{17}'
    }
}
