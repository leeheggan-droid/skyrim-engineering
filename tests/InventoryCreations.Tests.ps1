Describe 'inventory-creations' {
    BeforeAll {
        $script:inventoryPath = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\inventory-creations.ps1'
        $script:creationFixture = Join-Path $PSScriptRoot 'fixtures\creations\Data'
        $script:loadOrderFixture = Join-Path $PSScriptRoot 'fixtures\creations\loadorder.txt'
    }

    It 'emits a stable privacy-safe manifest with inspected-file metadata' {
        if (-not (Test-Path -LiteralPath $inventoryPath)) {
            $false | Should -BeTrue
            return
        }

        $first = & $inventoryPath -DataPath $creationFixture -LoadOrderPath $loadOrderFixture -Json
        $second = & $inventoryPath -DataPath $creationFixture -LoadOrderPath $loadOrderFixture -Json
        $manifest = $first | ConvertFrom-Json

        $manifest.schema | Should -Be 'skyrim-engineering.creations/v1'
        $first | Should -Be $second
        $first | Should -Not -Match ([regex]::Escape($creationFixture))
        @($manifest.files.name) | Should -Be @(
            'ccBGSSSE001-Fish.esm',
            'ccTEST-Archive.bsa',
            'ccTEST-Lite.esl',
            'ccTEST-Master.esm',
            'ccTEST-Plugin.esp')
        @($manifest.files.relativePath) | Should -Be @(
            'ccBGSSSE001-Fish.esm',
            'ccTEST-Archive.bsa',
            'ccTEST-Lite.esl',
            'ccTEST-Master.esm',
            'ccTEST-Plugin.esp')
        @($manifest.files.sha256 | Where-Object { $_ -cnotmatch '^[0-9a-f]{64}$' }) | Should -BeNullOrEmpty
        ($manifest.files | Where-Object { $_.name -eq 'ccTEST-Lite.esl' }).kind | Should -Be 'plugin'
        ($manifest.files | Where-Object { $_.name -eq 'ccTEST-Lite.esl' }).pluginType | Should -Be 'esl'
        ($manifest.files | Where-Object { $_.name -eq 'ccTEST-Lite.esl' }).internalFlag | Should -Be 'notInspected'
        ($manifest.files | Where-Object { $_.name -eq 'ccTEST-Archive.bsa' }).kind | Should -Be 'archive'
        ($manifest.files | Where-Object { $_.name -eq 'ccTEST-Archive.bsa' }).pluginType | Should -BeNullOrEmpty
        @($manifest.loadOrder) | Should -Be @('ccTEST-Master.esm', 'ccTEST-Lite.esl', 'ccTEST-Plugin.esp')
    }

    It 'excludes non-Creation files from the approved include set' {
        if (-not (Test-Path -LiteralPath $inventoryPath)) {
            $false | Should -BeTrue
            return
        }

        $manifest = (& $inventoryPath -DataPath $creationFixture -Json) | ConvertFrom-Json
        @($manifest.files.name) | Should -Not -Contain 'Skyrim.esm'
        @($manifest.files.name) | Should -Not -Contain 'not-a-creation.esp'
        @($manifest.files.name) | Should -Not -Contain 'ccTEST-Readme.txt'
    }
}
