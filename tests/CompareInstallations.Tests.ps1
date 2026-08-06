Describe 'compare-installations' {
    BeforeAll {
        $script:comparisonPath = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\compare-installations.ps1'
        $script:manifestFixture = Join-Path $PSScriptRoot 'fixtures\manifests'
    }

    It 'reports parity with exit code zero' {
        if (-not (Test-Path -LiteralPath $comparisonPath)) {
            $false | Should -BeTrue
            return
        }

        $output = & $comparisonPath -ManifestPath @(
            (Join-Path $manifestFixture 'parity-a.json'),
            (Join-Path $manifestFixture 'parity-b.json')) -Json
        $exitCode = $LASTEXITCODE
        $comparison = $output | ConvertFrom-Json

        $exitCode | Should -Be 0
        $comparison.schema | Should -Be 'skyrim-engineering.comparison/v1'
        @($comparison.missing, $comparison.extra, $comparison.hashDifferent, $comparison.sizeDifferent, $comparison.orderDifferent) |
            ForEach-Object { @($_) | Should -BeNullOrEmpty }
    }

    It 'categorizes missing extra hash size and load-order differences with exit code two' {
        if (-not (Test-Path -LiteralPath $comparisonPath)) {
            $false | Should -BeTrue
            return
        }

        $output = & $comparisonPath -ManifestPath @(
            (Join-Path $manifestFixture 'baseline.json'),
            (Join-Path $manifestFixture 'different.json')) -Json
        $exitCode = $LASTEXITCODE
        $comparison = $output | ConvertFrom-Json

        $exitCode | Should -Be 2
        @($comparison.missing.relativePath) | Should -Be @('ccTEST-Missing.esl')
        @($comparison.extra.relativePath) | Should -Be @('ccTEST-Extra.esl')
        @($comparison.hashDifferent.relativePath) | Should -Be @('ccTEST-Hash.esl')
        @($comparison.sizeDifferent.relativePath) | Should -Be @('ccTEST-Size.esl')
        @($comparison.orderDifferent.relativePath) | Should -Be @('ccTEST-A.esl', 'ccTEST-B.esl')
    }

    It 'returns exit code one for malformed manifests' {
        if (-not (Test-Path -LiteralPath $comparisonPath)) {
            $false | Should -BeTrue
            return
        }

        & $comparisonPath -ManifestPath (Join-Path $manifestFixture 'malformed.json') -Json 2>$null | Out-Null
        $LASTEXITCODE | Should -Be 1
    }
}
