[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
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

    [ValidateNotNullOrEmpty()]
    [string]$PackageCache,

    [string]$ToolRoot,

    [string]$ArchiveToolPath = 'C:\Program Files\7-Zip\7z.exe',

    [ValidateSet('journalCreated', 'stageCreated', 'payloadExtracted', 'payloadVerified', 'profilePublished')]
    [string]$InterruptAfter,

    [switch]$ConfirmApply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Assert-ContainedPath {
    param([string]$Root, [string]$Candidate)
    $rootPath = Get-NormalizedPath -Path $Root
    $candidatePath = Get-NormalizedPath -Path $Candidate
    if (-not $candidatePath.StartsWith($rootPath + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Resolved path escapes its explicit root.'
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
    if ($policy.operation -cne 'approved7zInstall' -or @($policy.allowedArchiveTypes).Count -ne 1 -or
        $policy.allowedArchiveTypes[0] -cne '7z' -or $policy.networkAccess -ne $false -or $policy.executePayloads -ne $false) {
        throw 'Trusted package catalog policy must permit 7z extraction only, without network access or payload execution.'
    }
    $archiveTool = Get-RequiredProperty $policy 'archiveTool' 'Trusted package policy'
    foreach ($name in @('fileName', 'version', 'sha256')) { [void](Get-RequiredProperty $archiveTool $name 'Trusted archive tool') }
    if ($archiveTool.fileName -cne '7z.exe' -or $archiveTool.version -cne '26.02' -or $archiveTool.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Trusted archive tool identity is invalid.' }
    $map = @{}
    foreach ($package in @(Get-RequiredProperty $catalog 'packages' 'Trusted package catalog')) {
        foreach ($name in @('catalogId', 'component', 'version', 'gameRuntimeVersion', 'archiveFileName', 'archiveType', 'archiveBytes', 'archiveEntryCount', 'archiveSha256', 'mappings', 'publisher', 'provenanceUrl', 'license', 'approved', 'free')) {
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
            $package.approved -ne $true -or $package.free -ne $true -or
            [string]::IsNullOrWhiteSpace([string]$package.publisher) -or
            -not [Uri]::IsWellFormedUriString([string]$package.provenanceUrl, [UriKind]::Absolute) -or
            [string]::IsNullOrWhiteSpace([string]$package.license)) {
            throw 'Trusted package catalog entry violates provenance or approved 7z policy.'
        }
        $mappingPaths = @{}
        foreach ($mapping in @($package.mappings)) {
            foreach ($name in @('archivePath', 'destinationRelativePath', 'bytes', 'sha256')) { [void](Get-RequiredProperty $mapping $name 'Trusted package mapping') }
            Assert-SafeRelativePath ([string]$mapping.archivePath)
            Assert-SafeRelativePath ([string]$mapping.destinationRelativePath)
            if ($mapping.sha256 -cnotmatch '^[0-9a-f]{64}$' -or [long]$mapping.bytes -le 0 -or $mappingPaths.ContainsKey(([string]$mapping.destinationRelativePath).ToLowerInvariant())) { throw 'Trusted package mapping is invalid or duplicated.' }
            $mappingPaths[([string]$mapping.destinationRelativePath).ToLowerInvariant()] = $mapping
        }
        if ($mappingPaths.Count -eq 0) { throw 'Trusted package must have explicit entry mappings.' }
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
                throw 'Package source authorization must come from the trusted catalog.'
            }
            $catalogId = [string](Get-RequiredProperty $item 'catalogId' 'Canonical approvedShared item')
            if (-not $Catalog.byId.ContainsKey($catalogId)) { throw 'Canonical package is not in the trusted catalog.' }
            $trusted = $Catalog.byId[$catalogId]
            $mappingKey = ([string]$item.relativePath).ToLowerInvariant()
            if (-not $trusted.mappingByDestination.ContainsKey($mappingKey)) { throw 'Canonical package path is not an approved catalog mapping.' }
            $mapping = $trusted.mappingByDestination[$mappingKey]
            if ($item.root -cne 'profile' -or $item.sha256 -cne $mapping.sha256 -or $item.version -cne $trusted.version) {
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
    param($Manifest, [string]$Game, [string]$Profiles)
    $expected = @{}
    foreach ($item in @($Manifest.items)) { $expected[('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()] = $item }
    $inventory = New-Object Collections.ArrayList
    $data = Join-Path $Game 'Data'
    if (Test-Path -LiteralPath $data -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $data -File -Recurse -Force | Sort-Object FullName)) {
            Assert-NoReparseAncestor -Path $file.FullName
            $relative = Convert-ToPortablePath $file.FullName.Substring($Game.Length + 1)
            $key = ('game|{0}' -f $relative).ToLowerInvariant()
            $hash = Get-LowerHash $file.FullName
            $version = if ($expected.ContainsKey($key) -and $expected[$key].sha256 -ceq $hash) { [string]$expected[$key].version } else { $null }
            [void]$inventory.Add([pscustomobject]@{ root = 'game'; relativePath = $relative; sha256 = $hash; version = $version; expected = $(if ($expected.ContainsKey($key)) { $expected[$key] } else { $null }); insideIsolated = $false })
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
    $inventory = @(Get-Inventory $Manifest $Game $Profiles)
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
    foreach ($item in @($Manifest.items)) {
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
        $componentItems = @($Manifest.items | Where-Object {
            $_.category -eq 'approvedShared' -and $Catalog.byId[[string]$_.catalogId].component -ceq $component
        })
        $unsupported = @($Catalog.document.unsupportedComponents | Where-Object component -ceq $component)
        $componentStatus[$component] = [pscustomobject][ordered]@{ status = $(if ($unsupported.Count -eq 1) { [string]$unsupported[0].status } elseif (@($componentItems).Count -eq 0) { 'notConfigured' } elseif (@($categories.approvedShared | Where-Object { $_.relativePath -in @($componentItems.relativePath) }).Count -eq $componentItems.Count) { 'exact' } else { 'missingOrIncompatible' }) }
    }
    $pluginItems = @($inventory | Where-Object { $_.root -eq 'game' -and [IO.Path]::GetExtension($_.relativePath).ToLowerInvariant() -in @('.esm', '.esl', '.esp') } |
        ForEach-Object { [pscustomobject][ordered]@{ opaqueId = Get-OpaqueId ("plugin|$($_.root)|$($_.relativePath)|$($_.sha256)"); sha256 = $_.sha256 } })
    $archiveItems = @($inventory | Where-Object { $_.root -eq 'game' -and [IO.Path]::GetExtension($_.relativePath).ToLowerInvariant() -in @('.bsa', '.ba2') } |
        ForEach-Object { [pscustomobject][ordered]@{ opaqueId = Get-OpaqueId ("archive|$($_.root)|$($_.relativePath)|$($_.sha256)"); sha256 = $_.sha256 } })
    $profileItems = @(Get-ChildItem -LiteralPath $Profiles -Directory -Force | Where-Object Name -ne 'Anniversary Together' | Sort-Object Name | ForEach-Object {
        [pscustomobject][ordered]@{ opaqueId = Get-OpaqueId ('profile|' + $_.FullName); fileCount = @(Get-ChildItem -LiteralPath $_.FullName -File -Recurse -Force).Count }
    })
    $domains = [ordered]@{
        runtime = Get-RuntimeEvidence $Game ([string]$Manifest.runtimeVersion)
        creations = [pscustomobject][ordered]@{ status = 'observed'; count = $pluginItems.Count; items = $pluginItems }
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
    $actions = New-Object Collections.ArrayList
    if (-not (Test-Path -LiteralPath (Join-Path $Profiles 'Anniversary Together'))) { [void]$actions.Add([pscustomobject][ordered]@{ type = 'createProfile'; relativePath = 'Anniversary Together' }) }
    $missingPaths = @($Audit.differences.missing.relativePath)
    foreach ($package in @(Get-TrustedPackages $Manifest $Catalog)) {
        foreach ($mapping in @($package.mappings)) {
            if ($mapping.destinationRelativePath -in $missingPaths) { [void]$actions.Add([pscustomobject][ordered]@{ type = 'installApproved7zEntry'; catalogId = $package.catalogId; component = $package.component; archiveFileName = $package.archiveFileName; archiveSha256 = $package.archiveSha256; relativePath = $mapping.destinationRelativePath; version = $package.version; sha256 = $mapping.sha256 }) }
        }
    }
    return [pscustomobject][ordered]@{ schema = 'skyrim-engineering.laptop-plan/v1'; clientId = $ClientId; operation = 'approved7zInstall'; actions = @($actions); differences = $Audit.differences }
}

function Get-ExpectedMutations {
    param($Manifest, $Catalog)
    $directories = @{'Anniversary Together' = $true}
    $files = New-Object Collections.ArrayList
    foreach ($package in @(Get-TrustedPackages $Manifest $Catalog)) {
        foreach ($mapping in @($package.mappings)) {
            $relative = 'Anniversary Together/' + [string]$mapping.destinationRelativePath
            $parent = [IO.Path]::GetDirectoryName($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
            while (-not [string]::IsNullOrEmpty($parent)) {
                $portable = Convert-ToPortablePath $parent
                $directories[$portable] = $true
                if ($portable -ceq 'Anniversary Together') { break }
                $parent = [IO.Path]::GetDirectoryName($parent)
            }
            [void]$files.Add([pscustomobject][ordered]@{ type = 'createFile'; root = 'profile'; relativePath = $relative; sha256 = [string]$mapping.sha256; catalogId = [string]$package.catalogId; status = 'planned' })
        }
    }
    $mutations = New-Object Collections.ArrayList
    foreach ($directory in @($directories.Keys | Sort-Object { ($_ -split '/').Count }, { $_ })) { [void]$mutations.Add([pscustomobject][ordered]@{ type = 'createDirectory'; root = 'profile'; relativePath = $directory; sha256 = $null; catalogId = $null; status = 'planned' }) }
    foreach ($file in @($files | Sort-Object relativePath)) { [void]$mutations.Add($file) }
    return @($mutations)
}

function Write-BytesExclusively {
    param([string]$Path, [byte[]]$Bytes)
    $stream = New-Object IO.FileStream($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try { $stream.Write($Bytes, 0, $Bytes.Length); $stream.Flush($true) } finally { $stream.Dispose() }
}

function Write-StateAtomic {
    param($State, [string]$StatePath, [switch]$CreateNew)
    $transactionId = [guid]::NewGuid().ToString('N')
    $next = $StatePath + '.' + $transactionId + '.next'
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($State | ConvertTo-Json -Depth 12 -Compress))
    Write-BytesExclusively $next $bytes
    try {
        if ($CreateNew) {
            if (Test-Path -LiteralPath $StatePath) { throw 'Client state journal already exists.' }
            [IO.File]::Move($next, $StatePath)
        }
        else {
            $backup = $StatePath + '.' + $transactionId + '.backup'
            [IO.File]::Replace($next, $StatePath, $backup)
            if (Test-Path -LiteralPath $backup) { Remove-Item -LiteralPath $backup }
        }
    }
    finally { if (Test-Path -LiteralPath $next) { Remove-Item -LiteralPath $next } }
}

function Assert-SourcePackage {
    param($Package, [string]$Cache)
    if ($Package.archiveType -cne '7z') { throw "Unsupported archive type '$($Package.archiveType)'; only 7z is allowed." }
    $source = Join-Path $Cache ([string]$Package.archiveFileName).Replace('/', [IO.Path]::DirectorySeparatorChar)
    Assert-ContainedPath $Cache $source
    Assert-NoReparseAncestor $source
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'Required package cache archive is missing.' }
    $item = Get-Item -LiteralPath $source -Force
    if ($item.Length -ne [long]$Package.archiveBytes -or (Get-LowerHash $source) -cne $Package.archiveSha256) { throw 'Package cache archive failed its pinned archive hash or size.' }
    return $source
}

function Assert-ArchiveTool {
    param($Catalog, [string]$Path)
    Assert-FullyQualifiedLocalPath $Path
    $normalized = Get-NormalizedPath $Path
    Assert-NoReparseAncestor $normalized
    if (-not (Test-Path -LiteralPath $normalized -PathType Leaf)) { throw 'Pinned 7-Zip tool is missing.' }
    $expected = $Catalog.document.policy.archiveTool
    $item = Get-Item -LiteralPath $normalized -Force
    if ($item.Name -cne $expected.fileName -or $item.VersionInfo.FileVersion -cne $expected.version -or (Get-LowerHash $normalized) -cne $expected.sha256) { throw '7-Zip tool identity, version, or hash is not approved.' }
    return $normalized
}

function Assert-NoReparseTree {
    param([string]$Root)
    Assert-NoReparseAncestor $Root
    foreach ($item in @(Get-ChildItem -LiteralPath $Root -Force -Recurse)) {
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'An extracted reparse or symbolic-link entry was refused.' }
    }
}

function Assert-Official7zLayout {
    param($Package, [string]$ArchivePath, [string]$Tool)
    $output = @(& $Tool l -slt -ba -- $ArchivePath 2>&1)
    if ($LASTEXITCODE -ne 0) { throw '7-Zip could not list the approved archive.' }
    $paths = @($output | Where-Object { $_ -like 'Path = *' } | ForEach-Object { Convert-ToPortablePath $_.Substring(7) })
    if ($paths.Count -ne [int]$Package.archiveEntryCount) { throw 'Approved archive entry count is unexpected.' }
    foreach ($path in $paths) { Assert-SafeRelativePath $path }
    if (@($output | Where-Object { $_ -match '^(Symbolic Link|Hard Link) = .+' }).Count -gt 0) { throw 'Archive link entries are refused.' }
    foreach ($mapping in @($Package.mappings)) {
        if ([string]$mapping.archivePath -cnotin $paths) { throw 'Approved archive is missing a mapped entry.' }
    }
}

function Test-QualificationInterrupt {
    param([string]$Boundary)
    if ($InterruptAfter -ceq $Boundary) { throw "simulated interruption after $Boundary" }
}

function Remove-OwnedStage {
    param($State, [string]$Profiles)
    $expectedRelative = '.skyrim-engineering-stage-' + [string]$State.transactionId
    if ($State.stagingRelativePath -cne $expectedRelative -or $State.ownershipToken -cnotmatch '^[a-f0-9]{64}$') { throw 'Journal staging ownership identity is invalid.' }
    $stage = Join-Path $Profiles $expectedRelative
    Assert-ContainedPath $Profiles $stage
    if (-not (Test-Path -LiteralPath $stage -PathType Container)) { return }
    Assert-NoReparseTree $stage
    $marker = Join-Path $stage '.skyrim-engineering-owner'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or (Get-Content -LiteralPath $marker -Raw) -cne $State.ownershipToken) { throw 'Staging ownership marker does not match the journal.' }
    Remove-Item -LiteralPath $stage -Recurse -Force
}

function Invoke-ApplyTransaction {
    param($Manifest, $Catalog, [string]$ManifestPath, [string]$Profiles, [string]$States, [string]$Cache, [string]$Tool)
    if (-not $ConfirmApply) { throw 'Apply requires the separate -ConfirmApply switch.' }
    if (-not $PSCmdlet.ShouldProcess('Anniversary Together', 'Create a new isolated profile from the pinned official SKSE 7z archive')) { return }
    $profile = Join-Path $Profiles 'Anniversary Together'
    $statePath = Join-Path $States ($ClientId + '.state.json')
    if ([string]::IsNullOrWhiteSpace($Cache)) { throw 'Apply requires an explicit -PackageCache.' }
    Assert-NoReparseAncestor $Cache
    Assert-NoReparseAncestor $States
    if (Test-Path -LiteralPath $profile) { throw 'Anniversary Together already exists; Apply refuses to merge into a pre-existing profile.' }
    if (Test-Path -LiteralPath $statePath) { throw 'Client state journal already exists; use Rollback for an applying or applied transaction.' }
    $packages = @(Get-TrustedPackages $Manifest $Catalog)
    if ($packages.Count -ne 1 -or $packages[0].component -cne 'skse') { throw 'Only the approved SKSE package may be applied.' }
    foreach ($package in $packages) { [void](Assert-SourcePackage $package $Cache) }
    $toolPath = Assert-ArchiveTool $Catalog $Tool
    $transactionId = [guid]::NewGuid().ToString('N')
    $ownershipBytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Fill($ownershipBytes)
    $ownershipToken = ($ownershipBytes | ForEach-Object { $_.ToString('x2') }) -join ''
    $stageRelative = '.skyrim-engineering-stage-' + $transactionId
    $state = [pscustomobject][ordered]@{ schema = 'skyrim-engineering.laptop-state/v1'; clientId = $ClientId; status = 'applying'; phase = 'journalCreated'; operation = 'approved7zInstall'; transactionId = $transactionId; stagingRelativePath = $stageRelative; ownershipToken = $ownershipToken; manifestSha256 = Get-LowerHash $ManifestPath; catalogSha256 = $Catalog.sha256; mutations = @(Get-ExpectedMutations $Manifest $Catalog) }
    Write-StateAtomic $state $statePath -CreateNew
    Test-QualificationInterrupt 'journalCreated'
    try {
        $stage = Join-Path $Profiles $stageRelative
        Assert-NoReparseAncestor $Profiles
        if (Test-Path -LiteralPath $stage) { throw 'Transaction staging path unexpectedly exists.' }
        [void](New-Item -ItemType Directory -Path $stage -ErrorAction Stop)
        Write-BytesExclusively (Join-Path $stage '.skyrim-engineering-owner') ((New-Object Text.UTF8Encoding($false)).GetBytes($ownershipToken))
        $state.phase = 'stageCreated'; Write-StateAtomic $state $statePath
        Test-QualificationInterrupt 'stageCreated'

        $package = $packages[0]
        $archive = Assert-SourcePackage $package $Cache
        Assert-Official7zLayout $package $archive $toolPath
        $extractRoot = Join-Path $stage 'extract'
        Assert-NoReparseAncestor $stage
        [void](New-Item -ItemType Directory -Path $extractRoot -ErrorAction Stop)
        $arguments = @('x', '-y', "-o$extractRoot", '--', $archive) + @($package.mappings | ForEach-Object { ([string]$_.archivePath).Replace('/', '\') })
        $output = @(& $toolPath @arguments 2>&1)
        if ($LASTEXITCODE -ne 0) { throw ('7-Zip extraction failed: ' + ($output -join ' ')) }
        $state.phase = 'payloadExtracted'; Write-StateAtomic $state $statePath
        Test-QualificationInterrupt 'payloadExtracted'
        Assert-NoReparseTree $extractRoot
        $extractedFiles = @(Get-ChildItem -LiteralPath $extractRoot -File -Recurse -Force)
        if ($extractedFiles.Count -ne @($package.mappings).Count) { throw 'Extraction produced unexpected files.' }
        $publishProfile = Join-Path $stage 'publish\Anniversary Together'
        foreach ($mapping in @($package.mappings)) {
            $source = Join-Path $extractRoot ([string]$mapping.archivePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Item $source).Length -ne [long]$mapping.bytes -or (Get-LowerHash $source) -cne $mapping.sha256) { throw 'Extracted SKSE payload failed its pinned hash or size.' }
            $destination = Join-Path $publishProfile ([string]$mapping.destinationRelativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
            $parent = Split-Path -Parent $destination
            [void](New-Item -ItemType Directory -Path $parent -Force)
            Assert-NoReparseAncestor $parent
            [IO.File]::Move($source, $destination)
        }
        $state.phase = 'payloadVerified'; Write-StateAtomic $state $statePath
        Test-QualificationInterrupt 'payloadVerified'
        Assert-NoReparseTree $publishProfile
        Assert-NoReparseAncestor $Profiles
        if (Test-Path -LiteralPath $profile) { throw 'Final profile appeared before atomic publication.' }
        [IO.Directory]::Move($publishProfile, $profile)
        foreach ($mutation in @($state.mutations)) { $mutation.status = 'complete' }
        $state.phase = 'profilePublished'; Write-StateAtomic $state $statePath
        Test-QualificationInterrupt 'profilePublished'
        Remove-OwnedStage $state $Profiles
        $state.phase = 'cleanupComplete'; $state.status = 'applied'; Write-StateAtomic $state $statePath
        return $state
    }
    catch { throw ('Apply stopped in recoverable applying state. Run Rollback with the same manifest and roots. {0}' -f $_.Exception.Message) }
}

function Assert-JournalAllowlist {
    param($State, $Manifest, $Catalog, [string]$ManifestPath)
    if ($State.schema -cne 'skyrim-engineering.laptop-state/v1' -or $State.clientId -cne $ClientId -or $State.status -cnotin @('applying', 'applied') -or
        $State.operation -cne 'approved7zInstall' -or $State.transactionId -cnotmatch '^[a-f0-9]{32}$' -or
        $State.stagingRelativePath -cne ('.skyrim-engineering-stage-' + [string]$State.transactionId) -or $State.ownershipToken -cnotmatch '^[a-f0-9]{64}$' -or
        $State.phase -cnotin @('journalCreated', 'stageCreated', 'payloadExtracted', 'payloadVerified', 'profilePublished', 'cleanupComplete') -or
        $State.manifestSha256 -cne (Get-LowerHash $ManifestPath) -or $State.catalogSha256 -cne $Catalog.sha256) {
        throw 'State journal identity or trusted manifest binding is invalid.'
    }
    $expected = @(Get-ExpectedMutations $Manifest $Catalog)
    $actual = @($State.mutations)
    if ($actual.Count -ne $expected.Count) { throw 'State journal mutation set does not match the trusted allowlist.' }
    $seen = @{}
    for ($index = 0; $index -lt $expected.Count; $index++) {
        $want = $expected[$index]; $have = $actual[$index]
        $key = ('{0}|{1}' -f $have.type, $have.relativePath).ToLowerInvariant()
        if ($seen.ContainsKey($key) -or $have.type -cne $want.type -or $have.root -cne 'profile' -or $have.relativePath -cne $want.relativePath -or
            [string]$have.sha256 -cne [string]$want.sha256 -or [string]$have.catalogId -cne [string]$want.catalogId -or $have.status -cnotin @('planned', 'pending', 'complete')) {
            throw 'State journal contains duplicate, altered, or non-allowlisted mutations.'
        }
        $seen[$key] = $true
    }
    return $actual
}

function Move-Verify-DeleteFile {
    param([string]$Path, [string]$ExpectedHash, [string]$Quarantine)
    Assert-NoReparseAncestor $Path
    if (Test-Path -LiteralPath $Quarantine) { throw 'Rollback quarantine path is unexpectedly occupied.' }
    [IO.File]::Move($Path, $Quarantine)
    $hash = Get-LowerHash $Quarantine
    if ($hash -cne $ExpectedHash) {
        if (-not (Test-Path -LiteralPath $Path)) { [IO.File]::Move($Quarantine, $Path) }
        throw 'A journaled file hash no longer matches; rollback restored it without deletion.'
    }
    Remove-Item -LiteralPath $Quarantine
}

function Invoke-RollbackTransaction {
    param($Manifest, $Catalog, [string]$ManifestPath, [string]$Profiles, [string]$States)
    $statePath = Join-Path $States ($ClientId + '.state.json')
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'No journaled state exists for this client.' }
    if (-not $PSCmdlet.ShouldProcess('Anniversary Together', 'Rollback only the trusted manifest-derived mutation allowlist')) { return }
    Assert-NoReparseAncestor $statePath
    $state = Read-JsonFile $statePath 'Client state journal'
    $mutations = @(Assert-JournalAllowlist $state $Manifest $Catalog $ManifestPath)
    Remove-OwnedStage $state $Profiles
    foreach ($mutation in @($mutations | Where-Object { $_.type -eq 'createFile' -and $_.status -in @('pending', 'complete') } | Sort-Object relativePath -Descending)) {
        $path = Join-Path $Profiles ([string]$mutation.relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        Assert-ContainedPath $Profiles $path
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $quarantine = Join-Path $States ('.' + $ClientId + '.' + $mutation.catalogId + '.rollback.tmp')
            Move-Verify-DeleteFile $path ([string]$mutation.sha256) $quarantine
        }
    }
    foreach ($mutation in @($mutations | Where-Object { $_.type -eq 'createDirectory' -and $_.status -in @('pending', 'complete') } | Sort-Object { ([string]$_.relativePath).Length } -Descending)) {
        $path = Join-Path $Profiles ([string]$mutation.relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        Assert-ContainedPath $Profiles $path
        Assert-NoReparseAncestor $path
        if ((Test-Path -LiteralPath $path -PathType Container) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) { Remove-Item -LiteralPath $path }
    }
    $state.status = 'rolledBack'
    Write-StateAtomic $state $statePath
    return $state
}

$modeCount = @($AuditOnly, $Plan, $Apply, $Verify, $Rollback | Where-Object { $_ }).Count
if ($modeCount -ne 1) { throw 'Select exactly one mode: -AuditOnly, -Plan, -Apply, -Verify, or -Rollback.' }
if ($ConfirmApply -and -not $Apply) { throw '-ConfirmApply is valid only with -Apply.' }
if (-not [string]::IsNullOrWhiteSpace($InterruptAfter) -and -not $Apply) { throw '-InterruptAfter is valid only with -Apply qualification tests.' }
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
if ($Apply) {
    if ([string]::IsNullOrWhiteSpace($PackageCache)) { throw 'Apply requires an explicit -PackageCache.' }
    Assert-FullyQualifiedLocalPath $PackageCache
    $packageCachePath = Get-NormalizedPath $PackageCache
    if (-not (Test-Path -LiteralPath $packageCachePath -PathType Container)) { throw 'PackageCache must be an existing explicit directory.' }
    Assert-NoReparseAncestor $packageCachePath
    Assert-DisjointRoots @($game, $profiles, $states, $packageCachePath)
    if ([IO.Path]::GetPathRoot($profiles) -cne [IO.Path]::GetPathRoot($states)) {
        throw 'ProfileRoot and StateDirectory must be on the same volume for recoverable rollback.'
    }
}
Assert-NoReparseAncestor $manifestPath
$catalogPath = Get-NormalizedPath (Join-Path $PSScriptRoot '..\references\laptop-package-catalog.json')
$catalog = Read-PackageCatalog $catalogPath
$manifest = Read-CanonicalManifest $manifestPath $catalog

if ($AuditOnly) { New-Audit $manifest $catalog 'auditOnly' $game $profiles $tools | ConvertTo-Json -Depth 10 -Compress }
elseif ($Plan) { $audit = New-Audit $manifest $catalog 'plan' $game $profiles $tools; New-Plan $manifest $catalog $audit $profiles | ConvertTo-Json -Depth 10 -Compress }
elseif ($Apply) { $result = Invoke-ApplyTransaction $manifest $catalog $manifestPath $profiles $states $packageCachePath $ArchiveToolPath; if ($null -ne $result) { $result | ConvertTo-Json -Depth 12 -Compress } }
elseif ($Verify) { New-Audit $manifest $catalog 'verify' $game $profiles $tools | ConvertTo-Json -Depth 10 -Compress }
elseif ($Rollback) { $result = Invoke-RollbackTransaction $manifest $catalog $manifestPath $profiles $states; if ($null -ne $result) { $result | ConvertTo-Json -Depth 12 -Compress } }
