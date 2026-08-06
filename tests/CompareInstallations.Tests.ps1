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

    It 'treats an omitted plugin from a present load order as an order difference' {
        if (-not (Test-Path -LiteralPath $comparisonPath)) {
            $false | Should -BeTrue
            return
        }

        $output = & $comparisonPath -ManifestPath @(
            (Join-Path $manifestFixture 'load-order-complete.json'),
            (Join-Path $manifestFixture 'load-order-incomplete.json')) -Json
        $exitCode = $LASTEXITCODE
        $comparison = $output | ConvertFrom-Json

        $exitCode | Should -Be 2
        @($comparison.orderDifferent.relativePath) | Should -Be @('ccTEST-B.esl')
    }

    It 'returns exit code one for omitted unknown or duplicate loadOrder entries' {
        if (-not (Test-Path -LiteralPath $comparisonPath)) {
            $false | Should -BeTrue
            return
        }

        @('load-order-omitted.json', 'load-order-unknown.json', 'load-order-duplicate.json') | ForEach-Object {
            & $comparisonPath -ManifestPath (Join-Path $manifestFixture $_) -Json 2>$null | Out-Null
            $LASTEXITCODE | Should -Be 1
        }
    }

    It 'returns exit code one for every malformed emitted manifest shape' {
        if (-not (Test-Path -LiteralPath $comparisonPath)) {
            $false | Should -BeTrue
            return
        }

        @(
            'invalid-name-path.json',
            'invalid-portable-path.json',
            'invalid-negative-size.json',
            'invalid-string-size.json',
            'invalid-extension-kind.json',
            'invalid-plugin-type.json',
            'invalid-plugin-flag.json',
            'invalid-archive-convention.json'
        ) | ForEach-Object {
            & $comparisonPath -ManifestPath (Join-Path $manifestFixture $_) -Json 2>$null | Out-Null
            $LASTEXITCODE | Should -Be 1
        }
    }
}
