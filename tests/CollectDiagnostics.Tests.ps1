Describe 'collect-diagnostics' {
    BeforeAll {
        $script:collectorPath = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\collect-diagnostics.ps1'
        $script:diagnosticRoot = Join-Path $TestDrive 'input'
        $script:outputRoot = Join-Path $TestDrive 'bundle'
        $null = New-Item -ItemType Directory -Path (Join-Path $diagnosticRoot 'nested') -Force

        $script:syntheticUser = 'Test' + 'User'
        $script:syntheticSteamId = '7656119' + '8012345678'
        $script:syntheticToken = 'ey' + 'SyntheticBearerToken'
        $content = @(
            ((('C:' + '\Us' + 'ers\{0}\Documents\My Games')) -f $script:syntheticUser)
            ((('C:' + '/Us' + 'ers/{0}/Documents') -f $script:syntheticUser))
            ('username={0}' -f $script:syntheticUser)
            ('/Users/{0}/Library/Application Support' -f $script:syntheticUser)
            ('steamId={0}' -f $script:syntheticSteamId)
            'address=192.168.10.25'
            'password=synthetic-password'
            ('Authorization: Bearer {0}' -f $script:syntheticToken)
            'Unhandled exception at FormID 0x2A00C123'
            '  at QuestScript.OnInit()'
        ) -join "`n"
        [System.IO.File]::WriteAllText((Join-Path $diagnosticRoot 'nested\engine.log'), $content, (New-Object System.Text.UTF8Encoding($false)))
        [System.IO.File]::WriteAllText((Join-Path $diagnosticRoot 'settings.ini'), 'language=en', (New-Object System.Text.UTF8Encoding($false)))
    }

    It 'collects only deterministic sanitized diagnostic evidence' {
        # Break caught: removing typed redaction or leaking an absolute input path.
        & $collectorPath -InputPath $diagnosticRoot -OutputDirectory $outputRoot
        $firstManifest = Get-Content -LiteralPath (Join-Path $outputRoot 'diagnostic-manifest.json') -Raw
        $sanitizedLog = Get-Content -LiteralPath (Join-Path $outputRoot 'nested\engine.log') -Raw

        Remove-Item -LiteralPath $outputRoot -Recurse -Force
        & $collectorPath -InputPath $diagnosticRoot -OutputDirectory $outputRoot
        $secondManifest = Get-Content -LiteralPath (Join-Path $outputRoot 'diagnostic-manifest.json') -Raw

        $manifest = $firstManifest | ConvertFrom-Json
        $manifest.schema | Should -Be 'skyrim-engineering.diagnostics/v1'
        $manifest.files.relativePath | Should -Be @('nested/engine.log', 'settings.ini')
        $firstManifest | Should -Be $secondManifest
        $firstManifest | Should -Not -Match ([regex]::Escape($diagnosticRoot))
        $bundleText = @(Get-ChildItem -LiteralPath $outputRoot -Recurse -File | ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
        @($script:syntheticUser, $script:syntheticSteamId, '192.168.10.25', 'synthetic-password', $script:syntheticToken) |
            ForEach-Object { $bundleText | Should -Not -Match ([regex]::Escape($_)) }
        @('[REDACTED:username]', '[REDACTED:steam-id]', '[REDACTED:ipv4]', '[REDACTED:password]', '[REDACTED:token]') |
            ForEach-Object { $sanitizedLog | Should -Match ([regex]::Escape($_)) }
        $sanitizedLog | Should -Match 'FormID 0x2A00C123'
        $sanitizedLog | Should -Match 'at QuestScript\.OnInit\(\)'
    }

    It 'refuses dumps saves and binary inputs' {
        # Break caught: broadening collection beyond the text allowlist.
        foreach ($extension in @('.dmp', '.ess', '.skse', '.dll')) {
            $path = Join-Path $TestDrive ("refused{0}" -f $extension)
            [System.IO.File]::WriteAllBytes($path, [byte[]](0, 1, 2, 3))
            { & $collectorPath -InputPath $path -OutputDirectory (Join-Path $TestDrive ("out{0}" -f $extension)) } |
                Should -Throw '*not permitted*'
        }
    }

    It 'enforces the 25 MiB limit before reading an allowlisted file' {
        # Break caught: accepting an unbounded text file.
        $largePath = Join-Path $TestDrive 'large.log'
        $stream = [System.IO.File]::Create($largePath)
        try {
            $stream.SetLength((25 * 1024 * 1024) + 1)
        }
        finally {
            $stream.Dispose()
        }

        { & $collectorPath -InputPath $largePath -OutputDirectory (Join-Path $TestDrive 'large-output') } |
            Should -Throw '*25 MiB*'
    }

    It 'rejects source-tree outputs and existing bundles unless Force is explicit' {
        # Break caught: writing into evidence sources or silently replacing a prior bundle.
        { & $collectorPath -InputPath $diagnosticRoot -OutputDirectory (Join-Path $diagnosticRoot 'output') } |
            Should -Throw '*inside an input source*'

        $null = New-Item -ItemType Directory -Path $outputRoot -Force
        [System.IO.File]::WriteAllText((Join-Path $outputRoot 'existing.txt'), 'retain unless Force')
        { & $collectorPath -InputPath $diagnosticRoot -OutputDirectory $outputRoot } |
            Should -Throw '*already exists*'
        & $collectorPath -InputPath $diagnosticRoot -OutputDirectory $outputRoot -Force
        Test-Path -LiteralPath (Join-Path $outputRoot 'diagnostic-manifest.json') | Should -BeTrue
    }

    It 'rejects output paths equal to inside or above an input before Force can delete evidence' {
        # Break caught: Force recursively deleting the source tree or its unrelated siblings.
        $overlapRoot = Join-Path $TestDrive 'overlap'
        $sourceRoot = Join-Path $overlapRoot 'session'
        $sourceLog = Join-Path $sourceRoot 'engine.log'
        $unrelatedFile = Join-Path $overlapRoot 'unrelated.txt'
        $null = New-Item -ItemType Directory -Path $sourceRoot -Force
        [System.IO.File]::WriteAllText($sourceLog, 'safe diagnostic')
        [System.IO.File]::WriteAllText($unrelatedFile, 'must survive')

        foreach ($output in @($sourceRoot, (Join-Path $sourceRoot 'bundle'), $overlapRoot)) {
            { & $collectorPath -InputPath $sourceRoot -OutputDirectory $output -Force } |
                Should -Throw '*overlaps*'
            Test-Path -LiteralPath $sourceLog | Should -BeTrue
            Test-Path -LiteralPath $unrelatedFile | Should -BeTrue
        }

        { & $collectorPath -InputPath $sourceLog -OutputDirectory $sourceLog -Force } |
            Should -Throw '*overlaps*'
        Test-Path -LiteralPath $sourceLog | Should -BeTrue
    }

    It 'refuses an output reparse point before Force can touch its target' {
        # Break caught: Force following a junction outside the approved output directory.
        $sourceRoot = Join-Path $TestDrive 'junction-source'
        $targetRoot = Join-Path $TestDrive 'junction-target'
        $junctionPath = Join-Path $TestDrive 'junction-output'
        $null = New-Item -ItemType Directory -Path $sourceRoot, $targetRoot -Force
        [System.IO.File]::WriteAllText((Join-Path $sourceRoot 'engine.log'), 'safe diagnostic')
        $sentinel = Join-Path $targetRoot 'sentinel.txt'
        [System.IO.File]::WriteAllText($sentinel, 'must survive')
        $null = New-Item -ItemType Junction -Path $junctionPath -Target $targetRoot

        { & $collectorPath -InputPath $sourceRoot -OutputDirectory $junctionPath -Force } |
            Should -Throw '*reparse point*'
        Test-Path -LiteralPath $sentinel | Should -BeTrue
    }

    It 'reserves the generated manifest name and records hashes of every final file' {
        # Break caught: replacing an input after recording its stale hash in the manifest.
        $sourceRoot = Join-Path $TestDrive 'manifest-source'
        $reservedInput = Join-Path $sourceRoot 'diagnostic-manifest.json'
        $outputRoot = Join-Path $TestDrive 'manifest-output'
        $null = New-Item -ItemType Directory -Path $sourceRoot -Force
        [System.IO.File]::WriteAllText($reservedInput, '{"not":"generated"}')
        { & $collectorPath -InputPath $sourceRoot -OutputDirectory $outputRoot } |
            Should -Throw '*reserved*'
        Test-Path -LiteralPath $reservedInput | Should -BeTrue

        Remove-Item -LiteralPath $reservedInput -Force
        [System.IO.File]::WriteAllText((Join-Path $sourceRoot 'engine.log'), 'safe diagnostic')
        & $collectorPath -InputPath $sourceRoot -OutputDirectory $outputRoot
        $manifest = Get-Content -LiteralPath (Join-Path $outputRoot 'diagnostic-manifest.json') -Raw | ConvertFrom-Json
        foreach ($entry in $manifest.files) {
            $outputFile = Join-Path $outputRoot ($entry.relativePath.Replace('/', '\\'))
            $item = Get-Item -LiteralPath $outputFile
            $item.Length | Should -Be $entry.size
            (Get-FileHash -LiteralPath $outputFile -Algorithm SHA256).Hash.ToLowerInvariant() | Should -Be $entry.sha256
        }
    }
}
