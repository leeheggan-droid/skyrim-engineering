Describe 'Anniversary Together compatibility project contracts' {
    BeforeAll {
        $script:projectRoot = Join-Path $PSScriptRoot '..\projects\anniversary-together'
        $script:casesPath = Join-Path $projectRoot 'test-cases.yaml'
        $script:resultSchemaPath = Join-Path $projectRoot 'result.schema.json'
        $script:manifestSchemaPath = Join-Path $projectRoot 'manifest.schema.json'
    }

    It 'defines a complete unique anonymous compatibility matrix with retained evidence and cleanup' {
        # Break caught: a missing gameplay boundary or case that cannot be repeated and audited.
        $caseText = Get-Content -LiteralPath $casesPath -Raw
        $caseIds = @([regex]::Matches($caseText, '(?m)^  - id: (?<id>(?:CONTROL|SYNC|AE)-[0-9]{3})$') | ForEach-Object { $_.Groups['id'].Value })
        $expected = @(
            'CONTROL-001', 'CONTROL-002', 'SYNC-001', 'SYNC-002', 'SYNC-003', 'SYNC-004', 'SYNC-005',
            'SYNC-006', 'SYNC-007', 'AE-001', 'SYNC-008', 'SYNC-009', 'SYNC-010'
        )

        $caseIds | Should -Be $expected
        @($caseIds | Select-Object -Unique).Count | Should -Be $expected.Count
        @('preconditions:', 'steps:', 'expected:', 'evidence:', 'cleanup:', 'checkpoint:') |
            ForEach-Object { ([regex]::Matches($caseText, [regex]::Escape($_))).Count | Should -Be $expected.Count }
        $caseText | Should -Match '(?m)^privateClientSlots:$'
        $privateNamePattern = '(?i)\b(' + ('l' + 'ee') + '|' + ('ja' + 'cks') + '|' + ('heg' + 'gan') + ')\b'
        $caseText | Should -Not -Match $privateNamePattern
        $evidenceNames = @([regex]::Matches($caseText, '(?m)^    evidence: \[diagnostic-manifest\.json, (?<name>[^\]]+)\]$') | ForEach-Object { $_.Groups['name'].Value })
        $evidenceNames.Count | Should -Be $expected.Count
        $evidenceNames | ForEach-Object { ($_ -cmatch '^[a-z0-9-]+\.(log|json)$') | Should -BeTrue }
    }

    It 'permits only public anonymous client identifiers and supported result statuses' {
        # Break caught: a result that records a real identity or an untriageable status.
        $resultSchema = Get-Content -LiteralPath $resultSchemaPath -Raw | ConvertFrom-Json
        $clientEnum = @($resultSchema.'$defs'.publicClientId.enum)
        $statusEnum = @($resultSchema.properties.status.enum)

        $resultSchema.properties.schema.const | Should -Be 'skyrim-engineering.anniversary-together.result/v1'
        $clientEnum | Should -Be @('client-a', 'client-b', 'client-c')
        $statusEnum | Should -Be @('pass', 'partial', 'host-only', 'desync', 'crash', 'blocked', 'untested')
        $resultSchema.additionalProperties | Should -BeFalse
    }

    It 'defines a manifest that records anonymous slots and only result paths' {
        # Break caught: a manifest that can persist private identities or raw diagnostics.
        $manifestSchema = Get-Content -LiteralPath $manifestSchemaPath -Raw | ConvertFrom-Json

        $manifestSchema.properties.schema.const | Should -Be 'skyrim-engineering.anniversary-together.manifest/v1'
        @($manifestSchema.required) | Should -Contain 'privateClientSlots'
        $manifestSchema.properties.privateClientSlots.items.enum | Should -Be @('slot-1', 'slot-2', 'slot-3')
        $manifestSchema.properties.results.items.properties.path.pattern | Should -Be '^results/[A-Z]+-[0-9]{3}\.json$'
        $manifestSchema.additionalProperties | Should -BeFalse
    }
}
