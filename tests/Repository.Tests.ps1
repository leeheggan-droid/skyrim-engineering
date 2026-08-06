Describe 'Repository foundation' {
    It 'contains a discoverable skill and private-artifact ignores' {
        'skill/skyrim-engineering/SKILL.md' | Should -Exist
        'skill/skyrim-engineering/agents/openai.yaml' | Should -Exist
        $ignore = Get-Content -Raw '.gitignore'
        @('*.dmp','*.ess','*.skse','*.pex','diagnostics-private/','manifests-private/') |
            ForEach-Object { $ignore | Should -Match ([regex]::Escape($_)) }
    }
}
