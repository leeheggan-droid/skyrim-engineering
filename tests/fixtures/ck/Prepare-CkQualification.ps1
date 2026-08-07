[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$CreationKit,
    [Parameter(Mandatory)][string]$XDump64
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Assert-SafeNewRunRoot([string]$Path) {
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw 'RunRoot must be fully qualified.' }
    $full = [IO.Path]::GetFullPath($Path)
    if (-not $full.Equals($Path, [StringComparison]::OrdinalIgnoreCase)) { throw 'RunRoot must already be canonical.' }
    $temp = [IO.Path]::GetFullPath('C:\tmp').TrimEnd('\')
    if (-not $full.StartsWith($temp + '\', [StringComparison]::OrdinalIgnoreCase)) { throw 'RunRoot must be a C:\tmp descendant.' }
    if (-not (Test-Path -LiteralPath $temp -PathType Container)) { throw 'C:\tmp is absent.' }
    if (((Get-Item -LiteralPath $temp -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'C:\tmp is a reparse point.' }
    if (Test-Path -LiteralPath $full) { throw 'RunRoot must not already exist.' }
    $cursor = Split-Path -Parent $full
    while ($cursor.StartsWith($temp + '\', [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $cursor) {
            if (((Get-Item -LiteralPath $cursor -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'RunRoot has a reparse-point ancestor.'
            }
        }
        $cursor = Split-Path -Parent $cursor
    }
    $full
}
$resolvedRoot = Assert-SafeNewRunRoot $RunRoot
foreach ($tool in @($CreationKit, $XDump64)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'A required reviewed tool is absent.' }
}
New-Item -ItemType Directory -Path $resolvedRoot | Out-Null

$plan = [ordered]@{
    schema = 'skyrim-engineering.qualification.creation-kit-preparation/v1'
    status = 'PREPARED'
    runtimeEvidenceCaptured = $false
    guiLaunchAuthorized = $false
    createdAtUtc = [DateTimeOffset]::UtcNow.ToString('o')
    runRoot = $resolvedRoot
    tools = [ordered]@{
        creationKitSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $CreationKit).Hash
        xDump64Sha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $XDump64).Hash
    }
    steps = @(
        'Automation: verify reviewed tool, seed, master, and INI hashes; compile original Papyrus only in this disposable root.',
        'Human: launch Creation Kit 1.6.1378.1 and select the exact masters and SEG_CK_Practical3.esp as active file.',
        'Human: configure the original quest alias, stage/objective, CTDA conditions, relationships, package procedure tree, and owned finalized navmesh.',
        'Human: save the active plugin and fully close Creation Kit.',
        'Human: fully close Creation Kit, reopen the active plugin, inspect, save, and close.',
        'Automation: run xDump check and dump, bind structured evidence and protected hashes, and emit only UNVERIFIED_SUBMISSION.',
        'Review: a named independent reviewer checks original-only provenance, warnings, relationships, ownership, and rollback.',
        'Cleanup: delete only this named disposable run root after sanitized evidence is retained.'
    )
}
$runbook = Join-Path $resolvedRoot 'ck-runbook.json'
$json = $plan | ConvertTo-Json -Depth 8
$createdRunbook = $false
try {
    $stream = [IO.File]::Open($runbook, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    $createdRunbook = $true
    try {
        $writer = [IO.StreamWriter]::new($stream, [Text.UTF8Encoding]::new($false))
        try { $writer.Write($json) } finally { $writer.Dispose() }
    } finally { if ($stream) { $stream.Dispose() } }
}
catch {
    if ($createdRunbook -and (Test-Path -LiteralPath $runbook)) { Remove-Item -LiteralPath $runbook -Force }
    throw
}
'RESULT=PREPARED'
