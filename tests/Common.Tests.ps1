Describe 'Skyrim engineering common module' {
    BeforeAll {
        $script:modulePath = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\SkyrimEngineering.Common.psm1'
        $script:steamFixture = Join-Path $PSScriptRoot 'fixtures\steam'
        $script:gameFixture = Join-Path $PSScriptRoot 'fixtures\game'
    }

    It 'provides the common module' {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $false | Should -BeTrue
            return
        }

        Import-Module -Force $modulePath
        Get-Command Resolve-SkyrimInstall | Should -Not -BeNullOrEmpty
    }

    It 'resolves an explicit Steam root from its Skyrim manifest' {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $false | Should -BeTrue
            return
        }

        Import-Module -Force $modulePath
        $installation = Resolve-SkyrimInstall -SteamRoot $steamFixture

        $installation | Should -BeOfType System.IO.DirectoryInfo
        $installation.FullName | Should -Be (Join-Path $steamFixture 'steamapps\common\Skyrim Special Edition')
    }

    It 'fails with an actionable error when the Skyrim manifest is absent' {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $false | Should -BeTrue
            return
        }

        Import-Module -Force $modulePath
        { Resolve-SkyrimInstall -SteamRoot (Join-Path $PSScriptRoot 'fixtures\missing-steam') } |
            Should -Throw '*appmanifest_489830.acf*'
    }

    It 'returns a lowercase stable SHA-256 digest' {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $false | Should -BeTrue
            return
        }

        $temporaryFile = New-TemporaryFile
        try {
            $utf8WithoutBom = New-Object System.Text.UTF8Encoding($false)
            [System.IO.File]::WriteAllText($temporaryFile.FullName, 'Skyrim Engineering', $utf8WithoutBom)
            Import-Module -Force $modulePath
            Get-StableSha256 -Path $temporaryFile.FullName |
                Should -Be '07e8d83a3fcf074d7e21261607e4c29b4f4eed1acefa0b064d6567eafd16e9d5'
        }
        finally {
            Remove-Item -LiteralPath $temporaryFile.FullName -Force -ErrorAction SilentlyContinue
        }
    }

    It 'normalizes paths below the supplied root and rejects paths outside it' {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $false | Should -BeTrue
            return
        }

        Import-Module -Force $modulePath
        Get-RelativeSafePath -Root $gameFixture -Path (Join-Path $gameFixture 'Data\plugins.txt') |
            Should -Be 'Data/plugins.txt'
        { Get-RelativeSafePath -Root $gameFixture -Path (Join-Path $PSScriptRoot 'Common.Tests.ps1') } |
            Should -Throw '*outside*'
    }

    It 'redacts usernames, Steam IDs, IPv4 addresses, tokens, and passwords' {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $false | Should -BeTrue
            return
        }

        Import-Module -Force $modulePath
        $usernamePath = ('C:' + '\Users\' + 'TestUser\Documents')
        $steamId = ('7656119' + '8012345678')
        $ipAddress = ('192.168' + '.10.25')
        $input = "$usernamePath $steamId $ipAddress token=abc123secret password=hunter2"
        $protected = Protect-DiagnosticText -Text $input

        $protected | Should -Not -Match 'TestUser|abc123secret|hunter2'
        $protected | Should -Not -Match ([regex]::Escape($steamId))
        $protected | Should -Not -Match ([regex]::Escape($ipAddress))
        @('username', 'steam-id', 'ipv4', 'token', 'password') |
            ForEach-Object { $protected | Should -Match ("\[REDACTED:{0}\]" -f $_) }
    }

    It 'redacts colon-delimited, quoted, and Basic authorization credentials' {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $false | Should -BeTrue
            return
        }

        Import-Module -Force $modulePath
        $passwordSecret = ('moon' + 'light phrase')
        $tokenSecret = ('token' + 'Value')
        $apiKeySecret = ('api' + 'Key with spaces')
        $basicCredential = ('QmFzaWM' + '6Y3JlZGVudGlhbA==')
        $input = @(
            "password: `"$passwordSecret`""
            "token: $tokenSecret"
            "apikey: `"$apiKeySecret`""
            "Authorization: Basic $basicCredential"
        ) -join "`n"

        $protected = Protect-DiagnosticText -Text $input

        @($passwordSecret, $tokenSecret, $apiKeySecret, $basicCredential) |
            ForEach-Object { $protected | Should -Not -Match ([regex]::Escape($_)) }
        $protected | Should -Match '\[REDACTED:password\]'
        $protected | Should -Match '\[REDACTED:token\]'
    }

    It 'redacts case-insensitive spaced API key labels' {
        if (-not (Test-Path -LiteralPath $modulePath)) {
            $false | Should -BeTrue
            return
        }

        Import-Module -Force $modulePath
        $apiKeySecret = ('exposed' + '-spaced-form')
        $protected = Protect-DiagnosticText -Text ("API   Key : $apiKeySecret")

        $protected | Should -Not -Match ([regex]::Escape($apiKeySecret))
        $protected | Should -Match '\[REDACTED:token\]'
    }
}
