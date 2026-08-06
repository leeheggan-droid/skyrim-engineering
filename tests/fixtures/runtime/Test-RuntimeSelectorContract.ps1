[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$SkyrimExe,
    [Parameter(Mandatory)][string]$SkseRoot,
    [Parameter(Mandatory)][string]$AddressLibraryRoot,
    [Parameter(Mandatory)][ValidatePattern('^[A-Fa-f0-9]{64}$')][string]$ExpectedSkseSha256
)

$ErrorActionPreference = 'Stop'
$selector = Join-Path $PSScriptRoot 'Test-IsolatedRuntimeCompatibility.ps1'
$pwsh = (Get-Process -Id $PID).Path
$root = Join-Path 'C:\tmp' ('SEG-runtime-selector-contract-' + [guid]::NewGuid().ToString('N'))
$duplicateRoot = Join-Path $root 'duplicates'

function Invoke-Selector([string]$Profile, [string]$Root, [string]$Hash) {
    $output = & $pwsh -NoProfile -File $selector -SkyrimExe $SkyrimExe `
        -SkseRoot $Root -AddressLibraryRoot $AddressLibraryRoot `
        -IsolatedProfile $Profile -ExpectedSkseSha256 $Hash 2>&1
    [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join [Environment]::NewLine) }
}

try {
    $positive = Invoke-Selector (Join-Path $root 'positive') $SkseRoot $ExpectedSkseSha256
    if ($positive.ExitCode -ne 0 -or $positive.Output -notmatch 'ACCEPT runtime=') {
        throw "positive case failed: $($positive.Output)"
    }
    'ASSERT positive-exact-hash=ACCEPT'

    $mismatch = Invoke-Selector (Join-Path $root 'mismatch') $SkseRoot ('0' * 64)
    if ($mismatch.ExitCode -eq 0 -or $mismatch.Output -notmatch 'SKSE SHA256 mismatch') {
        throw "mismatch case did not reject: $($mismatch.Output)"
    }
    'ASSERT altered-same-version-hash=REJECT'

    $candidate = @(Get-ChildItem -LiteralPath $SkseRoot -Recurse -File -Filter 'skse64_1_6_1170.dll')
    if ($candidate.Count -ne 1) { throw "contract setup expected one source candidate; found $($candidate.Count)" }
    $null = New-Item -ItemType Directory -Force (Join-Path $duplicateRoot 'a'), (Join-Path $duplicateRoot 'b')
    Copy-Item -LiteralPath $candidate[0].FullName -Destination (Join-Path $duplicateRoot 'a\skse64_1_6_1170.dll')
    Copy-Item -LiteralPath $candidate[0].FullName -Destination (Join-Path $duplicateRoot 'b\skse64_1_6_1170.dll')
    $duplicate = Invoke-Selector (Join-Path $root 'duplicate') $duplicateRoot $ExpectedSkseSha256
    if ($duplicate.ExitCode -eq 0 -or $duplicate.Output -notmatch 'Expected exactly one SKSE runtime DLL') {
        throw "duplicate case did not reject: $($duplicate.Output)"
    }
    'ASSERT duplicate-candidates=REJECT'
    'RESULT=PASS cases=3'
}
finally {
    if (Test-Path -LiteralPath $root) { Remove-Item -LiteralPath $root -Recurse -Force }
}
