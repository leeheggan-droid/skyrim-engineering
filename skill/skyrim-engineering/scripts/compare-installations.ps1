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
    # Preserve array-valued JSON properties when PowerShell captures function
    # output; otherwise a single-entry JSON array is silently unwrapped.
    return ,$property.Value
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

    $filesValue = Get-PropertyValue -InputObject $manifest -Name 'files'
    if ($null -eq $filesValue -or -not ($filesValue -is [System.Collections.IEnumerable]) -or $filesValue -is [string]) {
        throw 'Manifest files must be an array.'
    }

    $files = @($filesValue)
    $byPath = @{}
    $pluginsByName = @{}
    foreach ($file in $files) {
        foreach ($propertyName in @('name', 'kind', 'size', 'sha256', 'pluginType', 'internalFlag', 'relativePath')) {
            [void](Get-PropertyValue -InputObject $file -Name $propertyName)
        }

        if ($file.name -isnot [string] -or [string]::IsNullOrWhiteSpace($file.name) -or $file.name -match '[\\/]') {
            throw 'Manifest contains an invalid file name.'
        }
        $name = [string]$file.name
        if ($file.relativePath -isnot [string]) {
            throw 'Manifest relativePath must be a string.'
        }
        $relativePath = [string]$file.relativePath
        $pathSegments = $relativePath -split '/'
        $invalidPathSegments = @($pathSegments | Where-Object { [string]::IsNullOrWhiteSpace($_) -or $_ -eq '.' -or $_ -eq '..' })
        if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath) -or $relativePath.Contains('\') -or
            $pathSegments.Count -eq 0 -or $invalidPathSegments.Count -gt 0) {
            throw 'Manifest contains an unsafe non-portable relativePath.'
        }
        if ($pathSegments[$pathSegments.Count - 1] -cne $name) {
            throw 'Manifest name must match the filename in relativePath.'
        }
        if ($file.sha256 -isnot [string] -or $file.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Manifest contains a non-lowercase SHA-256 value.'
        }
        if ($file.size -isnot [System.Int16] -and $file.size -isnot [System.Int32] -and $file.size -isnot [System.Int64] -and
            $file.size -isnot [System.UInt16] -and $file.size -isnot [System.UInt32] -and $file.size -isnot [System.UInt64]) {
            throw 'Manifest size must be an integer.'
        }
        if ([Int64]$file.size -lt 0) {
            throw 'Manifest size must be nonnegative.'
        }

        $extension = [System.IO.Path]::GetExtension($name).ToLowerInvariant()
        $expectedKind = $null
        $expectedPluginType = $null
        if ($extension -in @('.esl', '.esm', '.esp')) {
            $expectedKind = 'plugin'
            $expectedPluginType = $extension.TrimStart('.')
        }
        elseif ($extension -eq '.bsa') {
            $expectedKind = 'archive'
        }
        else {
            throw 'Manifest contains an unsupported Creation file extension.'
        }
        if ($file.kind -isnot [string] -or $file.kind -cne $expectedKind) {
            throw 'Manifest kind does not match file extension.'
        }
        if ($expectedKind -eq 'plugin') {
            if ($file.pluginType -isnot [string] -or $file.pluginType -cne $expectedPluginType) {
                throw 'Manifest pluginType does not match plugin extension.'
            }
            if ($file.internalFlag -isnot [string] -or $file.internalFlag -cne 'notInspected') {
                throw 'Manifest plugins must use internalFlag notInspected.'
            }
        }
        else {
            # Archives have no plugin type or internal plugin-header flag.
            if ($null -ne $file.pluginType -or $null -ne $file.internalFlag) {
                throw 'Manifest archives must use null pluginType and internalFlag.'
            }
        }

        $key = $relativePath.ToLowerInvariant()
        if ($byPath.ContainsKey($key)) {
            throw 'Manifest contains duplicate relativePath values.'
        }
        $byPath[$key] = $file
        if ($expectedKind -eq 'plugin') {
            $pluginKey = $name.ToLowerInvariant()
            if ($pluginsByName.ContainsKey($pluginKey)) {
                throw 'Manifest contains duplicate plugin names.'
            }
            $pluginsByName[$pluginKey] = $file
        }
    }

    $loadOrderValue = Get-PropertyValue -InputObject $manifest -Name 'loadOrder'
    if ($null -eq $loadOrderValue -or -not ($loadOrderValue -is [System.Collections.IEnumerable]) -or $loadOrderValue -is [string]) {
        throw 'Manifest loadOrder must be an array.'
    }
    $loadOrder = @($loadOrderValue)
    $loadOrderSeen = @{}
    foreach ($entry in $loadOrder) {
        if ($entry -isnot [string] -or [string]::IsNullOrWhiteSpace($entry)) {
            throw 'Manifest contains an invalid loadOrder entry.'
        }
        $entryKey = $entry.ToLowerInvariant()
        if (-not $pluginsByName.ContainsKey($entryKey)) {
            throw 'Manifest loadOrder entry is not an inventory plugin.'
        }
        if ($loadOrderSeen.ContainsKey($entryKey)) {
            throw 'Manifest contains duplicate loadOrder entries.'
        }
        $loadOrderSeen[$entryKey] = $true
    }

    return [pscustomobject]@{
        displayName = Split-Path -Path $Path -Leaf
        filesByPath = $byPath
        pluginsByName = $pluginsByName
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
            $candidate.pluginsByName.ContainsKey(([string]$_).ToLowerInvariant())
        })
        $candidateOrder = @($candidate.loadOrder | Where-Object {
            $baseline.pluginsByName.ContainsKey(([string]$_).ToLowerInvariant())
        })
        $candidatePositions = @{}
        for ($index = 0; $index -lt $candidateOrder.Count; $index++) {
            $candidatePositions[([string]$candidateOrder[$index]).ToLowerInvariant()] = $index
        }
        $baselinePositions = @{}
        for ($index = 0; $index -lt $baselineOrder.Count; $index++) {
            $baselinePositions[([string]$baselineOrder[$index]).ToLowerInvariant()] = $index
        }
        for ($index = 0; $index -lt $baselineOrder.Count; $index++) {
            $key = ([string]$baselineOrder[$index]).ToLowerInvariant()
            if (-not $candidatePositions.ContainsKey($key) -or $candidatePositions[$key] -ne $index) {
                [void]$orderDifferent.Add((New-DifferenceRecord -Manifest $candidate.displayName -RelativePath $baseline.pluginsByName[$key].relativePath))
            }
        }
        for ($index = 0; $index -lt $candidateOrder.Count; $index++) {
            $key = ([string]$candidateOrder[$index]).ToLowerInvariant()
            if (-not $baselinePositions.ContainsKey($key)) {
                [void]$orderDifferent.Add((New-DifferenceRecord -Manifest $candidate.displayName -RelativePath $candidate.pluginsByName[$key].relativePath))
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
