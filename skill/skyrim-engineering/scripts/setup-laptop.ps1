[CmdletBinding()]
param(
    [switch]$AuditOnly,
    [switch]$Plan,
    [switch]$Apply,
    [switch]$Verify,
    [switch]$Rollback,

    [Parameter(Mandatory = $true)]
    [ValidateSet('client-a', 'client-b', 'client-c')]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$GameRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$ProfileRoot,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$CanonicalManifest,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$StateDirectory,

    [string]$ToolRoot
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$commonModule = Join-Path $PSScriptRoot 'SkyrimEngineering.Common.psm1'
Import-Module $commonModule -Force

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    $full = [IO.Path]::GetFullPath($Path)
    $volumeRoot = [IO.Path]::GetPathRoot($full)
    if ([string]::Equals($full, $volumeRoot, [StringComparison]::OrdinalIgnoreCase)) { return $volumeRoot }
    return $full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Assert-FullyQualifiedLocalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -cnotmatch '^[A-Za-z]:[\\/]' -or $Path -match '^\\\\') {
        throw 'Every root and manifest path must be a fully qualified local path.'
    }
}

function Assert-NoReparseAncestor {
    param([Parameter(Mandatory = $true)][string]$Path)
    $current = Get-NormalizedPath -Path $Path
    if (-not (Test-Path -LiteralPath $current)) { $current = Split-Path -Parent $current }
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'A reparse-point ancestor was refused.'
            }
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
}

function Assert-DisjointRoots {
    param([string[]]$Roots)
    for ($left = 0; $left -lt $Roots.Count; $left++) {
        for ($right = $left + 1; $right -lt $Roots.Count; $right++) {
            $a = $Roots[$left]
            $b = $Roots[$right]
            if ([string]::Equals($a, $b, [StringComparison]::OrdinalIgnoreCase) -or
                $a.StartsWith($b + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase) -or
                $b.StartsWith($a + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
                throw 'GameRoot, ProfileRoot, and StateDirectory must not overlap.'
            }
        }
    }
}

function Assert-SafeRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
        $Path.Contains('\') -or $Path.Contains(':') -or $Path.StartsWith('/') -or
        $Path -match '(^|/)(\.\.?)(/|$)') {
        throw 'A safe relative path is required.'
    }
    foreach ($segment in @($Path -split '/')) {
        if ([string]::IsNullOrWhiteSpace($segment)) { throw 'A safe relative path is required.' }
    }
}

function Assert-SafeVersion {
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -cnotmatch '^[0-9][0-9A-Za-z._+-]{0,63}$') { throw 'Version metadata is not public-safe.' }
}

function Get-RequiredProperty {
    param($InputObject, [string]$Name, [string]$Context = 'document')
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) { throw "$Context is missing required property '$Name'." }
    return $property.Value
}

function Get-LowerHash {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash.ToLowerInvariant()
}

