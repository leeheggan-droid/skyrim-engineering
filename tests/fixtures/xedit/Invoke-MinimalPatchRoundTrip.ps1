[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$XEdit64,
    [Parameter(Mandatory)][string]$XDump64,
    [Parameter(Mandatory)][string]$DataPath,
    [Parameter(Mandatory)][string]$IniPath,
    [Parameter(Mandatory)][string]$PluginListPath,
    [Parameter(Mandatory)][string]$RunRoot,
    [ValidateRange(10, 600)][int]$XEditTimeoutSeconds = 120,
    [switch]$PrepareOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$expectedXEditHash = '659FADDD8DC061A9D2EDDD20DE925821B87E377284CE179F4538FF78BB2420CD'
$expectedXDumpHash = '30C085B8A20DC02BF5ABAE2CB6610870C9BB9EEA50330E0FE5ADE98E3F89EFE6'
$expectedFileVersion = '4.1.5.0'

function Assert-NoReparseAncestor {
    param([string]$Path, [string]$Role)
    $cursor = [IO.Path]::GetFullPath($Path)
    while (-not (Test-Path -LiteralPath $cursor)) { $cursor = Split-Path -Parent $cursor }
    while ($cursor) {
        $item = Get-Item -LiteralPath $cursor -Force
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw "$Role traverses a reparse point: $cursor" }
        $parent = Split-Path -Parent $cursor
        if (-not $parent -or $parent -eq $cursor) { break }
        $cursor = $parent
    }
}

function Resolve-ExistingFile {
    param([string]$Path, [string]$Role)
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw "$Role must be fully qualified" }
    Assert-NoReparseAncestor $Path $Role
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Role does not exist: $Path" }
    (Resolve-Path -LiteralPath $Path).Path
}

function Resolve-ExistingDirectory {
    param([string]$Path, [string]$Role)
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw "$Role must be fully qualified" }
    Assert-NoReparseAncestor $Path $Role
    if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "$Role does not exist: $Path" }
    (Resolve-Path -LiteralPath $Path).Path.TrimEnd('\')
}

