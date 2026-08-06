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
        @($script:syntheticUser, $script:syntheticSteamId, '192.168.10.25', 'synthetic-password', $script:syntheticToken) |
            ForEach-Object { $sanitizedLog | Should -Not -Match ([regex]::Escape($_)) }
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
}
