Describe 'Public repository safety' {
    BeforeAll {
        $script:trackedFiles = @(git ls-files)
        if ($LASTEXITCODE -ne 0) { throw 'Unable to enumerate tracked files.' }
    }

    It 'does not track prohibited game, diagnostic, credential, or executable files' {
        $prohibited = @('.bsa','.esm','.esp','.esl','.pex','.ess','.skse','.dmp','.exe','.dll','.pdb','.7z','.rar')
        @($script:trackedFiles | Where-Object { $prohibited -contains [IO.Path]::GetExtension($_).ToLowerInvariant() }) |
            Should -BeNullOrEmpty
    }

    It 'does not contain credentials, private keys, Steam IDs, or personal absolute paths' {
        $credentialPatterns = @(
            'AKIA[0-9A-Z]{16}',
            'gh[pousr]_[A-Za-z0-9]{30,}',
            'xox[baprs]-[A-Za-z0-9-]{20,}',
            ('-----BEGIN ' + '(?:RSA |EC |OPENSSH )?' + 'PRIVATE KEY-----'),
            '(?<!\d)7656119\d{10}(?!\d)'
        )
        $personalPathPatterns = @(
            '(?i)[A-Z]:\\Users\\[^\\\s]+',
            '(?im)(?:^|[\s"''(])/(?:Users|home)/[A-Za-z0-9._-]{2,64}(?:/|\\)'
        )
        $violations = foreach ($path in $script:trackedFiles) {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $PWD $path))
            if ($bytes -contains 0) { continue }
            $text = [Text.Encoding]::UTF8.GetString($bytes)
            foreach ($pattern in $credentialPatterns) {
                if ($text -match $pattern) { "$path matches $pattern" }
            }
            if ($path -notmatch '^tests/') {
                foreach ($pattern in $personalPathPatterns) {
                    if ($text -match $pattern) { "$path matches $pattern" }
                }
            }
        }
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
