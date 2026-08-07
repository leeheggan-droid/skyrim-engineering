Describe 'Skyrim engineering common module' {
    BeforeAll {
        $script:modulePath = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\SkyrimEngineering.Common.psm1'
        $script:steamFixture = Join-Path $TestDrive 'steam'
        $steamApps = Join-Path $steamFixture 'steamapps'
        New-Item -ItemType Directory -Path $steamApps -Force | Out-Null
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'fixtures\steam\steamapps\appmanifest_489830.acf.txt') `
            -Destination (Join-Path $steamApps 'appmanifest_489830.acf')
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

    It 'redacts cross-platform paths network identities and standalone bearer-shaped secrets' {
        Import-Module -Force $modulePath
        $linuxPath = '/ho' + 'me/alice/.config/skyrim/log.txt'
        $uncPath = '\\' + '\\workstation-07\Users\alice\Documents\crash.log'
        $genericWindowsPath = 'D:' + '\\Games\\Profiles\\alice\\session.log'
        $ipv6 = '2001:' + 'db8:85a3::8a2e:370:7334'
        $email = 'alice' + '@example.test'
        $privateHostname = 'private-host' + '.example.test'
        $jwt = @('eyJhbGciOiJIUzI1NiJ9', 'eyJzdWIiOiIxMjM0NTY3ODkwIn0', 'signature_material_123') -join '.'
        $input = "$linuxPath $uncPath $genericWindowsPath $ipv6 $email $privateHostname $jwt requestId=req-private-987"

        $protected = Protect-DiagnosticText -Text $input

        @($linuxPath, $uncPath, $genericWindowsPath, $ipv6, $email, $privateHostname, $jwt, 'req-private-987') |
            ForEach-Object { $protected | Should -Not -Match ([regex]::Escape($_)) }
        @('path', 'ipv6', 'email', 'hostname', 'token', 'identifier') |
            ForEach-Object { $protected | Should -Match ("\[REDACTED:{0}\]" -f $_) }
    }

    It 'redacts compressed IPv6 addresses including loopback' {
        Import-Module -Force $modulePath
        $input = 'peer=::1 fallback=fe80::1%12'
        $protected = Protect-DiagnosticText -Text $input

        $protected | Should -Not -Match '::1|fe80::1'
        $protected | Should -Match '\[REDACTED:ipv6\]'
    }

    It 'redacts complete quoted Windows and UNC paths containing spaces' {
        Import-Module -Force $modulePath
        $windowsPath = 'D:' + '\Private Folder\User Name\crash.log'
        $uncPath = '\\' + '\private-host\Private Share\User Name\crash.log'
        $protected = Protect-DiagnosticText -Text ('"{0}" "{1}"' -f $windowsPath, $uncPath)

        @($windowsPath, $uncPath, 'Private Folder', 'Private Share', 'User Name') |
            ForEach-Object { $protected | Should -Not -Match ([regex]::Escape($_)) }
        ([regex]::Matches($protected, '\[REDACTED:path\]')).Count | Should -Be 2
    }

    It 'redacts absolute Unix service and log paths' {
        Import-Module -Force $modulePath
        $rootPath = '/root/private/crash.log'
        $varPath = '/var/log/private/session.log'
        $protected = Protect-DiagnosticText -Text "$rootPath $varPath"

        @($rootPath, $varPath) | ForEach-Object { $protected | Should -Not -Match ([regex]::Escape($_)) }
        ([regex]::Matches($protected, '\[REDACTED:path\]')).Count | Should -Be 2
    }

    It 'redacts player and connection identifiers' {
        Import-Module -Force $modulePath
        $protected = Protect-DiagnosticText -Text 'playerId=synthetic-player-987 connection_id=synthetic-connection-987'

        $protected | Should -Not -Match 'synthetic-player-987|synthetic-connection-987'
        ([regex]::Matches($protected, '\[REDACTED:identifier\]')).Count | Should -Be 2
    }

    It 'redacts secrets in URL query parameters' {
        Import-Module -Force $modulePath
        $protected = Protect-DiagnosticText -Text 'callback?access_token=synthetic-access-987&refresh_token=synthetic-refresh-987&api_key=synthetic-api-987'

        $protected | Should -Not -Match 'synthetic-access-987|synthetic-refresh-987|synthetic-api-987'
        ([regex]::Matches($protected, '\[REDACTED:token\]')).Count | Should -Be 3
    }
}
