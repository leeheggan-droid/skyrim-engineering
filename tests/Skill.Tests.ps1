Describe 'Skyrim engineering skill' {
    BeforeAll {
        $skillPath = 'skill/skyrim-engineering/SKILL.md'
        $skill = Get-Content -Raw $skillPath
        $skillLines = Get-Content $skillPath
        $expectedReferences = @(
            'ecosystem.md'
            'plugins-and-formids.md'
            'diagnostics.md'
            'together-reborn.md'
            'anniversary-creations.md'
            'build-and-release.md'
            'research-ledger.md'
        )
    }

    It 'triggers and routes every core engineering surface' {
        @('Skyrim Together', 'Anniversary', 'FormID', 'Papyrus', 'crash', 'load order') |
            ForEach-Object { $skill | Should -Match ([regex]::Escape($_)) }

        $expectedReferences | ForEach-Object {
            $skill | Should -Match ([regex]::Escape("references/$_"))
        }
    }

    It 'keeps the entry workflow concise and integration first' {
        $skillLines.Count | Should -BeLessOrEqual 250
        @(
            'discover versions'
            'stock control'
            'isolated reproduction'
            'sanitize'
            'Observation'
            'Hypothesis'
            'upstream'
            'focused tests'
            'single-client'
            'multi-client'
            'legal'
            'reviewed knowledge'
        ) | ForEach-Object { $skill | Should -Match ([regex]::Escape($_)) }
    }

    It 'requires prior-art inspection and reproduction before an Anniversary Together patch' {
        $skill | Should -Match 'prior art'
        $skill | Should -Match 'reproduce before patch'
        $skill | Should -Match 'do not build a parallel replacement'
    }

    It 'routes Creation inventory work to its executable entry point' {
        $skill | Should -Match ([regex]::Escape('scripts/inventory-creations.ps1'))
        $skill | Should -Match ([regex]::Escape('references/anniversary-creations.md'))
    }
}
