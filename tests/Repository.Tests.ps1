Describe 'Repository foundation' {
    It 'contains a discoverable skill and private-artifact ignores' {
        'skill/skyrim-engineering/SKILL.md' | Should -Exist
        'skill/skyrim-engineering/agents/openai.yaml' | Should -Exist
        $ignore = Get-Content -Raw '.gitignore'
        @('*.dmp','*.ess','*.skse','*.pex','diagnostics-private/','manifests-private/') |
            ForEach-Object { $ignore | Should -Match ([regex]::Escape($_)) }
    }

    It 'defines a least-privilege Windows validation workflow' {
        '.github/workflows/validate.yml' | Should -Exist
        $workflow = Get-Content -Raw '.github/workflows/validate.yml'
        $workflow | Should -Match 'windows-2022'
        $workflow | Should -Match '(?ms)^permissions:\s*\r?\n\s+contents:\s*read\s*$'
        $workflow | Should -Match 'Pester.*5\.9\.0|RequiredVersion\s+5\.9\.0'
    }
}
