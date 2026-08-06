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
