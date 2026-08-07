[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$RunRoot,
    [Parameter(Mandatory)][string]$CreationKit,
    [Parameter(Mandatory)][string]$XDump64
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$resolvedRoot = [IO.Path]::GetFullPath($RunRoot)
if (Test-Path -LiteralPath $resolvedRoot) {
    if (@(Get-ChildItem -LiteralPath $resolvedRoot -Force).Count -gt 0) { throw 'RunRoot must be absent or empty.' }
} else {
    New-Item -ItemType Directory -Path $resolvedRoot | Out-Null
}
foreach ($tool in @($CreationKit, $XDump64)) {
    if (-not (Test-Path -LiteralPath $tool -PathType Leaf)) { throw 'A required reviewed tool is absent.' }
}

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
$plan | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $resolvedRoot 'ck-runbook.json') -Encoding UTF8
'RESULT=PREPARED'