function Resolve-SafeTempDestination {
    param([string]$Path, [string]$Role)
    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    if (-not [IO.Path]::IsPathFullyQualified($Path)) { throw "$Role must be fully qualified" }
    if (-not $full.StartsWith('C:\tmp\', [StringComparison]::OrdinalIgnoreCase)) { throw "$Role must be a child of C:\tmp" }
    Assert-NoReparseAncestor $full $Role
    $full
}

function Assert-Hash {
    param([string]$Path, [string]$Expected, [string]$Role)
    $actual = (Get-FileHash -Algorithm SHA256 -LiteralPath $Path).Hash
    if ($actual -ne $Expected) { throw "$Role SHA-256 mismatch: expected $Expected, got $actual" }
}

function Assert-ToolVersion {
    param([string]$Path, [string]$Role)
    $actual = (Get-Item -LiteralPath $Path).VersionInfo.FileVersion
    if ($actual -ne $expectedFileVersion) { throw "$Role version mismatch: expected $expectedFileVersion, got $actual" }
}

function Test-PathOverlap {
    param([string]$Left, [string]$Right)
    $leftFull = [IO.Path]::GetFullPath($Left).TrimEnd('\')
    $rightFull = [IO.Path]::GetFullPath($Right).TrimEnd('\')
    return $leftFull.Equals($rightFull, [StringComparison]::OrdinalIgnoreCase) -or
        $leftFull.StartsWith($rightFull + '\', [StringComparison]::OrdinalIgnoreCase) -or
        $rightFull.StartsWith($leftFull + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Invoke-HiddenProcess {
    param([string]$Executable, [string[]]$Arguments, [string]$Role, [int]$TimeoutSeconds)
    $process = Start-Process -FilePath $Executable -ArgumentList ($Arguments -join ' ') -WindowStyle Hidden -PassThru
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        Stop-Process -Id $process.Id -Force -ErrorAction SilentlyContinue
        $process.WaitForExit()
        throw "$Role exceeded the $TimeoutSeconds second timeout and was terminated"
    }
    if ($process.ExitCode -ne 0) { throw "$Role exited $($process.ExitCode)" }
}

$xedit = Resolve-ExistingFile $XEdit64 'xEdit executable'
$xdump = Resolve-ExistingFile $XDump64 'xDump executable'
Assert-Hash $xedit $expectedXEditHash 'xEdit executable'
Assert-Hash $xdump $expectedXDumpHash 'xDump executable'
Assert-ToolVersion $xedit 'xEdit executable'
Assert-ToolVersion $xdump 'xDump executable'
$data = Resolve-ExistingDirectory $DataPath 'isolated Data root'
if (-not $data.StartsWith('C:\tmp\', [StringComparison]::OrdinalIgnoreCase)) { throw 'isolated Data root must be a child of C:\tmp' }
$ini = Resolve-ExistingFile $IniPath 'isolated Skyrim.ini'
$plugins = Resolve-ExistingFile $PluginListPath 'isolated plugin list'
if (-not $ini.StartsWith('C:\tmp\', [StringComparison]::OrdinalIgnoreCase)) { throw 'isolated Skyrim.ini must be a child of C:\tmp' }
if (-not $plugins.StartsWith('C:\tmp\', [StringComparison]::OrdinalIgnoreCase)) { throw 'isolated plugin list must be a child of C:\tmp' }
$run = Resolve-SafeTempDestination $RunRoot 'run root'
if (Test-Path -LiteralPath $run) { throw "run root already exists: $run" }
foreach ($protectedRoot in @($data, (Split-Path -Parent $ini), (Split-Path -Parent $plugins))) {
    if (Test-PathOverlap $run $protectedRoot) { throw 'run root must not overlap a protected input root' }
}

$skyrim = Resolve-ExistingFile (Join-Path $data 'Skyrim.esm') 'isolated Skyrim.esm'
$source = Resolve-ExistingFile (Join-Path $data 'SEG_CK_Practical3.esp') 'original fixture plugin'
$activePlugins = @(Get-Content -LiteralPath $plugins | ForEach-Object { $_.Trim() } | Where-Object { $_ -match '^\*' } | ForEach-Object { $_.Substring(1) })
if ($activePlugins.Count -ne 2 -or $activePlugins[0] -cne 'Skyrim.esm' -or $activePlugins[1] -cne 'SEG_CK_Practical3.esp') {
    throw 'plugin list must activate only Skyrim.esm then SEG_CK_Practical3.esp'
}

$sourceHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash
$skyrimHashBefore = (Get-FileHash -Algorithm SHA256 -LiteralPath $skyrim).Hash
$scripts = Join-Path $run 'Scripts'
$temp = Join-Path $run 'Temp'
$cache = Join-Path $run 'Cache'
$backups = Join-Path $run 'Backups'
$logs = Join-Path $run 'Logs'
$profile = Join-Path $run 'Profile'
[IO.Directory]::CreateDirectory($scripts) | Out-Null
[IO.Directory]::CreateDirectory($temp) | Out-Null
[IO.Directory]::CreateDirectory($cache) | Out-Null
[IO.Directory]::CreateDirectory($backups) | Out-Null
[IO.Directory]::CreateDirectory($logs) | Out-Null
[IO.Directory]::CreateDirectory($profile) | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'CreateMinimalPatch.pas') -Destination $scripts
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'VerifyMinimalPatch.pas') -Destination $scripts
$createPlugins = Join-Path $profile 'create-plugins.txt'
$reopenPlugins = Join-Path $profile 'reopen-plugins.txt'
Set-Content -LiteralPath $createPlugins -Encoding ASCII -Value @('*Skyrim.esm', '*SEG_CK_Practical3.esp')
Set-Content -LiteralPath $reopenPlugins -Encoding ASCII -Value @('*Skyrim.esm', '*SEG_CK_Practical3.esp', '*SEG_MinimalPatch.esp')

$dataArg = $data + '\'
$scriptsArg = $scripts + '\'
$tempArg = $temp + '\'
$cacheArg = $cache + '\'
$backupsArg = $backups + '\'
$createLog = Join-Path $logs 'create-save.log'
$reopenLog = Join-Path $logs 'reopen-verify.log'
$createArguments = @('-SSE', "-D:$dataArg", "-I:$ini", "-P:$createPlugins", "-S:$scriptsArg", "-T:$tempArg", "-C:$cacheArg", "-B:$backupsArg", "-R:$createLog", '-autoload', '-autoexit', '-script:CreateMinimalPatch.pas')
$reopenArguments = @('-SSE', "-D:$dataArg", "-I:$ini", "-P:$reopenPlugins", "-S:$scriptsArg", "-T:$tempArg", "-C:$cacheArg", "-B:$backupsArg", "-R:$reopenLog", '-autoload', '-autoexit', '-script:VerifyMinimalPatch.pas')
$patch = Join-Path $data 'SEG_MinimalPatch.esp'
$checkArguments = @('-SSE', "-D:$dataArg", '-check', $patch)
$dumpArguments = @('-SSE', "-D:$dataArg", '-dump', $patch)

$plan = [ordered]@{
    schema = 'skyrim-engineering.qualification.xedit-preparation/v1'
    contractVersion = 1
    status = 'PREPARED'
    runtimeEvidenceCaptured = $false
    xeditTimeoutSeconds = $XEditTimeoutSeconds
    tools = [ordered]@{
        xEdit = [ordered]@{ version = '4.1.5f'; sha256 = $expectedXEditHash }
        xDump = [ordered]@{ version = '4.1.5f'; sha256 = $expectedXDumpHash }
    }
    source = [ordered]@{ name = 'SEG_CK_Practical3.esp'; sha256 = $sourceHashBefore }
    protectedInputs = [ordered]@{
        'Skyrim.esm' = [ordered]@{ sha256 = $skyrimHashBefore }
        'SEG_CK_Practical3.esp' = [ordered]@{ sha256 = $sourceHashBefore }
    }
    target = [ordered]@{ name = 'SEG_MinimalPatch.esp'; editorId = 'SEG_ExpertiseItem'; full = 'SEG Expertise Token - Patched' }
    phases = @(
        [ordered]@{ name = 'create-save'; tool = 'xTESEdit64.exe'; arguments = $createArguments }
        [ordered]@{ name = 'reopen-verify'; tool = 'xTESEdit64.exe'; arguments = $reopenArguments }
        [ordered]@{ name = 'xdump-check'; tool = 'xDump64.exe'; arguments = $checkArguments }
        [ordered]@{ name = 'xdump-dump'; tool = 'xDump64.exe'; arguments = $dumpArguments }
    )
    requiredMarkers = @('SEG_PATCH_CREATE_OK', 'SEG_PATCH_REOPEN_OK')
    review = [ordered]@{ required = $true; reviewerId = $null; status = 'pending' }
    limitations = 'A plan is not execution evidence. Any automated capture remains UNVERIFIED_SUBMISSION pending a named human review.'
}
$planPath = Join-Path $run 'minimal-patch-plan.json'
$plan | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $planPath -Encoding UTF8
if ($PrepareOnly) {
    'RESULT=PASS status=PREPARED phases=4 runtime-evidence=false'
    exit 0
}

try {
    $captureStartedAtUtc = [DateTime]::UtcNow
    if (Test-Path -LiteralPath $patch) { throw 'refusing to overwrite existing SEG_MinimalPatch.esp' }
    Invoke-HiddenProcess $xedit $createArguments 'xEdit create-save phase' $XEditTimeoutSeconds
    if (-not (Test-Path -LiteralPath $patch -PathType Leaf)) { throw 'create-save phase produced no patch' }
    if (-not (Test-Path -LiteralPath $createLog -PathType Leaf) -or (Get-Content -Raw -LiteralPath $createLog) -notmatch 'SEG_PATCH_CREATE_OK') { throw 'create-save log lacks SEG_PATCH_CREATE_OK' }
    if ((Get-Item -LiteralPath $createLog).LastWriteTimeUtc -lt $captureStartedAtUtc.AddSeconds(-2)) { throw 'create-save log is stale' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne $sourceHashBefore) { throw 'create-save phase changed original fixture bytes' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $skyrim).Hash -ne $skyrimHashBefore) { throw 'create-save phase changed Skyrim.esm bytes' }
    $patchHashAfterCreate = (Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash
    $createCompletedAtUtc = [DateTime]::UtcNow

    Invoke-HiddenProcess $xedit $reopenArguments 'xEdit reopen-verify phase' $XEditTimeoutSeconds
    if (-not (Test-Path -LiteralPath $reopenLog -PathType Leaf) -or (Get-Content -Raw -LiteralPath $reopenLog) -notmatch 'SEG_PATCH_REOPEN_OK') { throw 'reopen log lacks SEG_PATCH_REOPEN_OK' }
    if ((Get-Item -LiteralPath $reopenLog).LastWriteTimeUtc -lt $createCompletedAtUtc.AddSeconds(-2)) { throw 'reopen log is stale' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash -ne $patchHashAfterCreate) { throw 'read-only reopen changed patch bytes' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne $sourceHashBefore) { throw 'reopen changed original fixture bytes' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $skyrim).Hash -ne $skyrimHashBefore) { throw 'reopen changed Skyrim.esm bytes' }
    $reopenCompletedAtUtc = [DateTime]::UtcNow

    $checkOutput = & $xdump @checkArguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "xDump check failed: $($checkOutput -join [Environment]::NewLine)" }
    $dumpOutput = & $xdump @dumpArguments 2>&1
    if ($LASTEXITCODE -ne 0) { throw "xDump dump failed: $($dumpOutput -join [Environment]::NewLine)" }
    $dumpText = $dumpOutput -join [Environment]::NewLine
    if ($dumpText -notmatch 'SEG_ExpertiseItem' -or $dumpText -notmatch [regex]::Escape('SEG Expertise Token - Patched')) { throw 'xDump does not show the reviewed original override' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $patch).Hash -ne $patchHashAfterCreate) { throw 'xDump verification changed patch bytes' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash -ne $sourceHashBefore) { throw 'xDump verification changed original fixture bytes' }
    if ((Get-FileHash -Algorithm SHA256 -LiteralPath $skyrim).Hash -ne $skyrimHashBefore) { throw 'xDump verification changed Skyrim.esm bytes' }
    $verificationCompletedAtUtc = [DateTime]::UtcNow

    $capture = [ordered]@{
        schema = 'skyrim-engineering.qualification.xedit/v1'
        contractVersion = 1
        result = 'UNVERIFIED_SUBMISSION'
        capturedAtUtc = [DateTime]::UtcNow.ToString('o')
        freshness = [ordered]@{ startedAtUtc = $captureStartedAtUtc.ToString('o'); completedAtUtc = [DateTime]::UtcNow.ToString('o') }
        tools = $plan.tools
        inputs = @(
            [ordered]@{ name = 'Skyrim.esm'; before = $skyrimHashBefore; after = (Get-FileHash -Algorithm SHA256 -LiteralPath $skyrim).Hash; equal = $true }
            [ordered]@{ name = 'SEG_CK_Practical3.esp'; before = $sourceHashBefore; after = (Get-FileHash -Algorithm SHA256 -LiteralPath $source).Hash; equal = $true }
        )
        patch = [ordered]@{ name = 'SEG_MinimalPatch.esp'; sha256 = $patchHashAfterCreate; editorId = 'SEG_ExpertiseItem'; winnerFull = 'SEG Expertise Token - Patched' }
        markers = @('SEG_PATCH_CREATE_OK', 'SEG_PATCH_REOPEN_OK')
        phases = @(
            [ordered]@{ name = 'create-save'; completedAtUtc = $createCompletedAtUtc.ToString('o'); logSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $createLog).Hash }
            [ordered]@{ name = 'reopen-verify'; completedAtUtc = $reopenCompletedAtUtc.ToString('o'); logSha256 = (Get-FileHash -Algorithm SHA256 -LiteralPath $reopenLog).Hash }
            [ordered]@{ name = 'xdump-check-and-dump'; completedAtUtc = $verificationCompletedAtUtc.ToString('o') }
        )
        xdump = [ordered]@{ checkExitCode = 0; dumpExitCode = 0 }
        review = [ordered]@{ required = $true; reviewerId = $null; status = 'pending' }
        limitations = 'This verifies an xEdit-created original fixture override and byte-stable reopen; it is not Creation Kit or game runtime evidence.'
    }
    $capture | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath (Join-Path $run 'minimal-patch-capture.json') -Encoding UTF8
    "RESULT=PASS contract=UNVERIFIED_SUBMISSION patch=$patchHashAfterCreate"
}
catch {
    $capturePath = Join-Path $run 'minimal-patch-capture.json'
    if (Test-Path -LiteralPath $capturePath) { Remove-Item -LiteralPath $capturePath -Force }
    throw
}
