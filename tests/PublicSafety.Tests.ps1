Describe 'Public repository safety' {
    BeforeAll {
        function Find-PublicSafetyTextViolations {
            param([string[]]$Files)
            $credentialPatterns = @(
                'AKIA[0-9A-Z]{16}',
                'gh[pousr]_[A-Za-z0-9]{30,}',
                ('github' + '_pat_[A-Za-z0-9_]{20,}'),
                'xox[baprs]-[A-Za-z0-9-]{20,}',
                ('-----BEGIN ' + '(?:RSA |EC |OPENSSH )?' + 'PRIVATE KEY-----'),
                '(?<!\d)7656119\d{10}(?!\d)'
            )
            $personalPathPatterns = @(
                '(?i)[A-Z]:[\\/]Users[\\/][^\\/\s]+',
                '(?im)(?:^|[\s"''(])/(?:Users|home)/[A-Za-z0-9._-]{2,64}(?:/|\\)'
            )
            foreach ($path in $Files) {
                $resolvedPath = if ([IO.Path]::IsPathFullyQualified($path)) { $path } else { Join-Path $PWD $path }
                $text = [Text.Encoding]::UTF8.GetString([IO.File]::ReadAllBytes($resolvedPath))
                foreach ($pattern in @($credentialPatterns + $personalPathPatterns)) {
                    if ($text -match $pattern) { "$path matches $pattern" }
                }
            }
        }
        $script:trackedFiles = @(git ls-files)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate tracked files.' }
    }

    It 'does not track prohibited game, diagnostic, credential, or executable files' {
        $prohibited = @('.bsa','.esm','.esp','.esl','.pex','.ess','.skse','.dmp','.exe','.dll','.pdb','.7z','.rar','.zip')
        @($script:trackedFiles | Where-Object { $prohibited -contains [IO.Path]::GetExtension($_).ToLowerInvariant() }) |
            Should -BeNullOrEmpty
    }

    It 'keeps archive, binary, test-path, and fine-grained-token checks fail closed' {
        $source = Get-Content -Raw -LiteralPath $PSCommandPath
        $zipLiteral = "'" + '.zip' + "'"
        $source | Should -Match ([regex]::Escape($zipLiteral))
        $source | Should -Not -Match '\$bytes\s+-contains\s+0\)\s*\{\s*continue'
        $source | Should -Not -Match "\$path\s+-notmatch\s+'\^tests/'"

        $probe = Join-Path $TestDrive 'probe.txt'
        $fineToken = 'github' + '_pat_' + ('A' * 24)
        $personalPath = 'C:' + '/Users/' + 'PrivateOwner' + '/secret.txt'
        [IO.File]::WriteAllBytes($probe, [byte[]](0,1,2) + [Text.Encoding]::UTF8.GetBytes("$fineToken $personalPath"))
        @(Find-PublicSafetyTextViolations -Files @($probe)).Count | Should -Be 2
    }

    It 'does not contain credentials, private keys, Steam IDs, or personal absolute paths' {
        $violations = Find-PublicSafetyTextViolations -Files $script:trackedFiles
        @($violations) | Should -BeNullOrEmpty
    }

    It 'does not publish private client addresses in result records' {
        $resultFiles = @($script:trackedFiles | Where-Object { $_ -match '^projects/.+/results/.+\.json$' })
        $violations = foreach ($path in $resultFiles) {
            $text = Get-Content -Raw -LiteralPath $path
            if ($text -match '(?<!\d)(?:10\.|127\.|169\.254\.|192\.168\.|172\.(?:1[6-9]|2\d|3[01])\.)\d{1,3}(?:\.\d{1,3}){2}(?!\d)') {
                $path
            }
        }
        @($violations) | Should -BeNullOrEmpty
    }
}
