[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$cases = Get-Content -Raw (Join-Path $PSScriptRoot 'cases.json') | ConvertFrom-Json

function Parse-Hex([string] $Value) {
    [Convert]::ToUInt32($Value.Substring(2), 16)
}

function Assert-Equal($Actual, $Expected, [string] $Name) {
    if ($Actual -ne $Expected) {
        throw "$Name expected=$Expected actual=$Actual"
    }
    Write-Output "ASSERT $Name=$Actual"
}

try {
    $standard = Parse-Hex $cases.standard.runtimeFormId
    Assert-Equal (($standard -shr 24) -band 0xFF) (Parse-Hex $cases.standard.loadIndex) 'standard.load-index'
    Assert-Equal ($standard -band 0xFFFFFF) (Parse-Hex $cases.standard.objectId) 'standard.object-id'
    Assert-Equal (Parse-Hex $cases.standard.loadIndexMaximum) 0xFD 'standard.load-index-maximum'
    Assert-Equal (Parse-Hex $cases.standard.objectIdMaximum) 0xFFFFFF 'standard.object-id-maximum'

    $light = Parse-Hex $cases.light.runtimeFormId
    Assert-Equal (($light -shr 24) -band 0xFF) 0xFE 'light.prefix'
    Assert-Equal (($light -shr 12) -band 0xFFF) (Parse-Hex $cases.light.lightIndex) 'light.index'
    Assert-Equal ($light -band 0xFFF) (Parse-Hex $cases.light.objectId) 'light.object-id'
    Assert-Equal (Parse-Hex $cases.light.lightIndexMaximum) 0xFFF 'light.index-maximum'
    Assert-Equal (Parse-Hex $cases.light.objectIdMaximum) 0xFFF 'light.object-id-maximum'

    $disk = Parse-Hex $cases.masterRelative.onDiskFormId
    $resolved = ((Parse-Hex $cases.masterRelative.sourceMasterRuntimeIndex) -shl 24) -bor ($disk -band 0xFFFFFF)
    Assert-Equal (($disk -shr 24) -band 0xFF) $cases.masterRelative.sourceMasterIndex 'master.source-index'
    Assert-Equal $resolved (Parse-Hex $cases.masterRelative.resolvedRuntimeFormId) 'master.runtime-form-id'
    Assert-Equal $cases.masterRelative.missingMasterResult 'loader-reject-unresolved' 'master.missing-result'

    $chain = @($cases.overrideChain.orderedPlugins)
    Assert-Equal $chain.Count 3 'override.count'
    Assert-Equal $chain[-1].role 'winning-override' 'override.winner-role'
    Assert-Equal $chain[-1].value $cases.overrideChain.desiredCombinedOutcome.value 'winner.value-contribution'
    Assert-Equal $chain[-1].survivalCompatible $false 'winner.misses-desired-survival-field'
    Assert-Equal $cases.overrideChain.minimalPatch.value $cases.overrideChain.desiredCombinedOutcome.value 'patch.value'
    Assert-Equal $cases.overrideChain.minimalPatch.survivalCompatible $cases.overrideChain.desiredCombinedOutcome.survivalCompatible 'patch.combined-field'
    Assert-Equal $cases.overrideChain.minimalPatch.newRecords 0 'patch.new-records'
    Assert-Equal @($cases.overrideChain.minimalPatch.requiredMasters).Count 1 'patch.master-count'
    Assert-Equal $cases.overrideChain.minimalPatch.requiredMasters[0] 'Base.esp' 'patch.only-required-master'
    Assert-Equal $cases.overrideChain.reopen.winner 'CompatibilityPatch.esp' 'patch.reopen-winner'
    Assert-Equal $cases.overrideChain.reopen.errors 0 'patch.reopen-errors'
    Assert-Equal @($cases.overrideChain.reopen.tes4Masters).Count 1 'patch.reopen-master-count'

    Assert-Equal $cases.overrideChain.compaction.existingOverrideAction 'unchanged' 'compaction.existing-override'
    Assert-Equal (Parse-Hex $cases.overrideChain.compaction.newLocalCompactedFormId) 0x800 'compaction.new-local-lower-bound'
    Assert-Equal ((Parse-Hex $cases.overrideChain.compaction.dependentBefore) -band 0xFFFFFF) 0x1234 'compaction.dependent-before-local'
    Assert-Equal ((Parse-Hex $cases.overrideChain.compaction.dependentAfter) -band 0xFFFFFF) 0x800 'compaction.dependent-after-local'
    Assert-Equal $cases.overrideChain.compaction.allDependentsMigratedTogether $true 'compaction.dependents-migrated'

    'RESULT=PASS data-model-cases=4'
    exit 0
}
catch {
    "RESULT=FAIL $($_.Exception.Message)"
    exit 1
}
