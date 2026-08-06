Set-StrictMode -Version Latest

function Get-SteamRootFromRegistry {
    [CmdletBinding()]
    param()

    $registryPaths = @(
        'HKCU:\Software\Valve\Steam',
        'HKLM:\SOFTWARE\WOW6432Node\Valve\Steam',
        'HKLM:\SOFTWARE\Valve\Steam'
    )

    foreach ($registryPath in $registryPaths) {
        $entry = Get-ItemProperty -Path $registryPath -ErrorAction SilentlyContinue
        if ($null -eq $entry) {
            continue
        }

        foreach ($propertyName in @('SteamPath', 'InstallPath')) {
            $value = $entry.$propertyName
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                return [string]$value
            }
        }
    }

    return $null
}

function Resolve-SkyrimInstall {
    [CmdletBinding()]
    param(
        [string]$SteamRoot
    )

    if ([string]::IsNullOrWhiteSpace($SteamRoot)) {
        $SteamRoot = Get-SteamRootFromRegistry
    }

    if ([string]::IsNullOrWhiteSpace($SteamRoot)) {
        throw 'Unable to locate Steam. Supply -SteamRoot with your Steam installation directory.'
    }

    $steamRootFull = [System.IO.Path]::GetFullPath($SteamRoot)
    $manifestPath = Join-Path $steamRootFull 'steamapps\appmanifest_489830.acf'
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) {
        throw "Skyrim Steam manifest appmanifest_489830.acf was not found under the supplied Steam root."
    }

    $manifestText = Get-Content -LiteralPath $manifestPath -Raw -ErrorAction Stop
    $match = [regex]::Match($manifestText, '(?m)^\s*"installdir"\s*"(?<directory>[^"]+)"')
    if (-not $match.Success) {
        throw 'Skyrim Steam manifest appmanifest_489830.acf does not contain an installdir value.'
    }

    $installDirectory = $match.Groups['directory'].Value
    if ([System.IO.Path]::GetFileName($installDirectory) -ne $installDirectory) {
        throw 'Skyrim Steam manifest contains an unsafe installdir value.'
    }

    $commonRoot = [System.IO.Path]::GetFullPath((Join-Path $steamRootFull 'steamapps\common'))
    $installPath = [System.IO.Path]::GetFullPath((Join-Path $commonRoot $installDirectory))
    $commonPrefix = $commonRoot.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar) + [System.IO.Path]::DirectorySeparatorChar
    if (-not $installPath.StartsWith($commonPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'Skyrim Steam manifest resolves outside Steam common directory.'
    }

    return New-Object System.IO.DirectoryInfo($installPath)
}

function Get-RelativeSafePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Root,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $pathFull = [System.IO.Path]::GetFullPath($Path)
    $trimmedRoot = $rootFull.TrimEnd([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)
    $rootPrefix = $trimmedRoot + [System.IO.Path]::DirectorySeparatorChar

    if ($pathFull.Equals($trimmedRoot, [System.StringComparison]::OrdinalIgnoreCase)) {
        return '.'
    }

    if (-not $pathFull.StartsWith($rootPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
        throw 'The supplied path is outside the permitted root.'
    }

    return $pathFull.Substring($rootPrefix.Length).Replace('\', '/')
}

function Get-StableSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "Cannot hash missing file: $Path"
    }

    $stream = $null
    $sha256 = $null
    try {
        $stream = [System.IO.File]::OpenRead($Path)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        $bytes = $sha256.ComputeHash($stream)
        return ([System.BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($null -ne $sha256) {
            $sha256.Dispose()
        }
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Protect-DiagnosticText {
    [CmdletBinding()]
    param(
        [AllowEmptyString()]
        [string]$Text
    )

    $protected = $Text
    $protected = [regex]::Replace($protected, '(?i)[A-Z]:[\\/]+Users[\\/]+[^\\/\s]+', '[REDACTED:username]')
    $protected = [regex]::Replace($protected, '(?i)/Users/[^/\s]+', '[REDACTED:username]')
    $protected = [regex]::Replace($protected, '(?im)\b(username|user)\b(\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|[^\s;]+)', '$1$2[REDACTED:username]')
    $protected = [regex]::Replace($protected, '(?<!\d)7656119\d{10}(?!\d)', '[REDACTED:steam-id]')
    $protected = [regex]::Replace($protected, '(?<![\d.])(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)(?:\.(?:25[0-5]|2[0-4]\d|1\d\d|[1-9]?\d)){3}(?![\d.])', '[REDACTED:ipv4]')
    $protected = [regex]::Replace($protected, '(?im)\bauthorization\b(\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|[^\r\n;]+)', 'Authorization$1[REDACTED:token]')
    $protected = [regex]::Replace($protected, '(?im)\b(password|passwd|pwd)\b(\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|[^\s;]+)', '$1$2[REDACTED:password]')
    $protected = [regex]::Replace($protected, '(?im)\b(token|api[\s_-]*key)\b(\s*[:=]\s*)(?:"[^"]*"|''[^'']*''|[^\s;]+)', '$1$2[REDACTED:token]')
    $protected = [regex]::Replace($protected, '(?im)\b(?:Bearer|Basic|Digest|Negotiate)\s+(?:"[^"]*"|''[^'']*''|[A-Za-z0-9._~+/=-]+)', '[REDACTED:token]')
    return $protected
}

Export-ModuleMember -Function Resolve-SkyrimInstall, Get-RelativeSafePath, Get-StableSha256, Protect-DiagnosticText
