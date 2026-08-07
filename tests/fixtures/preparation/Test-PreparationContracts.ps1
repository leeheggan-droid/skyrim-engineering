[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

$repoRoot = Split-Path -Parent (Split-Path -Parent (Split-Path -Parent $PSScriptRoot))
$papyrusRoot = Join-Path $repoRoot 'tests\fixtures\papyrus'
$xeditRoot = Join-Path $repoRoot 'tests\fixtures\xedit'
$stageScript = Join-Path $papyrusRoot 'Prepare-RuntimeMigration.ps1'
$captureScript = Join-Path $papyrusRoot 'Test-RuntimeCapture.ps1'
$xeditScript = Join-Path $xeditRoot 'Invoke-MinimalPatchRoundTrip.ps1'
$powershell = (Get-Process -Id $PID).Path
$testRoot = Join-Path 'C:\tmp' ("seg-preparation-contract-{0}" -f [guid]::NewGuid().ToString('N'))

function Assert-True {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERT: $Message" }
}

function Invoke-Child {
    param([string]$Script, [string[]]$Arguments)
    $previousErrorAction = $ErrorActionPreference
    try {
        $ErrorActionPreference = 'Continue'
        $output = & $powershell -NoProfile -ExecutionPolicy Bypass -File $Script @Arguments 2>&1
        [pscustomobject]@{ ExitCode = $LASTEXITCODE; Output = ($output -join [Environment]::NewLine) }
    }
    finally {
        $ErrorActionPreference = $previousErrorAction
    }
}

try {
    [IO.Directory]::CreateDirectory($testRoot) | Out-Null

    # Papyrus preparation: real staged bytes, two distinct versions, and a
    # machine-readable manifest whose hashes are independently recomputed.
    $buildV1 = Join-Path $testRoot 'build-v1'
    $buildV2 = Join-Path $testRoot 'build-v2'
    [IO.Directory]::CreateDirectory($buildV1) | Out-Null
    [IO.Directory]::CreateDirectory($buildV2) | Out-Null
    $v1Pex = Join-Path $buildV1 'SEG_RuntimeMigration.pex'
    $v2Pex = Join-Path $buildV2 'SEG_RuntimeMigration.pex'
    [IO.File]::WriteAllBytes($v1Pex, [byte[]](1, 3, 3, 7))
    [IO.File]::WriteAllBytes($v2Pex, [byte[]](2, 4, 6, 8, 10))
    $stagingRoot = Join-Path $testRoot 'runtime-stage'
    $result = Invoke-Child $stageScript @(
        '-V1Pex', $v1Pex,
        '-V2Pex', $v2Pex,
        '-StagingRoot', $stagingRoot
    )
    Assert-True ($result.ExitCode -eq 0) "Papyrus preparation failed: $($result.Output)"
    $manifestPath = Join-Path $stagingRoot 'runtime-migration-manifest.json'
    Assert-True (Test-Path -LiteralPath $manifestPath -PathType Leaf) 'preparation did not write its manifest'
    $manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
    Assert-True ($manifest.status -eq 'PREPARED') 'manifest status must remain PREPARED, not runtime PASS'
    Assert-True ($manifest.runtimeEvidenceCaptured -eq $false) 'preparation must not claim runtime evidence'
    Assert-True ($manifest.versions.V1.sha256 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $v1Pex).Hash) 'V1 hash is not bound to input bytes'
    Assert-True ($manifest.versions.V2.sha256 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $v2Pex).Hash) 'V2 hash is not bound to input bytes'
    Assert-True ($manifest.versions.V1.sha256 -ne $manifest.versions.V2.sha256) 'version PEX hashes must differ'
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stagingRoot $manifest.versions.V1.relativePath)).Hash -eq $manifest.versions.V1.sha256) 'staged V1 bytes differ from manifest'
    Assert-True ((Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $stagingRoot $manifest.versions.V2.relativePath)).Hash -eq $manifest.versions.V2.sha256) 'staged V2 bytes differ from manifest'

    $sameStage = Join-Path $testRoot 'same-version-stage'
    $result = Invoke-Child $stageScript @(
        '-V1Pex', $v1Pex,
        '-V2Pex', $v1Pex,
        '-StagingRoot', $sameStage
    )
    Assert-True ($result.ExitCode -ne 0) 'preparation accepted byte-identical V1/V2 PEX inputs'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $sameStage 'runtime-migration-manifest.json'))) 'failed preparation left an acceptance manifest'

    # Runtime capture: markers are phase-separated and the accepted record
    # contains independently verifiable pre/post save hashes.
    $v1Log = Join-Path $testRoot 'Papyrus-v1.log'
    $v2Log = Join-Path $testRoot 'Papyrus-v2.log'
    $saveBefore = Join-Path $testRoot 'save-before.ess'
    $saveAfter = Join-Path $testRoot 'save-after.ess'
    [IO.File]::WriteAllText($v1Log, "SEG_EVENT_OK schema=1`r`nSEG_MIGRATION_OLD schema=1`r`n")
    [IO.File]::WriteAllText($v2Log, "SEG_MIGRATION_NEW from=1 to=2`r`n")
    [IO.File]::WriteAllBytes($saveBefore, [byte[]](11, 12, 13))
    [IO.File]::WriteAllBytes($saveAfter, [byte[]](21, 22, 23, 24))
    $captureOutput = Join-Path $testRoot 'runtime-capture.json'
    $result = Invoke-Child $captureScript @(
        '-V1PapyrusLog', $v1Log,
        '-V2PapyrusLog', $v2Log,
        '-SaveBefore', $saveBefore,
        '-SaveAfter', $saveAfter,
        '-StageManifest', $manifestPath,
        '-CaptureOutput', $captureOutput
    )
    Assert-True ($result.ExitCode -eq 0) "runtime capture contract rejected valid inputs: $($result.Output)"
    $capture = Get-Content -Raw -LiteralPath $captureOutput | ConvertFrom-Json
    Assert-True ($capture.result -eq 'UNVERIFIED_SUBMISSION') 'synthetic capture must remain an unverified submission'
    Assert-True ($capture.markers.SEG_EVENT_OK -eq 'V1') 'event marker was not attributed to V1'
    Assert-True ($capture.markers.SEG_MIGRATION_OLD -eq 'V1') 'old marker was not attributed to V1'
    Assert-True ($capture.markers.SEG_MIGRATION_NEW -eq 'V2') 'new marker was not attributed to V2'
    Assert-True ($capture.saves.before.sha256 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $saveBefore).Hash) 'pre-save hash is wrong'
    Assert-True ($capture.saves.after.sha256 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath $saveAfter).Hash) 'post-save hash is wrong'

    [IO.File]::WriteAllText($v2Log, "SEG_EVENT_OK schema=1`r`n")
    $badCapture = Join-Path $testRoot 'bad-runtime-capture.json'
    $result = Invoke-Child $captureScript @(
        '-V1PapyrusLog', $v1Log,
        '-V2PapyrusLog', $v2Log,
        '-SaveBefore', $saveBefore,
        '-SaveAfter', $saveAfter,
        '-StageManifest', $manifestPath,
        '-CaptureOutput', $badCapture
    )
    Assert-True ($result.ExitCode -ne 0) 'capture accepted a V2 log without SEG_MIGRATION_NEW'
    Assert-True (-not (Test-Path -LiteralPath $badCapture)) 'failed capture left an acceptance record'

    # xEdit preparation: build a real plan around the pinned local tools and
    # reject a binary whose bytes do not match the reviewed tool contract.
    $dataRoot = Join-Path $testRoot 'xedit\Data'
    $iniRoot = Join-Path $testRoot 'xedit\Ini'
    $profileRoot = Join-Path $testRoot 'xedit\Profile'
    [IO.Directory]::CreateDirectory($dataRoot) | Out-Null
    [IO.Directory]::CreateDirectory($iniRoot) | Out-Null
    [IO.Directory]::CreateDirectory($profileRoot) | Out-Null
    [IO.File]::WriteAllBytes((Join-Path $dataRoot 'Skyrim.esm'), [byte[]](1))
    [IO.File]::WriteAllBytes((Join-Path $dataRoot 'SEG_CK_Practical3.esp'), [byte[]](2))
    $iniPath = Join-Path $iniRoot 'Skyrim.ini'
    $pluginList = Join-Path $profileRoot 'plugins.txt'
    [IO.File]::WriteAllText($iniPath, "[General]`r`n")
    [IO.File]::WriteAllText($pluginList, "*Skyrim.esm`r`n*SEG_CK_Practical3.esp`r`n")
    $planRoot = Join-Path $testRoot 'xedit-plan'
    $result = Invoke-Child $xeditScript @(
        '-XEdit64', 'C:\Tools\xEdit-4.1.5f\xTESEdit64.exe',
        '-XDump64', 'C:\Tools\xEdit-4.1.5f\xDump64.exe',
        '-DataPath', $dataRoot,
        '-IniPath', $iniPath,
        '-PluginListPath', $pluginList,
        '-RunRoot', $planRoot,
        '-PrepareOnly'
    )
    Assert-True ($result.ExitCode -eq 0) "xEdit plan preparation failed: $($result.Output)"
    $plan = Get-Content -Raw -LiteralPath (Join-Path $planRoot 'minimal-patch-plan.json') | ConvertFrom-Json
    Assert-True ($plan.status -eq 'PREPARED') 'xEdit plan must not claim executed evidence'
    Assert-True ($plan.schema -eq 'skyrim-engineering.qualification.xedit-preparation/v1') 'xEdit plan schema is missing or wrong'
    Assert-True ($plan.runtimeEvidenceCaptured -eq $false) 'xEdit preparation claimed execution'
    Assert-True ($plan.xeditTimeoutSeconds -eq 120) 'xEdit execution has no reviewed timeout boundary'
    Assert-True (@($plan.phases).Count -eq 4) 'xEdit plan must contain create, reopen, check, and dump phases'
    Assert-True ($plan.phases[0].name -eq 'create-save') 'first xEdit phase is not create-save'
    Assert-True (@($plan.phases[0].arguments) -contains '-autoload') 'create phase can open a module-selection dialog'
    Assert-True (@($plan.phases[0].arguments) -contains '-autoexit') 'create phase does not close deterministically'
    Assert-True ($plan.phases[1].name -eq 'reopen-verify') 'second xEdit phase is not reopen verification'
    Assert-True ($plan.phases[2].name -eq 'xdump-check') 'third phase is not xDump check'
    Assert-True ($plan.phases[3].name -eq 'xdump-dump') 'fourth phase is not xDump dump'
    Assert-True ($plan.protectedInputs.'Skyrim.esm'.sha256 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dataRoot 'Skyrim.esm')).Hash) 'plan does not bind Skyrim.esm bytes'
    Assert-True ($plan.protectedInputs.'SEG_CK_Practical3.esp'.sha256 -eq (Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $dataRoot 'SEG_CK_Practical3.esp')).Hash) 'plan does not bind source plugin bytes'
    Assert-True ($plan.review.required -eq $true -and $plan.review.reviewerId -eq $null) 'plan does not require a named reviewer'
    $xeditSource = Get-Content -Raw -LiteralPath $xeditScript
    Assert-True ($xeditSource -match 'UNVERIFIED_SUBMISSION') 'xEdit capture is not explicitly unverified'
    Assert-True ($xeditSource -notmatch "result\s*=\s*'CAPTURE_VERIFIED'") 'xEdit script can self-promote a capture'
    $xeditContract = Get-Content -Raw -LiteralPath (Join-Path $xeditRoot 'xedit-minimal-patch-contract.json') | ConvertFrom-Json
    Assert-True ($xeditContract.schema -eq 'skyrim-engineering.qualification.xedit-contract/v1') 'xEdit contract schema is missing or wrong'
    Assert-True ($xeditContract.captureResult -eq 'UNVERIFIED_SUBMISSION') 'xEdit contract permits automated promotion'
    Assert-True ($xeditContract.namedReviewRequired -eq $true) 'xEdit contract omits named review'
    Assert-True (@($xeditContract.requiredEvidence) -contains 'fresh-phase-timestamps') 'xEdit contract omits freshness evidence'

    $fakeXEdit = Join-Path $testRoot 'xTESEdit64.exe'
    [IO.File]::WriteAllBytes($fakeXEdit, [byte[]](9, 9, 9))
    $badPlanRoot = Join-Path $testRoot 'bad-xedit-plan'
    $result = Invoke-Child $xeditScript @(
        '-XEdit64', $fakeXEdit,
        '-XDump64', 'C:\Tools\xEdit-4.1.5f\xDump64.exe',
        '-DataPath', $dataRoot,
        '-IniPath', $iniPath,
        '-PluginListPath', $pluginList,
        '-RunRoot', $badPlanRoot,
        '-PrepareOnly'
    )
    Assert-True ($result.ExitCode -ne 0) 'xEdit preparation accepted an unreviewed binary'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $badPlanRoot 'minimal-patch-plan.json'))) 'failed xEdit preparation left an acceptance plan'

    $outsidePlanRoot = Join-Path $testRoot 'outside-input-plan'
    $result = Invoke-Child $xeditScript @(
        '-XEdit64', 'C:\Tools\xEdit-4.1.5f\xTESEdit64.exe',
        '-XDump64', 'C:\Tools\xEdit-4.1.5f\xDump64.exe',
        '-DataPath', $dataRoot,
        '-IniPath', 'C:\Windows\win.ini',
        '-PluginListPath', $pluginList,
        '-RunRoot', $outsidePlanRoot,
        '-PrepareOnly'
    )
    Assert-True ($result.ExitCode -ne 0) 'xEdit preparation accepted an INI outside the isolated temp boundary'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $outsidePlanRoot 'minimal-patch-plan.json'))) 'outside-boundary preparation left a plan'

    $overlapRoot = Join-Path $dataRoot 'run'
    $result = Invoke-Child $xeditScript @(
        '-XEdit64', 'C:\Tools\xEdit-4.1.5f\xTESEdit64.exe', '-XDump64', 'C:\Tools\xEdit-4.1.5f\xDump64.exe',
        '-DataPath', $dataRoot, '-IniPath', $iniPath, '-PluginListPath', $pluginList,
        '-RunRoot', $overlapRoot, '-PrepareOnly'
    )
    Assert-True ($result.ExitCode -ne 0) 'xEdit preparation accepted a run root overlapping protected Data'

    $reparseTarget = Join-Path $testRoot 'reparse-target'
    $reparseData = Join-Path $testRoot 'reparse-data'
    [IO.Directory]::CreateDirectory($reparseTarget) | Out-Null
    New-Item -ItemType Junction -Path $reparseData -Target $reparseTarget | Out-Null
    $result = Invoke-Child $xeditScript @(
        '-XEdit64', 'C:\Tools\xEdit-4.1.5f\xTESEdit64.exe', '-XDump64', 'C:\Tools\xEdit-4.1.5f\xDump64.exe',
        '-DataPath', $reparseData, '-IniPath', $iniPath, '-PluginListPath', $pluginList,
        '-RunRoot', (Join-Path $testRoot 'reparse-run'), '-PrepareOnly'
    )
    Assert-True ($result.ExitCode -ne 0) 'xEdit preparation accepted a reparse-point Data root'

    'RESULT=PASS preparation-contracts=3 fail-closed-probes=6'
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        $resolved = [IO.Path]::GetFullPath($testRoot)
        if (-not $resolved.StartsWith('C:\tmp\seg-preparation-contract-', [StringComparison]::OrdinalIgnoreCase)) {
            throw "refusing cleanup outside contract temp root: $resolved"
        }
        Remove-Item -LiteralPath $resolved -Recurse -Force
    }
}
