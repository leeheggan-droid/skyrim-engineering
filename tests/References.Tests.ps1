Describe 'Versioned Skyrim engineering references' {
    BeforeAll {
        $referenceRoot = 'skill/skyrim-engineering/references'
        $expectedNames = @(
            'ecosystem.md'
            'plugins-and-formids.md'
            'diagnostics.md'
            'together-reborn.md'
            'anniversary-creations.md'
            'build-and-release.md'
            'research-ledger.md'
        )
    }

    It 'provides each routed reference with a current primary-source claim record' {
        foreach ($name in $expectedNames) {
            $path = Join-Path $referenceRoot $name
            $path | Should -Exist
            $text = Get-Content -Raw $path
            $text | Should -Match '2026-08-06'
            @('Claim', 'Source', 'Accessed', 'Applies to', 'Confidence', 'Reproduced') |
                ForEach-Object { $text | Should -Match ([regex]::Escape($_)) }
            $text | Should -Match 'https://'
        }
    }

    It 'catalogues exactly 74 licensed Anniversary creations without assets' {
        $catalogue = Get-Content -Raw (Join-Path $referenceRoot 'anniversary-creations.md')
        $entries = @($catalogue -split "`n" | Where-Object { $_ -match '^\|\s*\d+\s*\|' })
        $entries.Count | Should -Be 74
        $catalogue | Should -Match 'display name'
        $catalogue | Should -Match 'plugin identifier'
        $catalogue | Should -Not -Match '(?i)download\s+(?:the\s+)?(?:asset|BSA|plugin)'
    }

    It 'documents a discoverable inventory invocation and safe handling of catalogue extras' {
        $catalogue = Get-Content -Raw (Join-Path $referenceRoot 'anniversary-creations.md')
        @(
            'scripts/inventory-creations.ps1'
            '-DataPath'
            'unknown/out-of-scope'
            'no completeness claim'
            'never redistribute'
        ) | ForEach-Object { $catalogue | Should -Match ([regex]::Escape($_)) }
    }

    It 'works a light FormID decode and distinguishes runtime from persistent identity' {
        $formIds = Get-Content -Raw (Join-Path $referenceRoot 'plugins-and-formids.md')
        @(
            '0xFE123ABC'
            '0x123'
            '0xABC'
            '-shr 12'
            '-band 0xFFF'
            'master-relative'
            'not a portable identity'
        ) | ForEach-Object { $formIds | Should -Match ([regex]::Escape($_)) }
    }

    It 'executes the documented light FormID round trip in Windows PowerShell 5.1' {
        $formIds = Get-Content -Raw (Join-Path $referenceRoot 'plugins-and-formids.md')
        $match = [regex]::Match(
            $formIds,
            '(?s)### Worked light-plugin runtime example.*?```powershell\r?\n(?<script>.*?)\r?\n```'
        )
        $match.Success | Should -BeTrue

        $probePath = Join-Path $TestDrive 'documented-formid-roundtrip.ps1'
        $probe = $match.Groups['script'].Value + @'

if ($prefix -ne 0xFE -or $lightIndex -ne 0x123 -or $objectId -ne 0xABC -or $roundTrip -ne $runtimeId) {
    throw 'Documented light FormID decode or round trip failed.'
}
'@
        Set-Content -LiteralPath $probePath -Value $probe -Encoding UTF8

        & powershell.exe -NoLogo -NoProfile -NonInteractive -ExecutionPolicy Bypass -File $probePath
        $LASTEXITCODE | Should -Be 0
    }

    It 'makes Anniversary Together patching evidence led and integration first' {
        $together = Get-Content -Raw (Join-Path $referenceRoot 'together-reborn.md')
        @('upstream behavior', 'prior art', 'reproduce before patch', 'GPL-3.0') |
            ForEach-Object { $together | Should -Match ([regex]::Escape($_)) }
    }

    It 'records SkyrimCoop as pinned experimental prior art without recommending adoption' {
        $together = Get-Content -Raw (Join-Path $referenceRoot 'together-reborn.md')
        @(
            'blockheads/SkyrimCoop'
            '6a0c293a97892f83be0672c1ac4a9e0487a19503'
            'work in progress'
            'HostService.h'
            'code-delta audit'
            'no proven release or Anniversary validation'
        ) | ForEach-Object { $together | Should -Match ([regex]::Escape($_)) }
    }
}