function Get-OpaqueId {
    param([string]$Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { $bytes = $algorithm.ComputeHash([Text.Encoding]::UTF8.GetBytes($Text)) }
    finally { $algorithm.Dispose() }
    return 'opaque-' + (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').Substring(0, 24)
}

function Convert-ToPortablePath {
    param([string]$Path)
    return $Path.Replace('\', '/')
}

function Convert-ToPublicVersion {
    param($Value)
    if ($null -eq $Value) { return $null }
    $text = [string]$Value
    if ($text -cmatch '^[0-9][0-9A-Za-z._+-]{0,63}$') { return $text }
    return 'redacted'
}

function Read-JsonFile {
    param([string]$Path, [string]$Label)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "$Label must be an existing file." }
    Assert-NoReparseAncestor -Path $Path
    try { return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw "$Label is not valid JSON." }
}

function Read-PackageCatalog {
    param([string]$Path)
    $catalog = Read-JsonFile -Path $Path -Label 'Trusted package catalog'
    if ((Get-RequiredProperty $catalog 'schema' 'Trusted package catalog') -cne 'skyrim-engineering.package-catalog/v1') {
        throw 'Trusted package catalog schema is unsupported.'
    }
    $policy = Get-RequiredProperty $catalog 'policy' 'Trusted package catalog'
    if ($policy.operation -cne 'verifiedPackageIntake' -or $policy.componentMutation -ne $false -or
        $policy.mutationStatus -cne 'deferredPendingNativeWindowsHandleRelativeWriterAndOsProtectedJournal' -or
        @($policy.verifiedArchiveTypes).Count -ne 1 -or $policy.verifiedArchiveTypes[0] -cne '7z' -or
        $policy.networkAccess -ne $false -or $policy.executePayloads -ne $false) {
        throw 'Trusted package catalog policy must describe read-only verified intake with component mutation deferred.'
    }
    $archiveTool = Get-RequiredProperty $policy 'archiveTool' 'Trusted package policy'
    foreach ($name in @('fileName', 'version', 'sha256')) { [void](Get-RequiredProperty $archiveTool $name 'Trusted archive tool') }
    if ($archiveTool.fileName -cne '7z.exe' -or $archiveTool.version -cne '26.02' -or $archiveTool.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Trusted archive tool identity is invalid.' }
    $map = @{}
    foreach ($package in @(Get-RequiredProperty $catalog 'packages' 'Trusted package catalog')) {
        foreach ($name in @('catalogId', 'component', 'version', 'gameRuntimeVersion', 'archiveFileName', 'archiveType', 'archiveBytes', 'archiveEntryCount', 'archiveSha256', 'mappings', 'prefixInventories', 'publisher', 'provenanceUrl', 'license', 'intakeVerified', 'free')) {
            [void](Get-RequiredProperty $package $name 'Trusted package entry')
        }
        if ($package.catalogId -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $map.ContainsKey([string]$package.catalogId)) {
            throw 'Trusted package catalog ids must be unique anonymous identifiers.'
        }
        if ($package.component -cne 'skse') { throw 'Only SKSE has completed package intake.' }
        Assert-SafeVersion -Value ([string]$package.version)
        Assert-SafeRelativePath -Path ([string]$package.archiveFileName)
        if ($package.archiveSha256 -cnotmatch '^[0-9a-f]{64}$' -or $package.archiveType -cne '7z' -or
            [IO.Path]::GetExtension([string]$package.archiveFileName) -cne '.7z' -or [long]$package.archiveBytes -le 0 -or [int]$package.archiveEntryCount -le 0 -or
            $package.intakeVerified -ne $true -or $package.free -ne $true -or
            [string]::IsNullOrWhiteSpace([string]$package.publisher) -or
            -not [Uri]::IsWellFormedUriString([string]$package.provenanceUrl, [UriKind]::Absolute) -or
            [string]::IsNullOrWhiteSpace([string]$package.license)) {
            throw 'Trusted package catalog entry violates verified intake provenance policy.'
        }
        $expandedMappings = New-Object Collections.ArrayList
        foreach ($mapping in @($package.mappings)) { [void]$expandedMappings.Add($mapping) }
        foreach ($inventory in @($package.prefixInventories)) {
            foreach ($name in @('archivePrefix', 'destinationRoot', 'destinationPrefix', 'extension', 'entryCount', 'entries')) { [void](Get-RequiredProperty $inventory $name 'Trusted package prefix inventory') }
            Assert-SafeRelativePath ([string]$inventory.archivePrefix).TrimEnd('/')
            Assert-SafeRelativePath ([string]$inventory.destinationPrefix).TrimEnd('/')
            if ($inventory.destinationRoot -cne 'game' -or $inventory.extension -cne '.pex' -or [int]$inventory.entryCount -ne @($inventory.entries).Count -or [int]$inventory.entryCount -le 0) {
                throw 'Trusted package prefix inventory policy is invalid.'
            }
            $prefixNames = @{}
            foreach ($entry in @($inventory.entries)) {
                foreach ($name in @('fileName', 'bytes', 'sha256')) { [void](Get-RequiredProperty $entry $name 'Trusted package prefix entry') }
                Assert-SafeRelativePath ([string]$entry.fileName)
                if ([IO.Path]::GetExtension([string]$entry.fileName) -cne '.pex' -or [IO.Path]::GetFileName([string]$entry.fileName) -cne [string]$entry.fileName -or
                    [long]$entry.bytes -le 0 -or $entry.sha256 -cnotmatch '^[0-9a-f]{64}$' -or $prefixNames.ContainsKey(([string]$entry.fileName).ToLowerInvariant())) {
                    throw 'Trusted package prefix entry is invalid or duplicated.'
                }
                $prefixNames[([string]$entry.fileName).ToLowerInvariant()] = $true
                [void]$expandedMappings.Add([pscustomobject][ordered]@{
                    archivePath = ([string]$inventory.archivePrefix) + [string]$entry.fileName
                    destinationRoot = [string]$inventory.destinationRoot
                    destinationRelativePath = ([string]$inventory.destinationPrefix) + [string]$entry.fileName
                    bytes = [long]$entry.bytes
                    sha256 = [string]$entry.sha256
                })
            }
        }
        $mappingPaths = @{}
        foreach ($mapping in @($expandedMappings)) {
            foreach ($name in @('archivePath', 'destinationRoot', 'destinationRelativePath', 'bytes', 'sha256')) { [void](Get-RequiredProperty $mapping $name 'Trusted package mapping') }
            Assert-SafeRelativePath ([string]$mapping.archivePath)
            Assert-SafeRelativePath ([string]$mapping.destinationRelativePath)
            $mappingKey = ('{0}|{1}' -f $mapping.destinationRoot, $mapping.destinationRelativePath).ToLowerInvariant()
            if ($mapping.destinationRoot -cne 'game' -or $mapping.sha256 -cnotmatch '^[0-9a-f]{64}$' -or [long]$mapping.bytes -le 0 -or $mappingPaths.ContainsKey($mappingKey)) { throw 'Trusted package mapping is invalid or duplicated.' }
            $mappingPaths[$mappingKey] = $mapping
        }
        if ($mappingPaths.Count -ne 64) { throw 'Trusted SKSE package must declare the exact 64-file runtime payload.' }
        $package.mappings = @($expandedMappings | Sort-Object destinationRoot, destinationRelativePath)
        $package | Add-Member -NotePropertyName mappingByDestination -NotePropertyValue $mappingPaths
        $map[[string]$package.catalogId] = $package
    }
    return [pscustomobject]@{ document = $catalog; byId = $map; sha256 = Get-LowerHash -Path $Path }
}

function Read-CanonicalManifest {
    param([string]$Path, $Catalog)
    $manifest = Read-JsonFile -Path $Path -Label 'CanonicalManifest'
    if ((Get-RequiredProperty $manifest 'schema' 'CanonicalManifest') -cne 'skyrim-engineering.laptop-canonical/v1') {
        throw 'CanonicalManifest schema must be skyrim-engineering.laptop-canonical/v1.'
    }
    Assert-SafeVersion -Value ([string](Get-RequiredProperty $manifest 'runtimeVersion' 'CanonicalManifest'))
    $items = @(Get-RequiredProperty $manifest 'items' 'CanonicalManifest')
    $loadOrder = @(Get-RequiredProperty $manifest 'loadOrder' 'CanonicalManifest')
    $seen = @{}
    foreach ($item in $items) {
        foreach ($name in @('id', 'category', 'root', 'relativePath', 'sha256', 'version')) { [void](Get-RequiredProperty $item $name 'Canonical item') }
        if ($item.id -cnotmatch '^[a-z0-9][a-z0-9-]*$' -or $item.category -cnotin @('anniversaryBaseline', 'approvedShared') -or
            $item.root -cnotin @('game', 'profile') -or $item.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Canonical item metadata is invalid.'
        }
        Assert-SafeRelativePath -Path ([string]$item.relativePath)
        Assert-SafeVersion -Value ([string]$item.version)
        $key = ('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()
        if ($seen.ContainsKey($key)) { throw 'Canonical manifest contains a duplicate item path.' }
        $seen[$key] = $true
        if ($item.category -eq 'approvedShared') {
            if ($null -ne $item.PSObject.Properties['sourceRelativePath']) {
                Assert-SafeRelativePath -Path ([string]$item.sourceRelativePath)
                throw 'Caller manifests cannot provide package source paths.'
            }
            $catalogId = [string](Get-RequiredProperty $item 'catalogId' 'Canonical approvedShared item')
            if (-not $Catalog.byId.ContainsKey($catalogId)) { throw 'Canonical package is not in the trusted catalog.' }
            $trusted = $Catalog.byId[$catalogId]
            $mappingKey = ('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()
            if (-not $trusted.mappingByDestination.ContainsKey($mappingKey)) { throw 'Canonical package path is not a verified intake mapping.' }
            $mapping = $trusted.mappingByDestination[$mappingKey]
            if ($item.root -cne $mapping.destinationRoot -or $item.sha256 -cne $mapping.sha256 -or $item.version -cne $trusted.version) {
                throw 'Canonical package does not exactly match its trusted catalog entry.'
            }
        }
    }
    foreach ($entry in $loadOrder) {
        if ($entry -isnot [string]) { throw 'Canonical load order entries must be strings.' }
        Assert-SafeRelativePath -Path ([string]$entry)
    }
    return $manifest
}

function Get-ExpectedInventoryItems {
    param($Manifest, $Catalog)
    $result = New-Object Collections.ArrayList
    $seen = @{}
    foreach ($item in @($Manifest.items)) {
        $key = ('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()
        $seen[$key] = $true
        [void]$result.Add($item)
    }
    foreach ($catalogId in @($Manifest.items | Where-Object category -eq 'approvedShared' | Select-Object -ExpandProperty catalogId -Unique)) {
        $package = $Catalog.byId[[string]$catalogId]
        foreach ($mapping in @($package.mappings)) {
            $key = ('{0}|{1}' -f $mapping.destinationRoot, $mapping.destinationRelativePath).ToLowerInvariant()
            if (-not $seen.ContainsKey($key)) {
                [void]$result.Add([pscustomobject][ordered]@{
                    id = 'catalog-' + (Get-OpaqueId $key).Substring(7)
                    category = 'approvedShared'
                    root = [string]$mapping.destinationRoot
                    relativePath = [string]$mapping.destinationRelativePath
                    sha256 = [string]$mapping.sha256
                    version = [string]$package.version
                    catalogId = [string]$package.catalogId
                })
                $seen[$key] = $true
            }
        }
    }
    return @($result)
}

function Get-LocalVersionMap {
    param([string]$Root)
    $map = @{}
    $path = Join-Path $Root 'versions.json'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        $versions = Read-JsonFile -Path $path -Label 'Local version metadata'
        foreach ($property in $versions.PSObject.Properties) {
            Assert-SafeRelativePath -Path ([string]$property.Name)
            $map[$property.Name.ToLowerInvariant()] = Convert-ToPublicVersion $property.Value
        }
    }
    return $map
}

function Get-Inventory {
    param($ExpectedItems, [string]$Game, [string]$Profiles)
    $expected = @{}
    foreach ($item in @($ExpectedItems)) { $expected[('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()] = $item }
    $inventory = New-Object Collections.ArrayList
    $observedGame = @{}
    $data = Join-Path $Game 'Data'
    if (Test-Path -LiteralPath $data -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $data -File -Recurse -Force | Sort-Object FullName)) {
            Assert-NoReparseAncestor -Path $file.FullName
            $relative = Convert-ToPortablePath $file.FullName.Substring($Game.Length + 1)
            $key = ('game|{0}' -f $relative).ToLowerInvariant()
            $hash = Get-LowerHash $file.FullName
            $version = if ($expected.ContainsKey($key) -and $expected[$key].sha256 -ceq $hash) { [string]$expected[$key].version } else { $null }
            [void]$inventory.Add([pscustomobject]@{ root = 'game'; relativePath = $relative; sha256 = $hash; version = $version; expected = $(if ($expected.ContainsKey($key)) { $expected[$key] } else { $null }); insideIsolated = $false })
            $observedGame[$key] = $true
        }
    }
    foreach ($item in @($ExpectedItems | Where-Object root -eq 'game')) {
        $key = ('game|{0}' -f $item.relativePath).ToLowerInvariant()
        if ($observedGame.ContainsKey($key)) { continue }
        $path = Join-Path $Game ([string]$item.relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Assert-NoReparseAncestor $path
            $hash = Get-LowerHash $path
            $version = if ($item.sha256 -ceq $hash) { [string]$item.version } else { $null }
            [void]$inventory.Add([pscustomobject]@{ root = 'game'; relativePath = [string]$item.relativePath; sha256 = $hash; version = $version; expected = $item; insideIsolated = $false })
        }
    }
    $isolated = Join-Path $Profiles 'Anniversary Together'
    foreach ($file in @(Get-ChildItem -LiteralPath $Profiles -File -Recurse -Force | Sort-Object FullName)) {
        Assert-NoReparseAncestor -Path $file.FullName
        $full = Get-NormalizedPath $file.FullName
        $inside = $full.StartsWith((Get-NormalizedPath $isolated) + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)
        $relative = if ($inside) { Convert-ToPortablePath $full.Substring((Get-NormalizedPath $isolated).Length + 1) } else { Convert-ToPortablePath $full.Substring($Profiles.Length + 1) }
        $key = ('profile|{0}' -f $relative).ToLowerInvariant()
        $hash = Get-LowerHash $full
        $version = $null
        if ($expected.ContainsKey($key) -and $expected[$key].sha256 -ceq $hash) { $version = [string]$expected[$key].version }
        [void]$inventory.Add([pscustomobject]@{ root = 'profile'; relativePath = $relative; sha256 = $hash; version = $version; expected = $(if ($expected.ContainsKey($key)) { $expected[$key] } else { $null }); insideIsolated = $inside })
    }
    return @($inventory)
}

function New-KnownRecord {
    param($Entry, [string]$Category)
    return [pscustomobject][ordered]@{ root = $Entry.root; relativePath = [string]$Entry.relativePath; category = $Category; version = $Entry.version; sha256 = $Entry.sha256 }
}

function New-OpaqueRecord {
    param($Entry, [string]$Category)
    return [pscustomobject][ordered]@{ root = $Entry.root; opaqueId = Get-OpaqueId ("$($Entry.root)|$($Entry.relativePath)|$($Entry.sha256)"); category = $Category; sha256 = $Entry.sha256 }
}

function New-Difference {
    param([string]$Root, [string]$RelativePath, $Expected, $Actual)
    return [pscustomobject][ordered]@{ root = $Root; relativePath = $RelativePath; expected = $Expected; actual = $Actual }
}

function Get-LoadOrder {
    param([string]$Game)
    $path = Join-Path $Game 'Data\plugins.txt'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { return @() }
    $result = New-Object Collections.ArrayList
    foreach ($line in @(Get-Content -LiteralPath $path)) {
        $entry = ($line -replace '#.*$', '').Trim()
        if ($entry.StartsWith('*')) { $entry = $entry.Substring(1).Trim() }
        if (-not [string]::IsNullOrWhiteSpace($entry)) { [void]$result.Add('Data/' + $entry) }
    }
    return @($result)
}

function Get-RuntimeEvidence {
    param([string]$Game, [string]$ExpectedVersion)
    $binary = Join-Path $Game 'SkyrimSE.exe'
    $actual = $null
    if (Test-Path -LiteralPath $binary -PathType Leaf) {
        Assert-NoReparseAncestor $binary
        $versionInfo = (Get-Item -LiteralPath $binary -Force).VersionInfo
        if (-not [string]::IsNullOrWhiteSpace([string]$versionInfo.FileVersion)) { $actual = Convert-ToPublicVersion $versionInfo.FileVersion }
    }
    return [pscustomobject][ordered]@{ status = $(if ($actual -ceq $ExpectedVersion) { 'exact' } elseif ($null -eq $actual) { 'missing' } else { 'incompatible' }); expectedVersion = $ExpectedVersion; actualVersion = $actual }
}

function Get-ModManagerEvidence {
    param([string]$Tools)
    if ([string]::IsNullOrWhiteSpace($Tools)) { return [pscustomobject][ordered]@{ status = 'unavailable'; executable = $null } }
    foreach ($name in @('ModOrganizer.exe', 'Vortex.exe')) {
        $path = Join-Path $Tools $name
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            Assert-NoReparseAncestor $path
            $item = Get-Item -LiteralPath $path -Force
            return [pscustomobject][ordered]@{ status = 'observed'; executable = [pscustomobject][ordered]@{ toolId = $(if ($name -ceq 'ModOrganizer.exe') { 'mod-organizer-2' } else { 'vortex' }); version = Convert-ToPublicVersion $item.VersionInfo.FileVersion; sha256 = Get-LowerHash $path } }
        }
    }
    return [pscustomobject][ordered]@{ status = 'unavailable'; executable = $null }
}

function New-Audit {
    param($Manifest, $Catalog, [string]$ModeName, [string]$Game, [string]$Profiles, [string]$Tools)
    $expectedItems = @(Get-ExpectedInventoryItems $Manifest $Catalog)
    $inventory = @(Get-Inventory $expectedItems $Game $Profiles)
    $actual = @{}
    $categories = [ordered]@{ anniversaryBaseline = New-Object Collections.ArrayList; approvedShared = New-Object Collections.ArrayList; machineSpecific = New-Object Collections.ArrayList; unknownOrIncompatible = New-Object Collections.ArrayList }
    foreach ($entry in $inventory) {
        $key = ('{0}|{1}' -f $entry.root, $entry.relativePath).ToLowerInvariant()
        $actual[$key] = $entry
        $exact = $null -ne $entry.expected -and $entry.sha256 -ceq $entry.expected.sha256 -and [string]$entry.version -ceq [string]$entry.expected.version
        if ($exact) { [void]$categories[[string]$entry.expected.category].Add((New-KnownRecord $entry ([string]$entry.expected.category))) }
        elseif ($null -ne $entry.expected) { [void]$categories.unknownOrIncompatible.Add((New-KnownRecord $entry 'unknownOrIncompatible')) }
        elseif ($entry.root -eq 'profile' -and -not $entry.insideIsolated) { [void]$categories.machineSpecific.Add((New-OpaqueRecord $entry 'machineSpecific')) }
        else { [void]$categories.unknownOrIncompatible.Add((New-OpaqueRecord $entry 'unknownOrIncompatible')) }
    }
    foreach ($name in @($categories.Keys)) { $categories[$name] = @($categories[$name] | Sort-Object root, relativePath, opaqueId) }
    $missing = New-Object Collections.ArrayList
    $extra = New-Object Collections.ArrayList
    $hashDifferent = New-Object Collections.ArrayList
    $versionDifferent = New-Object Collections.ArrayList
    foreach ($item in @($expectedItems)) {
        $key = ('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()
        if (-not $actual.ContainsKey($key)) { [void]$missing.Add((New-Difference $item.root $item.relativePath $item.sha256 $null)); continue }
        if ($actual[$key].sha256 -cne $item.sha256) { [void]$hashDifferent.Add((New-Difference $item.root $item.relativePath $item.sha256 $actual[$key].sha256)) }
        if ([string]$actual[$key].version -cne [string]$item.version) { [void]$versionDifferent.Add((New-Difference $item.root $item.relativePath $item.version $actual[$key].version)) }
    }
    foreach ($entry in $inventory) {
        if ($null -eq $entry.expected) { [void]$extra.Add([pscustomobject][ordered]@{ root = $entry.root; opaqueId = Get-OpaqueId ("$($entry.root)|$($entry.relativePath)|$($entry.sha256)") }) }
    }
    $expectedOrder = @($Manifest.loadOrder)
    $actualOrder = @(Get-LoadOrder $Game)
    $orderDifferent = New-Object Collections.ArrayList
    foreach ($path in $expectedOrder) {
        $expectedIndex = [array]::IndexOf([object[]]$expectedOrder, $path)
        $actualIndex = [array]::IndexOf([object[]]$actualOrder, $path)
        if ($actualIndex -ge 0 -and $actualIndex -ne $expectedIndex) { [void]$orderDifferent.Add((New-Difference 'game' $path $expectedIndex $actualIndex)) }
    }
    foreach ($path in @($actualOrder | Where-Object { $_ -notin $expectedOrder })) {
        [void]$orderDifferent.Add([pscustomobject][ordered]@{ root = 'game'; opaqueId = Get-OpaqueId ('loadOrder|' + $path); expected = $null; actual = [array]::IndexOf([object[]]$actualOrder, $path) })
    }
    $exactBaseline = @($categories.anniversaryBaseline).Count
    $expectedBaseline = @($Manifest.items | Where-Object category -eq 'anniversaryBaseline').Count
    $componentStatus = @{}
    foreach ($component in @('skse', 'addressLibrary', 'skyrimTogether')) {
        $componentItems = @($expectedItems | Where-Object {
            $_.category -eq 'approvedShared' -and $Catalog.byId[[string]$_.catalogId].component -ceq $component
        })
        $unsupported = @($Catalog.document.unsupportedComponents | Where-Object component -ceq $component)
        $componentStatus[$component] = [pscustomobject][ordered]@{ status = $(if ($unsupported.Count -eq 1) { [string]$unsupported[0].status } elseif (@($componentItems).Count -eq 0) { 'notConfigured' } elseif (@($categories.approvedShared | Where-Object { $_.relativePath -in @($componentItems.relativePath) }).Count -eq $componentItems.Count) { 'exact' } else { 'missingOrIncompatible' }) }
    }
    $pluginItems = @($inventory | Where-Object { $_.root -eq 'game' -and [IO.Path]::GetExtension($_.relativePath).ToLowerInvariant() -in @('.esm', '.esl', '.esp') } |
        ForEach-Object { [pscustomobject][ordered]@{ opaqueId = Get-OpaqueId ("plugin|$($_.root)|$($_.relativePath)|$($_.sha256)"); sha256 = $_.sha256 } })
    $archiveItems = @($inventory | Where-Object { $_.root -eq 'game' -and [IO.Path]::GetExtension($_.relativePath).ToLowerInvariant() -in @('.bsa', '.ba2') } |
        ForEach-Object { [pscustomobject][ordered]@{ opaqueId = Get-OpaqueId ("archive|$($_.root)|$($_.relativePath)|$($_.sha256)"); sha256 = $_.sha256 } })
    $creationItems = @($inventory | Where-Object {
        $_.root -eq 'game' -and $_.relativePath -match '(?i)^Data/[^/]+$' -and
            (Test-ApprovedCreationFile -Name ([IO.Path]::GetFileName([string]$_.relativePath)))
    } | ForEach-Object {
        $extension = [IO.Path]::GetExtension($_.relativePath).ToLowerInvariant()
        [pscustomobject][ordered]@{
            opaqueId = Get-OpaqueId ("creation|$($_.root)|$($_.relativePath)|$($_.sha256)")
            kind = $(if ($extension -in @('.esm', '.esl', '.esp')) { 'plugin' } else { 'archive' })
            sha256 = $_.sha256
        }
    })
    $profileItems = @(Get-ChildItem -LiteralPath $Profiles -Directory -Force | Where-Object Name -ne 'Anniversary Together' | Sort-Object Name | ForEach-Object {
        [pscustomobject][ordered]@{ opaqueId = Get-OpaqueId ('profile|' + $_.FullName); fileCount = @(Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Force).Count }
    })
    $domains = [ordered]@{
        runtime = Get-RuntimeEvidence $Game ([string]$Manifest.runtimeVersion)
        creations = [pscustomobject][ordered]@{ status = 'observed'; count = $creationItems.Count; items = $creationItems }
        plugins = [pscustomobject][ordered]@{ status = 'observed'; count = $pluginItems.Count; items = $pluginItems }
        archives = [pscustomobject][ordered]@{ status = 'observed'; count = $archiveItems.Count; items = $archiveItems }
        skse = $componentStatus.skse
        addressLibrary = $componentStatus.addressLibrary
        skyrimTogether = $componentStatus.skyrimTogether
        modManager = Get-ModManagerEvidence $Tools
        profiles = [pscustomobject][ordered]@{ status = 'observed'; count = $profileItems.Count; items = $profileItems }
        loadOrder = [pscustomobject][ordered]@{ status = $(if ($orderDifferent.Count -eq 0) { 'exact' } else { 'different' }); expectedCount = $expectedOrder.Count; actualCount = $actualOrder.Count }
    }
    return [pscustomobject][ordered]@{
        schema = 'skyrim-engineering.laptop-audit/v1'; clientId = $ClientId; mode = $ModeName; runtimeVersion = [string]$Manifest.runtimeVersion
        domains = [pscustomobject]$domains; categories = [pscustomobject]$categories
        differences = [pscustomobject][ordered]@{ missing = @($missing | Sort-Object root, relativePath); extra = @($extra | Sort-Object root, opaqueId); hashDifferent = @($hashDifferent | Sort-Object root, relativePath); versionDifferent = @($versionDifferent | Sort-Object root, relativePath); orderDifferent = @($orderDifferent | Sort-Object root, relativePath, opaqueId) }
    }
}

function Get-TrustedPackages {
    param($Manifest, $Catalog)
    $result = New-Object Collections.ArrayList
    foreach ($catalogId in @($Manifest.items | Where-Object category -eq 'approvedShared' | Select-Object -ExpandProperty catalogId -Unique | Sort-Object)) { [void]$result.Add($Catalog.byId[[string]$catalogId]) }
    return @($result)
}

function New-Plan {
    param($Manifest, $Catalog, $Audit, [string]$Profiles)
    $intake = @(Get-TrustedPackages $Manifest $Catalog | ForEach-Object {
        [pscustomobject][ordered]@{
            catalogId = [string]$_.catalogId
            component = [string]$_.component
            version = [string]$_.version
            status = 'verifiedIntakeEvidence'
            expectedFileCount = @($_.mappings).Count
        }
    })
    return [pscustomobject][ordered]@{
        schema = 'skyrim-engineering.laptop-plan/v1'
        clientId = $ClientId
        operation = 'readOnlyAssessment'
        supportedModes = @('AuditOnly', 'Plan', 'Verify')
        actions = @()
        packageIntake = $intake
        deferred = [pscustomobject][ordered]@{
            schema = 'skyrim-engineering.laptop-deferred/v1'
            status = 'deferred'
            modes = @('Apply', 'Rollback')
            requiredCapabilities = @('externalProfileManager', 'toolOwnedRollback')
        }
        differences = $Audit.differences
    }
}

$modeCount = @($AuditOnly, $Plan, $Apply, $Verify, $Rollback | Where-Object { $_ }).Count
if ($modeCount -ne 1) { throw 'Select exactly one mode: -AuditOnly, -Plan, -Apply, -Verify, or -Rollback.' }
if ($Apply -or $Rollback) {
    $requestedMode = if ($Apply) { 'Apply' } else { 'Rollback' }
    $deferred = [pscustomobject][ordered]@{
        schema = 'skyrim-engineering.laptop-deferred/v1'
        mode = $requestedMode
        status = 'deferred'
        message = 'Component Apply and Rollback are deferred for v0.1 pending a pinned MO2 or Wabbajack workflow with tool-owned rollback. Use -AuditOnly, -Plan, or -Verify; do not mutate the live game tree.'
        requiredCapabilities = @('externalProfileManager', 'toolOwnedRollback')
        supportedModes = @('AuditOnly', 'Plan', 'Verify')
    }
    throw ($deferred | ConvertTo-Json -Depth 4 -Compress)
}
foreach ($inputPath in @($GameRoot, $ProfileRoot, $CanonicalManifest, $StateDirectory)) { Assert-FullyQualifiedLocalPath $inputPath }
$game = Get-NormalizedPath $GameRoot
$profiles = Get-NormalizedPath $ProfileRoot
$manifestPath = Get-NormalizedPath $CanonicalManifest
$states = Get-NormalizedPath $StateDirectory
foreach ($root in @($game, $profiles, $states)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'GameRoot, ProfileRoot, and StateDirectory must be existing explicit directories.' }
    Assert-NoReparseAncestor $root
}
Assert-DisjointRoots @($game, $profiles, $states)
$tools = $null
if (-not [string]::IsNullOrWhiteSpace($ToolRoot)) {
    Assert-FullyQualifiedLocalPath $ToolRoot
    $tools = Get-NormalizedPath $ToolRoot
    if (-not (Test-Path -LiteralPath $tools -PathType Container)) { throw 'ToolRoot must be an existing explicit directory.' }
    Assert-NoReparseAncestor $tools
    Assert-DisjointRoots @($game, $profiles, $states, $tools)
}
Assert-NoReparseAncestor $manifestPath
$catalogPath = Get-NormalizedPath (Join-Path $PSScriptRoot '..\references\laptop-package-catalog.json')
$catalog = Read-PackageCatalog $catalogPath
$manifest = Read-CanonicalManifest $manifestPath $catalog

if ($AuditOnly) { New-Audit $manifest $catalog 'auditOnly' $game $profiles $tools | ConvertTo-Json -Depth 10 -Compress }
elseif ($Plan) { $audit = New-Audit $manifest $catalog 'plan' $game $profiles $tools; New-Plan $manifest $catalog $audit $profiles | ConvertTo-Json -Depth 10 -Compress }
elseif ($Verify) { New-Audit $manifest $catalog 'verify' $game $profiles $tools | ConvertTo-Json -Depth 10 -Compress }
