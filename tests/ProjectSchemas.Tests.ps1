Describe 'Anniversary Together compatibility project contracts' {
    BeforeAll {
        $script:projectRoot = Join-Path $PSScriptRoot '..\projects\anniversary-together'
        $script:casesPath = Join-Path $projectRoot 'test-cases.yaml'
        $script:resultSchemaPath = Join-Path $projectRoot 'result.schema.json'
        $script:manifestSchemaPath = Join-Path $projectRoot 'manifest.schema.json'

        function Test-JsonSchemaDocument {
            param([string]$SchemaPath, [hashtable]$Document)
            $documentPath = Join-Path $TestDrive ((New-Guid).Guid + '.json')
            $Document | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $documentPath -Encoding utf8
            & python -c "import json,sys,jsonschema; jsonschema.validate(json.load(open(sys.argv[2], encoding='utf-8-sig')), json.load(open(sys.argv[1], encoding='utf-8-sig')))" $SchemaPath $documentPath 2>$null
            return $LASTEXITCODE -eq 0
        }

        function New-RepresentativeManifest {
            $hash = 'a' * 64
            $results = @('CONTROL-001', 'CONTROL-002', 'SYNC-001', 'SYNC-002', 'SYNC-003', 'SYNC-004', 'SYNC-005', 'SYNC-006', 'SYNC-007', 'AE-001', 'SYNC-008', 'SYNC-009', 'SYNC-010') |
                ForEach-Object { @{ testId = $_; path = "results/$_.json" } }
            return @{
                schema = 'skyrim-engineering.anniversary-together.manifest/v1'
                privateClientSlots = @('slot-1', 'slot-2', 'slot-3')
                canonicalCreationManifest = @{ path = 'manifests-private/canonical.json'; sha256 = $hash }
                participants = @(
                    @{ publicId = 'host'; role = 'host'; privateSlot = 'slot-1' },
                    @{ publicId = 'client-a'; role = 'client'; privateSlot = 'slot-2' },
                    @{ publicId = 'client-b'; role = 'client'; privateSlot = 'slot-3' }
                )
                parityReconciliation = @{
                    comparisonReports = @(
                        @{ participant = 'host'; path = 'manifests-private/host-comparison.json'; sha256 = $hash },
                        @{ participant = 'client-a'; path = 'manifests-private/client-a-comparison.json'; sha256 = $hash },
                        @{ participant = 'client-b'; path = 'manifests-private/client-b-comparison.json'; sha256 = $hash }
                    )
                    allMatched = $true
                    mismatchDisposition = 'ready'
                }
                publicationStatus = 'eligible-for-live-record'
                results = $results
            }
        }
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
        $clientEnum = @($resultSchema.properties.participants.items.enum)
        $statusEnum = @($resultSchema.properties.status.enum)

        $resultSchema.properties.schema.const | Should -Be 'skyrim-engineering.anniversary-together.result/v1'
        $clientEnum | Should -Be @('host', 'client-a', 'client-b')
        $statusEnum | Should -Be @('pass', 'partial', 'host-only', 'desync', 'crash', 'blocked', 'untested')
        $resultSchema.additionalProperties | Should -BeFalse
    }

    It 'defines a manifest that records anonymous slots and only result paths' {
        # Break caught: a manifest that can persist private identities or raw diagnostics.
        $manifestSchema = Get-Content -LiteralPath $manifestSchemaPath -Raw | ConvertFrom-Json

        $manifestSchema.properties.schema.const | Should -Be 'skyrim-engineering.anniversary-together.manifest/v1'
        @($manifestSchema.required) | Should -Contain 'privateClientSlots'
        $manifestSchema.properties.privateClientSlots.items.enum | Should -Be @('slot-1', 'slot-2', 'slot-3')
        $manifestSchema.properties.results.prefixItems[0].'$ref' | Should -Be '#/$defs/control001'
        $manifestSchema.additionalProperties | Should -BeFalse
    }

    It 'makes every case executable and separates control transitions from retained checkpoints' {
        # Break caught: prose-only cases whose actor, timing, capture command, or reset point is ambiguous.
        $caseText = Get-Content -LiteralPath $casesPath -Raw
        $caseCount = ([regex]::Matches($caseText, '(?m)^  - id: ')).Count
        foreach ($field in @('fixture:', 'actors:', 'actions:', 'timing:', 'capture:', 'transition:', 'cleanup:')) {
            ([regex]::Matches($caseText, '(?m)^    ' + [regex]::Escape($field))).Count | Should -Be $caseCount
        }
        $caseText | Should -Match 'CONTROL-001[\s\S]+transition: control-does-not-create-multiplayer-checkpoint'
        $caseText | Should -Match 'SYNC-010[\s\S]+transition: reload-from-test-save-not-clean-baseline'
        $caseText | Should -Match ([regex]::Escape('skill/skyrim-engineering/scripts/collect-diagnostics.ps1'))
    }

    It 'requires a three-participant version-pinned scientific result with hashed evidence' {
        # Break caught: a SYNC result that cannot establish who ran it, against which bytes, or what could falsify the diagnosis.
        $schema = Get-Content -LiteralPath $resultSchemaPath -Raw | ConvertFrom-Json
        foreach ($name in @('versions', 'participants', 'checkpoint', 'expected', 'actual', 'analysis', 'creationAttribution', 'evidence')) {
            @($schema.required) | Should -Contain $name
        }
        $schema.properties.participants.minItems | Should -Be 1
        $schema.properties.participants.maxItems | Should -Be 3
        @($schema.properties.participants.items.enum) | Should -Be @('host', 'client-a', 'client-b')
        $syncRule = @($schema.allOf)[0]
        $syncRule.if.properties.testId.pattern | Should -Be '^SYNC-'
        $syncRule.then.properties.participants.minItems | Should -Be 3
        foreach ($name in @('observation', 'hypothesis', 'confidence', 'tests', 'uncertainty', 'falsifyingCheck')) {
            @($schema.properties.analysis.required) | Should -Contain $name
        }
        $schema.properties.evidence.items.properties.sha256.pattern | Should -Be '^[a-f0-9]{64}$'
    }

    It 'requires one canonical manifest, explicit role-to-slot mapping, parity reconciliation, and every case exactly once' {
        # Break caught: cherry-picked case results or a client entering a run despite manifest mismatch.
        $schema = Get-Content -LiteralPath $manifestSchemaPath -Raw | ConvertFrom-Json
        foreach ($name in @('canonicalCreationManifest', 'participants', 'parityReconciliation', 'results')) {
            @($schema.required) | Should -Contain $name
        }
        $schema.properties.participants.minItems | Should -Be 3
        $schema.properties.participants.maxItems | Should -Be 3
        @($schema.properties.parityReconciliation.properties.mismatchDisposition.enum) | Should -Be @('ready', 'blocked-read-only')
        @($schema.properties.parityReconciliation.properties.comparisonReports.prefixItems).Count | Should -Be 3
        $schema.properties.results.minItems | Should -Be 13
        $schema.properties.results.maxItems | Should -Be 13
        @($schema.properties.results.prefixItems).Count | Should -Be 13
    }

    It 'documents canonical creation and fail-closed read-only parity reconciliation' {
        # Break caught: operators improvise a writable repair or silently choose a different canonical laptop.
        $decisions = Get-Content -LiteralPath (Join-Path $projectRoot 'decisions.md') -Raw
        $decisions | Should -Match 'Canonical manifest creation'
        $decisions | Should -Match 'inventory-creations\.ps1'
        $decisions | Should -Match 'compare-installations\.ps1'
        $decisions | Should -Match 'read-only'
        $decisions | Should -Match '(?s)mismatch.*blocked'
        $decisions | Should -Match 'provisional'
    }

    It 'validates a representative fixed host and two-client manifest' {
        $document = New-RepresentativeManifest
        Test-JsonSchemaDocument $manifestSchemaPath $document | Should -BeTrue
    }

    It 'fails closed when parity is mismatched but publication is eligible' {
        $document = New-RepresentativeManifest
        $document.parityReconciliation.allMatched = $false
        $document.parityReconciliation.mismatchDisposition = 'blocked-read-only'
        Test-JsonSchemaDocument $manifestSchemaPath $document | Should -BeFalse

        $document.publicationStatus = 'provisional-blocked'
        Test-JsonSchemaDocument $manifestSchemaPath $document | Should -BeTrue
    }

    It 'requires three participants for connection and Anniversary results' {
        $schema = Get-Content -LiteralPath $resultSchemaPath -Raw | ConvertFrom-Json
        @($schema.allOf).Count | Should -BeGreaterOrEqual 3
        ($schema.allOf | ConvertTo-Json -Depth 20) | Should -Match 'CONTROL-002'
        ($schema.allOf | ConvertTo-Json -Depth 20) | Should -Match 'AE-001'
    }

    It 'binds Creation attribution to canonical plugin identity' {
        $attribution = (Get-Content -LiteralPath $resultSchemaPath -Raw | ConvertFrom-Json).properties.creationAttribution.items
        foreach ($name in @('pluginFilename', 'sha256', 'pluginType', 'internalFlag')) {
            @($attribution.required) | Should -Contain $name
        }
    }

    It 'documents executable scripts, deterministic logs, fixture pins, and local saves' {
        $cases = Get-Content -LiteralPath $casesPath -Raw
        $decisions = Get-Content -LiteralPath (Join-Path $projectRoot 'decisions.md') -Raw
        $cases | Should -Match 'skill/skyrim-engineering/scripts/collect-diagnostics\.ps1 -InputPath'
        $cases | Should -Match 'fixture-pins\.json'
        $decisions | Should -Match 'JSON Lines'
        $decisions | Should -Match 'relativeSecond'
        $decisions | Should -Match 'each participant creates its own authorized local test save'
        $decisions | Should -Match 'never copy.*save'
    }
}
