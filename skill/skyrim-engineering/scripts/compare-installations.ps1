[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string[]]$ManifestPath,

    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PropertyValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Required property '$Name' is missing."
    }
    return $property.Value
}

function Read-CreationManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'Manifest file does not exist.'
    }

    try {
        $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'Manifest is not valid JSON.'
    }

    if ((Get-PropertyValue -InputObject $manifest -Name 'schema') -ne 'skyrim-engineering.creations/v1') {
        throw 'Manifest schema must be skyrim-engineering.creations/v1.'
    }

    $files = @(Get-PropertyValue -InputObject $manifest -Name 'files')
    $byPath = @{}
    foreach ($file in $files) {
        foreach ($propertyName in @('name', 'kind', 'size', 'sha256', 'pluginType', 'relativePath')) {
            [void](Get-PropertyValue -InputObject $file -Name $propertyName)
        }
        $relativePath = [string]$file.relativePath
        if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath) -or $relativePath.Contains('..')) {
            throw 'Manifest contains an unsafe relativePath.'
        }
        if ($file.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Manifest contains a non-lowercase SHA-256 value.'
        }
        $key = $relativePath.ToLowerInvariant()
        if ($byPath.ContainsKey($key)) {
            throw 'Manifest contains duplicate relativePath values.'
        }
        $byPath[$key] = $file
    }

    $loadOrder = @()
    if ($null -ne $manifest.PSObject.Properties['loadOrder']) {
        $loadOrder = @($manifest.loadOrder)
        foreach ($entry in $loadOrder) {
            if ([string]::IsNullOrWhiteSpace([string]$entry)) {
                throw 'Manifest contains an invalid loadOrder entry.'
            }
        }
    }

    return [pscustomobject]@{
        displayName = Split-Path -Path $Path -Leaf
        filesByPath = $byPath
        loadOrder = $loadOrder
    }
}

function New-DifferenceRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$Manifest
    )

    return [pscustomobject][ordered]@{
        manifest = $Manifest
        relativePath = $RelativePath
    }
}

try {
    if ($ManifestPath.Count -lt 1) {
        throw 'At least one manifest is required.'
    }

    $manifests = @($ManifestPath | ForEach-Object { Read-CreationManifest -Path $_ })
    $baseline = $manifests[0]
    $missing = New-Object System.Collections.ArrayList
    $extra = New-Object System.Collections.ArrayList
    $hashDifferent = New-Object System.Collections.ArrayList
    $sizeDifferent = New-Object System.Collections.ArrayList
    $orderDifferent = New-Object System.Collections.ArrayList

    foreach ($candidate in @($manifests | Select-Object -Skip 1)) {
        foreach ($key in @($baseline.filesByPath.Keys | Sort-Object)) {
            if (-not $candidate.filesByPath.ContainsKey($key)) {
                [void]$missing.Add((New-DifferenceRecord -Manifest $candidate.displayName -RelativePath $baseline.filesByPath[$key].relativePath))
            }
        }
        foreach ($key in @($candidate.filesByPath.Keys | Sort-Object)) {
            if (-not $baseline.filesByPath.ContainsKey($key)) {
                [void]$extra.Add((New-DifferenceRecord -Manifest $candidate.displayName -RelativePath $candidate.filesByPath[$key].relativePath))
            }
        }
        foreach ($key in @($baseline.filesByPath.Keys | Where-Object { $candidate.filesByPath.ContainsKey($_) } | Sort-Object)) {
            $expected = $baseline.filesByPath[$key]
            $actual = $candidate.filesByPath[$key]
            if ($expected.sha256 -cne $actual.sha256) {
                [void]$hashDifferent.Add((New-DifferenceRecord -Manifest $candidate.displayName -RelativePath $expected.relativePath))
            }
            if ([Int64]$expected.size -ne [Int64]$actual.size) {
                [void]$sizeDifferent.Add((New-DifferenceRecord -Manifest $candidate.displayName -RelativePath $expected.relativePath))
            }
        }

        $baselineOrder = @($baseline.loadOrder | Where-Object {
            $baseline.filesByPath.ContainsKey(([string]$_).ToLowerInvariant()) -and $candidate.filesByPath.ContainsKey(([string]$_).ToLowerInvariant())
        })
        $candidateOrder = @($candidate.loadOrder | Where-Object {
            $baseline.filesByPath.ContainsKey(([string]$_).ToLowerInvariant()) -and $candidate.filesByPath.ContainsKey(([string]$_).ToLowerInvariant())
        })
        $candidatePositions = @{}
        for ($index = 0; $index -lt $candidateOrder.Count; $index++) {
            $candidatePositions[([string]$candidateOrder[$index]).ToLowerInvariant()] = $index
        }
        for ($index = 0; $index -lt $baselineOrder.Count; $index++) {
            $key = ([string]$baselineOrder[$index]).ToLowerInvariant()
            if ($candidatePositions.ContainsKey($key) -and $candidatePositions[$key] -ne $index) {
                [void]$orderDifferent.Add((New-DifferenceRecord -Manifest $candidate.displayName -RelativePath $baselineOrder[$index]))
            }
        }
    }

    $comparison = [pscustomobject][ordered]@{
        schema = 'skyrim-engineering.comparison/v1'
        missing = @($missing)
        extra = @($extra)
        hashDifferent = @($hashDifferent)
        sizeDifferent = @($sizeDifferent)
        orderDifferent = @($orderDifferent)
    }

    if ($Json) {
        $comparison | ConvertTo-Json -Depth 5 -Compress
    }
    else {
        $comparison
    }

    $hasDifferences = $missing.Count -gt 0 -or $extra.Count -gt 0 -or $hashDifferent.Count -gt 0 -or $sizeDifferent.Count -gt 0 -or $orderDifferent.Count -gt 0
    if ($hasDifferences) {
        exit 2
    }
    exit 0
}
catch {
    [Console]::Error.WriteLine('Malformed creation manifest: {0}' -f $_.Exception.Message)
    exit 1
}
