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

    [ValidateSet('journalCreated', 'stageCreated', 'payloadExtracted', 'payloadVerified', 'directoryPublishedBeforeStatus', 'filePublishIntent', 'filePublishedBeforeStatus', 'profilePublishIntent', 'profilePublishedBeforeStatus', 'profilePublished')]
    [string]$InterruptAfter,

    [ValidateRange(-1, 4096)]
    [int]$InterruptMutationIndex = -1,

    [switch]$ConfirmApply
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
    if ($policy.operation -cne 'verifiedPackageIntake' -or $policy.componentMutation -ne $false -or
        $policy.mutationStatus -cne 'deferredPendingNativeWindowsHandleRelativeWriterAndOsProtectedJournal' -or
        @($policy.allowedArchiveTypes).Count -ne 1 -or $policy.allowedArchiveTypes[0] -cne '7z' -or
        $policy.networkAccess -ne $false -or $policy.executePayloads -ne $false) {
        throw 'Trusted package catalog policy must describe read-only verified intake with component mutation deferred.'
    }
    $archiveTool = Get-RequiredProperty $policy 'archiveTool' 'Trusted package policy'
    foreach ($name in @('fileName', 'version', 'sha256')) { [void](Get-RequiredProperty $archiveTool $name 'Trusted archive tool') }
    if ($archiveTool.fileName -cne '7z.exe' -or $archiveTool.version -cne '26.02' -or $archiveTool.sha256 -cnotmatch '^[0-9a-f]{64}$') { throw 'Trusted archive tool identity is invalid.' }
    $map = @{}
    foreach ($package in @(Get-RequiredProperty $catalog 'packages' 'Trusted package catalog')) {
        foreach ($name in @('catalogId', 'component', 'version', 'gameRuntimeVersion', 'archiveFileName', 'archiveType', 'archiveBytes', 'archiveEntryCount', 'archiveSha256', 'mappings', 'prefixInventories', 'publisher', 'provenanceUrl', 'license', 'approved', 'free')) {
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
                throw 'Package source authorization must come from the trusted catalog.'
            }
            $catalogId = [string](Get-RequiredProperty $item 'catalogId' 'Canonical approvedShared item')
            if (-not $Catalog.byId.ContainsKey($catalogId)) { throw 'Canonical package is not in the trusted catalog.' }
            $trusted = $Catalog.byId[$catalogId]
            $mappingKey = ('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()
            if (-not $trusted.mappingByDestination.ContainsKey($mappingKey)) { throw 'Canonical package path is not an approved catalog mapping.' }
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

function Initialize-PhysicalIdentityApi {
    if ('SkyrimEngineering.DirectoryLease' -as [type]) { return }
    Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace SkyrimEngineering {
    public sealed class DirectoryLease : IDisposable {
        const uint FILE_READ_ATTRIBUTES = 0x80;
        const uint DELETE = 0x00010000;
        const uint FILE_SHARE_READ = 1;
        const uint FILE_SHARE_WRITE = 2;
        const uint FILE_SHARE_DELETE = 4;
        const uint OPEN_EXISTING = 3;
        const uint FILE_FLAG_BACKUP_SEMANTICS = 0x02000000;
        const uint FILE_FLAG_OPEN_REPARSE_POINT = 0x00200000;
        const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x400;

        [StructLayout(LayoutKind.Sequential)]
        struct BY_HANDLE_FILE_INFORMATION {
            public uint FileAttributes;
            public System.Runtime.InteropServices.ComTypes.FILETIME CreationTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastAccessTime;
            public System.Runtime.InteropServices.ComTypes.FILETIME LastWriteTime;
            public uint VolumeSerialNumber;
            public uint FileSizeHigh;
            public uint FileSizeLow;
            public uint NumberOfLinks;
            public uint FileIndexHigh;
            public uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern SafeFileHandle CreateFileW(string name, uint access, uint share, IntPtr security, uint creation, uint flags, IntPtr template);
        [DllImport("kernel32.dll", SetLastError=true)]
        static extern bool GetFileInformationByHandle(SafeFileHandle handle, out BY_HANDLE_FILE_INFORMATION info);
        [DllImport("kernel32.dll", CharSet=CharSet.Unicode, SetLastError=true)]
        static extern uint GetFinalPathNameByHandleW(SafeFileHandle handle, StringBuilder path, uint size, uint flags);

        SafeFileHandle handle;
        public string Identity { get; private set; }
        public string VolumeIdentity { get; private set; }
        public string FinalPath { get; private set; }

        DirectoryLease(SafeFileHandle value, string identity, string volumeIdentity, string finalPath) {
            handle = value; Identity = identity; VolumeIdentity = volumeIdentity; FinalPath = NormalizeFinalPath(finalPath);
        }

        static string NormalizeFinalPath(string path) {
            string value = path.Replace('/', '\\');
            while (value.Length > 7 && value.EndsWith("\\", StringComparison.Ordinal)) value = value.Substring(0, value.Length - 1);
            return value;
        }

        static string ExpectedFinalPath(string path) {
            string full = Path.GetFullPath(path);
            if (!full.StartsWith(@"\\?\", StringComparison.Ordinal)) full = @"\\?\" + full;
            return NormalizeFinalPath(full);
        }

        static DirectoryLease OpenCore(string path, bool directory, bool permitDeleteShare) {
            uint share = FILE_SHARE_READ | FILE_SHARE_WRITE | (permitDeleteShare ? FILE_SHARE_DELETE : 0);
            uint flags = FILE_FLAG_OPEN_REPARSE_POINT | (directory ? FILE_FLAG_BACKUP_SEMANTICS : 0);
            uint access = FILE_READ_ATTRIBUTES | ((directory && !permitDeleteShare) ? DELETE : 0);
            SafeFileHandle value = CreateFileW(path, access, share, IntPtr.Zero, OPEN_EXISTING, flags, IntPtr.Zero);
            if (value.IsInvalid) throw new Win32Exception(Marshal.GetLastWin32Error(), "Could not open a physical-identity handle.");
            BY_HANDLE_FILE_INFORMATION info;
            if (!GetFileInformationByHandle(value, out info)) { int error = Marshal.GetLastWin32Error(); value.Dispose(); throw new Win32Exception(error); }
            if ((info.FileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) != 0) { value.Dispose(); throw new IOException("A reparse-point mutation target was refused."); }
            StringBuilder buffer = new StringBuilder(1024);
            uint length = GetFinalPathNameByHandleW(value, buffer, (uint)buffer.Capacity, 0);
            if (length == 0 || length >= buffer.Capacity) { int error = Marshal.GetLastWin32Error(); value.Dispose(); throw new Win32Exception(error, "Could not resolve a physical path."); }
            ulong index = ((ulong)info.FileIndexHigh << 32) | info.FileIndexLow;
            string volumeIdentity = info.VolumeSerialNumber.ToString("x8");
            string identity = volumeIdentity + ":" + index.ToString("x16");
            return new DirectoryLease(value, identity, volumeIdentity, buffer.ToString());
        }

        public static DirectoryLease Open(string path) { return OpenCore(path, true, false); }
        public static DirectoryLease OpenRoot(string path) {
            DirectoryLease root = OpenCore(path, true, true);
            if (!String.Equals(root.FinalPath, ExpectedFinalPath(path), StringComparison.OrdinalIgnoreCase)) {
                root.Dispose();
                throw new IOException("The explicit root did not resolve to its anchored physical path.");
            }
            return root;
        }
        public static DirectoryLease OpenContained(string path, DirectoryLease root) {
            DirectoryLease current = OpenCore(path, true, false);
            try { current.AssertContainedBy(root); return current; }
            catch { current.Dispose(); throw; }
        }
        public static string ReadFileIdentity(string path) { using (DirectoryLease lease = OpenCore(path, false, true)) { return lease.Identity; } }
        public static string ReadDirectoryIdentity(string path) { using (DirectoryLease lease = OpenCore(path, true, true)) { return lease.Identity; } }
        public static string ReadFileIdentityContained(string path, DirectoryLease root) {
            using (DirectoryLease lease = OpenCore(path, false, true)) { lease.AssertContainedBy(root); return lease.Identity; }
        }
        public static string ReadDirectoryIdentityContained(string path, DirectoryLease root) {
            using (DirectoryLease lease = OpenCore(path, true, true)) { lease.AssertContainedBy(root); return lease.Identity; }
        }
        public void AssertContainedBy(DirectoryLease root) {
            string rootPath = NormalizeFinalPath(root.FinalPath);
            string childPath = NormalizeFinalPath(FinalPath);
            if (!String.Equals(VolumeIdentity, root.VolumeIdentity, StringComparison.Ordinal) ||
                (!String.Equals(childPath, rootPath, StringComparison.OrdinalIgnoreCase) &&
                 !childPath.StartsWith(rootPath + "\\", StringComparison.OrdinalIgnoreCase)))
                throw new IOException("Opened mutation parent is outside the anchored physical root.");
        }
        public void AssertPathStillSame(string path) {
            using (DirectoryLease current = OpenCore(path, true, true)) {
                if (!String.Equals(Identity, current.Identity, StringComparison.Ordinal) || !String.Equals(FinalPath, current.FinalPath, StringComparison.OrdinalIgnoreCase))
                    throw new IOException("Mutation parent physical identity changed.");
            }
        }
        public void Dispose() { if (handle != null) { handle.Dispose(); handle = null; } }
    }
}
'@
}

function Get-PhysicalRootAnchor {
    param([string]$Path)
    $candidate = Get-NormalizedPath $Path
    $best = $null
    foreach ($entry in @($script:PhysicalRootAnchors)) {
        if ([string]::Equals($candidate, $entry.path, [StringComparison]::OrdinalIgnoreCase) -or
            $candidate.StartsWith($entry.path + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            if ($null -eq $best -or $entry.path.Length -gt $best.path.Length) { $best = $entry }
        }
    }
    if ($null -eq $best) { throw 'Mutation path has no anchored physical root.' }
    return $best.lease
}

function Open-PhysicalRootAnchor {
    param([string]$Path)
    Initialize-PhysicalIdentityApi
    return [SkyrimEngineering.DirectoryLease]::OpenRoot((Get-NormalizedPath $Path))
}

function Open-DirectoryLease {
    param([string]$Path, $RootAnchor)
    Assert-NoReparseAncestor $Path
    Initialize-PhysicalIdentityApi
    if ($null -eq $RootAnchor) { $RootAnchor = Get-PhysicalRootAnchor $Path }
    return [SkyrimEngineering.DirectoryLease]::OpenContained((Get-NormalizedPath $Path), $RootAnchor)
}

function Get-FilePhysicalIdentity {
    param([string]$Path, $RootAnchor)
    Assert-NoReparseAncestor $Path
    Initialize-PhysicalIdentityApi
    if ($null -eq $RootAnchor) { $RootAnchor = Get-PhysicalRootAnchor $Path }
    return [SkyrimEngineering.DirectoryLease]::ReadFileIdentityContained((Get-NormalizedPath $Path), $RootAnchor)
}

function Get-DirectoryPhysicalIdentity {
    param([string]$Path, $RootAnchor)
    Assert-NoReparseAncestor $Path
    Initialize-PhysicalIdentityApi
    if ($null -eq $RootAnchor) { $RootAnchor = Get-PhysicalRootAnchor $Path }
    return [SkyrimEngineering.DirectoryLease]::ReadDirectoryIdentityContained((Get-NormalizedPath $Path), $RootAnchor)
}

function Invoke-GuardedFileMove {
    param([string]$Source, [string]$Destination)
    $sourceParent = Split-Path -Parent $Source
    $destinationParent = Split-Path -Parent $Destination
    $sourceLease = Open-DirectoryLease $sourceParent
    $sameParent = [string]::Equals((Get-NormalizedPath $sourceParent), (Get-NormalizedPath $destinationParent), [StringComparison]::OrdinalIgnoreCase)
    $destinationLease = if ($sameParent) { $sourceLease } else { Open-DirectoryLease $destinationParent }
    try {
        if (-not (Test-Path -LiteralPath $Source -PathType Leaf) -or (Test-Path -LiteralPath $Destination)) { throw 'Guarded file publication requires an existing source and a fresh destination.' }
        $sourceLease.AssertPathStillSame($sourceParent)
        $destinationLease.AssertPathStillSame($destinationParent)
        [IO.File]::Move($Source, $Destination)
        $sourceLease.AssertPathStillSame($sourceParent)
        $destinationLease.AssertPathStillSame($destinationParent)
    }
    finally { if (-not $sameParent) { $destinationLease.Dispose() }; $sourceLease.Dispose() }
}

function Invoke-GuardedDirectoryMove {
    param([string]$Source, [string]$Destination)
    $sourceParent = Split-Path -Parent $Source
    $destinationParent = Split-Path -Parent $Destination
    $sourceLease = Open-DirectoryLease $sourceParent
    $sameParent = [string]::Equals((Get-NormalizedPath $sourceParent), (Get-NormalizedPath $destinationParent), [StringComparison]::OrdinalIgnoreCase)
    $destinationLease = if ($sameParent) { $sourceLease } else { Open-DirectoryLease $destinationParent }
    try {
        if (-not (Test-Path -LiteralPath $Source -PathType Container) -or (Test-Path -LiteralPath $Destination)) { throw 'Guarded directory publication requires an existing source and a fresh destination.' }
        $sourceLease.AssertPathStillSame($sourceParent)
        $destinationLease.AssertPathStillSame($destinationParent)
        [IO.Directory]::Move($Source, $Destination)
        $sourceLease.AssertPathStillSame($sourceParent)
        $destinationLease.AssertPathStillSame($destinationParent)
    }
    finally { if (-not $sameParent) { $destinationLease.Dispose() }; $sourceLease.Dispose() }
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
            requiredCapabilities = @('nativeWindowsHandleRelativeWriter', 'osProtectedJournal')
        }
        differences = $Audit.differences
    }
}

function Get-ExpectedMutations {
    param($Manifest, $Catalog)
    $directories = @{ 'profile|Anniversary Together' = [pscustomobject]@{ root = 'profile'; relativePath = 'Anniversary Together' } }
    $files = New-Object Collections.ArrayList
    foreach ($package in @(Get-TrustedPackages $Manifest $Catalog)) {
        foreach ($mapping in @($package.mappings)) {
            $relative = [string]$mapping.destinationRelativePath
            $parent = [IO.Path]::GetDirectoryName($relative.Replace('/', [IO.Path]::DirectorySeparatorChar))
            while (-not [string]::IsNullOrEmpty($parent)) {
                $portable = Convert-ToPortablePath $parent
                $directoryKey = ('{0}|{1}' -f $mapping.destinationRoot, $portable).ToLowerInvariant()
                $directories[$directoryKey] = [pscustomobject]@{ root = [string]$mapping.destinationRoot; relativePath = $portable }
                $parent = [IO.Path]::GetDirectoryName($parent)
            }
            [void]$files.Add([pscustomobject][ordered]@{ type = 'createFile'; root = [string]$mapping.destinationRoot; relativePath = $relative; bytes = [long]$mapping.bytes; sha256 = [string]$mapping.sha256; catalogId = [string]$package.catalogId; preExisting = $false; preMutationIdentity = $null; status = 'planned'; sourceRelativePath = $null; fileIdentity = $null })
        }
    }
    $mutations = New-Object Collections.ArrayList
    foreach ($directory in @($directories.Values | Sort-Object root, { ($_.relativePath -split '/').Count }, relativePath)) {
        [void]$mutations.Add([pscustomobject][ordered]@{ type = 'createDirectory'; root = [string]$directory.root; relativePath = [string]$directory.relativePath; bytes = $null; sha256 = $null; catalogId = $null; preExisting = $false; preMutationIdentity = $null; status = 'planned'; sourceRelativePath = $null; fileIdentity = $null })
    }
    foreach ($file in @($files | Sort-Object root, relativePath)) { [void]$mutations.Add($file) }
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
    $parent = Split-Path -Parent $StatePath
    $lease = Open-DirectoryLease $parent
    try {
        Write-BytesExclusively $next $bytes
        $nextIdentity = Get-FilePhysicalIdentity $next
        $lease.AssertPathStillSame($parent)
    }
    finally { $lease.Dispose() }
    try {
        if ($CreateNew) {
            if (Test-Path -LiteralPath $StatePath) { throw 'Client state journal already exists.' }
            Invoke-GuardedFileMove $next $StatePath
        }
        else {
            $replaceLease = Open-DirectoryLease $parent
            $backup = $StatePath + '.' + $transactionId + '.backup'
            try {
                if (-not (Test-Path -LiteralPath $StatePath -PathType Leaf) -or (Test-Path -LiteralPath $backup)) { throw 'Client state journal replacement paths are not in the expected fresh state.' }
                $replaceLease.AssertPathStillSame($parent)
                [IO.File]::Replace($next, $StatePath, $backup)
                $replaceLease.AssertPathStillSame($parent)
                if (Test-Path -LiteralPath $backup -PathType Leaf) {
                    $backupIdentity = Get-FilePhysicalIdentity $backup
                    if ((Get-FilePhysicalIdentity $backup) -ceq $backupIdentity) { [IO.File]::Delete($backup) }
                    $replaceLease.AssertPathStillSame($parent)
                }
            }
            finally { $replaceLease.Dispose() }
        }
    }
    finally {
        if ((Test-Path -LiteralPath $next -PathType Leaf) -and (Get-FilePhysicalIdentity $next) -ceq $nextIdentity) {
            $cleanupLease = Open-DirectoryLease $parent
            try { $cleanupLease.AssertPathStillSame($parent); [IO.File]::Delete($next); $cleanupLease.AssertPathStillSame($parent) }
            finally { $cleanupLease.Dispose() }
        }
    }
}

function Get-PreflightOwnershipSha256 {
    param($Mutations)
    $facts = @($Mutations | ForEach-Object {
        [pscustomobject][ordered]@{
            type = [string]$_.type; root = [string]$_.root; relativePath = [string]$_.relativePath
            bytes = $_.bytes; sha256 = $_.sha256; catalogId = $_.catalogId
            preExisting = [bool]$_.preExisting; preMutationIdentity = $_.preMutationIdentity
        }
    })
    $bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($facts | ConvertTo-Json -Depth 6 -Compress))
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try { return (($algorithm.ComputeHash($bytes) | ForEach-Object { $_.ToString('x2') }) -join '') }
    finally { $algorithm.Dispose() }
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
    param([string]$Boundary, [int]$MutationIndex = -1)
    if ($InterruptAfter -ceq $Boundary -and ($InterruptMutationIndex -lt 0 -or $InterruptMutationIndex -eq $MutationIndex)) {
        throw "simulated interruption after $Boundary"
    }
}

function Remove-OwnedStage {
    param($State, [string]$States)
    $expectedRelative = '.skyrim-engineering-stage-' + [string]$State.transactionId
    if ($State.stagingRelativePath -cne $expectedRelative -or $State.ownershipToken -cnotmatch '^[a-f0-9]{64}$') { throw 'Journal staging ownership identity is invalid.' }
    $stage = Join-Path $States $expectedRelative
    Assert-ContainedPath $States $stage
    if (-not (Test-Path -LiteralPath $stage -PathType Container)) { return }
    Assert-NoReparseTree $stage
    $marker = Join-Path $stage '.skyrim-engineering-owner'
    if (-not (Test-Path -LiteralPath $marker -PathType Leaf) -or (Get-Content -LiteralPath $marker -Raw) -cne $State.ownershipToken) { throw 'Staging ownership marker does not match the journal.' }
    $lease = Open-DirectoryLease $States
    try {
        $lease.AssertPathStillSame($States)
        Remove-Item -LiteralPath $stage -Recurse -Force
        $lease.AssertPathStillSame($States)
    }
    finally { $lease.Dispose() }
}

function Get-MutationPath {
    param($Mutation, [string]$Game, [string]$Profiles)
    $base = if ($Mutation.root -ceq 'game') { $Game } elseif ($Mutation.root -ceq 'profile') { $Profiles } else { throw 'Mutation root is not allowlisted.' }
    $path = Join-Path $base ([string]$Mutation.relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
    Assert-ContainedPath $base $path
    return $path
}

function Set-MutationPreflight {
    param($Mutation, [string]$Game, [string]$Profiles)
    $path = Get-MutationPath $Mutation $Game $Profiles
    Assert-NoReparseAncestor $path
    if ($Mutation.type -ceq 'createDirectory') {
        if (Test-Path -LiteralPath $path -PathType Container) {
            $Mutation.preExisting = $true
            $Mutation.preMutationIdentity = Get-DirectoryPhysicalIdentity $path
            $Mutation.status = 'preExisting'
            $Mutation.fileIdentity = $Mutation.preMutationIdentity
        }
        elseif (Test-Path -LiteralPath $path) { throw 'An existing non-directory destination was refused.' }
    }
    else {
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $item = Get-Item -LiteralPath $path -Force
            if ($item.Length -ne [long]$Mutation.bytes -or (Get-LowerHash $path) -cne $Mutation.sha256) {
                throw 'An existing SKSE destination has a different hash; Apply must refuse overwrite.'
            }
            $Mutation.preExisting = $true
            $Mutation.preMutationIdentity = Get-FilePhysicalIdentity $path
            $Mutation.status = 'preExisting'
            $Mutation.fileIdentity = $Mutation.preMutationIdentity
        }
        elseif (Test-Path -LiteralPath $path) { throw 'An existing non-file SKSE destination was refused.' }
    }
}

function New-GuardedDirectory {
    param([string]$Path)
    $parent = Split-Path -Parent $Path
    $lease = Open-DirectoryLease $parent
    try {
        if (Test-Path -LiteralPath $Path) { throw 'A fresh directory destination was occupied before creation.' }
        $lease.AssertPathStillSame($parent)
        [void][IO.Directory]::CreateDirectory($Path)
        $lease.AssertPathStillSame($parent)
        Assert-NoReparseAncestor $Path
    }
    finally { $lease.Dispose() }
}

function Invoke-ApplyTransaction {
    param($Manifest, $Catalog, [string]$ManifestPath, [string]$Game, [string]$Profiles, [string]$States, [string]$Cache, [string]$Tool)
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
    $mutations = @(Get-ExpectedMutations $Manifest $Catalog)
    foreach ($mutation in $mutations) { Set-MutationPreflight $mutation $Game $Profiles }
    $transactionId = [guid]::NewGuid().ToString('N')
    $ownershipBytes = New-Object byte[] 32
    [Security.Cryptography.RandomNumberGenerator]::Fill($ownershipBytes)
    $ownershipToken = ($ownershipBytes | ForEach-Object { $_.ToString('x2') }) -join ''
    $stageRelative = '.skyrim-engineering-stage-' + $transactionId
    $preflightOwnershipSha256 = Get-PreflightOwnershipSha256 $mutations
    $state = [pscustomobject][ordered]@{ schema = 'skyrim-engineering.laptop-state/v1'; clientId = $ClientId; status = 'applying'; phase = 'journalCreated'; operation = 'approved7zInstall'; transactionId = $transactionId; stagingRelativePath = $stageRelative; ownershipToken = $ownershipToken; preflightOwnershipSha256 = $preflightOwnershipSha256; manifestSha256 = Get-LowerHash $ManifestPath; catalogSha256 = $Catalog.sha256; mutations = $mutations }
    Write-StateAtomic $state $statePath -CreateNew
    Test-QualificationInterrupt 'journalCreated'
    try {
        $stage = Join-Path $States $stageRelative
        Assert-NoReparseAncestor $States
        if (Test-Path -LiteralPath $stage) { throw 'Transaction staging path unexpectedly exists.' }
        New-GuardedDirectory $stage
        Write-BytesExclusively (Join-Path $stage '.skyrim-engineering-owner') ((New-Object Text.UTF8Encoding($false)).GetBytes($ownershipToken))
        $publishProfile = Join-Path $stage 'profile-publish'
        New-GuardedDirectory $publishProfile
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
        $mappingByDestination = @{}
        foreach ($mapping in @($package.mappings)) {
            $source = Join-Path $extractRoot ([string]$mapping.archivePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
            if (-not (Test-Path -LiteralPath $source -PathType Leaf) -or (Get-Item $source).Length -ne [long]$mapping.bytes -or (Get-LowerHash $source) -cne $mapping.sha256) { throw 'Extracted SKSE payload failed its pinned hash or size.' }
            $mappingByDestination[(('{0}|{1}' -f $mapping.destinationRoot, $mapping.destinationRelativePath).ToLowerInvariant())] = [pscustomobject]@{ mapping = $mapping; source = $source }
            $mutation = @($state.mutations | Where-Object { $_.type -eq 'createFile' -and $_.root -ceq $mapping.destinationRoot -and $_.relativePath -ceq $mapping.destinationRelativePath })[0]
            if ($mutation.status -ceq 'planned') {
                $mutation.sourceRelativePath = Convert-ToPortablePath $source.Substring($stage.Length + 1)
                $mutation.fileIdentity = Get-FilePhysicalIdentity $source
                $mutation.status = 'staged'
            }
        }
        $state.phase = 'payloadVerified'; Write-StateAtomic $state $statePath
        Test-QualificationInterrupt 'payloadVerified'

        $directoryIntentRoot = Join-Path $stage 'directory-intents'
        New-GuardedDirectory $directoryIntentRoot
        $directoryIndex = 0
        foreach ($mutation in @($state.mutations | Where-Object { $_.type -eq 'createDirectory' -and $_.root -eq 'game' -and $_.status -eq 'planned' } | Sort-Object { ($_.relativePath -split '/').Count }, relativePath)) {
            $sourceRelativePath = 'directory-intents/' + $directoryIndex.ToString('0000')
            $sourcePath = Join-Path $stage $sourceRelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
            New-GuardedDirectory $sourcePath
            $mutation.sourceRelativePath = $sourceRelativePath
            $mutation.fileIdentity = Get-DirectoryPhysicalIdentity $sourcePath
            $mutation.status = 'publishing'; Write-StateAtomic $state $statePath
            $path = Get-MutationPath $mutation $Game $Profiles
            Invoke-GuardedDirectoryMove $sourcePath $path
            Test-QualificationInterrupt 'directoryPublishedBeforeStatus' $directoryIndex
            if ((Get-DirectoryPhysicalIdentity $path) -cne $mutation.fileIdentity) { throw 'Published game directory identity changed.' }
            $mutation.status = 'complete'; Write-StateAtomic $state $statePath
            $directoryIndex++
        }

        $publishIndex = 0
        foreach ($mutation in @($state.mutations | Where-Object type -eq 'createFile' | Sort-Object root, relativePath)) {
            if ($mutation.status -ceq 'staged') {
                $source = Join-Path $stage ([string]$mutation.sourceRelativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
                $destination = Get-MutationPath $mutation $Game $Profiles
                $mutation.status = 'publishing'; Write-StateAtomic $state $statePath
                Test-QualificationInterrupt 'filePublishIntent' $publishIndex
                Invoke-GuardedFileMove $source $destination
                Test-QualificationInterrupt 'filePublishedBeforeStatus' $publishIndex
                if ((Get-FilePhysicalIdentity $destination) -cne $mutation.fileIdentity -or (Get-LowerHash $destination) -cne $mutation.sha256) { throw 'Published SKSE file identity or hash changed.' }
                $mutation.status = 'complete'; Write-StateAtomic $state $statePath
            }
            $publishIndex++
        }

        $profileMutation = @($state.mutations | Where-Object { $_.type -eq 'createDirectory' -and $_.root -eq 'profile' -and $_.relativePath -eq 'Anniversary Together' })[0]
        $profileMutation.sourceRelativePath = Convert-ToPortablePath $publishProfile.Substring($stage.Length + 1)
        $profileMutation.fileIdentity = Get-DirectoryPhysicalIdentity $publishProfile
        $profileMutation.status = 'publishing'; Write-StateAtomic $state $statePath
        Test-QualificationInterrupt 'profilePublishIntent'
        Invoke-GuardedDirectoryMove $publishProfile $profile
        Test-QualificationInterrupt 'profilePublishedBeforeStatus'
        if ((Get-DirectoryPhysicalIdentity $profile) -cne $profileMutation.fileIdentity) { throw 'Published profile identity changed.' }
        $profileMutation.status = 'complete'
        $state.phase = 'profilePublished'; Write-StateAtomic $state $statePath
        Test-QualificationInterrupt 'profilePublished'
        Remove-OwnedStage $state $States
        $state.phase = 'cleanupComplete'; $state.status = 'applied'; Write-StateAtomic $state $statePath
        return $state
    }
    catch { throw ('Apply stopped in recoverable applying state. Run Rollback with the same manifest and roots. {0}' -f $_.Exception.Message) }
}

function Assert-JournalAllowlist {
    param($State, $Manifest, $Catalog, [string]$ManifestPath)
    if ($State.schema -cne 'skyrim-engineering.laptop-state/v1' -or $State.clientId -cne $ClientId -or $State.status -cnotin @('applying', 'applied') -or
        $State.operation -cne 'approved7zInstall' -or $State.transactionId -cnotmatch '^[a-f0-9]{32}$' -or
        $State.stagingRelativePath -cne ('.skyrim-engineering-stage-' + [string]$State.transactionId) -or $State.ownershipToken -cnotmatch '^[a-f0-9]{64}$' -or $State.preflightOwnershipSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $State.phase -cnotin @('journalCreated', 'stageCreated', 'payloadExtracted', 'payloadVerified', 'profilePublished', 'cleanupComplete') -or
        $State.manifestSha256 -cne (Get-LowerHash $ManifestPath) -or $State.catalogSha256 -cne $Catalog.sha256) {
        throw 'State journal identity or trusted manifest binding is invalid.'
    }
    $expected = @(Get-ExpectedMutations $Manifest $Catalog)
    $actual = @($State.mutations)
    if ($actual.Count -ne $expected.Count) { throw 'State journal mutation set does not match the trusted allowlist.' }
    if ((Get-PreflightOwnershipSha256 $actual) -cne $State.preflightOwnershipSha256) { throw 'State journal preflight ownership binding is invalid.' }
    $seen = @{}
    for ($index = 0; $index -lt $expected.Count; $index++) {
        $want = $expected[$index]; $have = $actual[$index]
        $key = ('{0}|{1}' -f $have.type, $have.relativePath).ToLowerInvariant()
        if ($seen.ContainsKey($key) -or $have.type -cne $want.type -or $have.root -cne $want.root -or $have.relativePath -cne $want.relativePath -or
            [string]$have.bytes -cne [string]$want.bytes -or [string]$have.sha256 -cne [string]$want.sha256 -or [string]$have.catalogId -cne [string]$want.catalogId -or
            $have.status -cnotin @('planned', 'preExisting', 'creating', 'staged', 'publishing', 'complete')) {
            throw 'State journal contains duplicate, altered, or non-allowlisted mutations.'
        }
        if (($have.preExisting -eq $true -and ($have.status -cne 'preExisting' -or [string]$have.preMutationIdentity -cne [string]$have.fileIdentity)) -or
            ($have.preExisting -ne $true -and ($have.status -ceq 'preExisting' -or $null -ne $have.preMutationIdentity))) {
            throw 'State journal ownership lifecycle conflicts with independently bound pre-mutation facts.'
        }
        $seen[$key] = $true
    }
    return $actual
}

function Move-Verify-DeleteFile {
    param([string]$Path, [string]$ExpectedHash, [string]$ExpectedIdentity, [string]$Quarantine)
    Assert-NoReparseAncestor $Path
    if (Test-Path -LiteralPath $Quarantine) { throw 'Rollback quarantine path is unexpectedly occupied.' }
    if ((Get-LowerHash $Path) -cne $ExpectedHash) { throw 'A journaled file hash no longer matches; rollback refused deletion.' }
    if ((Get-FilePhysicalIdentity $Path) -cne $ExpectedIdentity) { throw 'A journaled file physical identity no longer matches; rollback refused deletion.' }
    Invoke-GuardedFileMove $Path $Quarantine
    if ((Get-LowerHash $Quarantine) -cne $ExpectedHash -or (Get-FilePhysicalIdentity $Quarantine) -cne $ExpectedIdentity) { throw 'Rollback quarantine ownership verification failed.' }
    $parent = Split-Path -Parent $Quarantine
    $lease = Open-DirectoryLease $parent
    try { $lease.AssertPathStillSame($parent); [IO.File]::Delete($Quarantine); $lease.AssertPathStillSame($parent) }
    finally { $lease.Dispose() }
}

function Invoke-RollbackTransaction {
    param($Manifest, $Catalog, [string]$ManifestPath, [string]$Game, [string]$Profiles, [string]$States)
    $statePath = Join-Path $States ($ClientId + '.state.json')
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'No journaled state exists for this client.' }
    if (-not $PSCmdlet.ShouldProcess('Anniversary Together', 'Rollback only the trusted manifest-derived mutation allowlist')) { return }
    Assert-NoReparseAncestor $statePath
    $state = Read-JsonFile $statePath 'Client state journal'
    $mutations = @(Assert-JournalAllowlist $state $Manifest $Catalog $ManifestPath)
    Remove-OwnedStage $state $States
    foreach ($mutation in @($mutations | Where-Object { $_.type -eq 'createFile' -and $_.preExisting -ne $true -and $_.status -in @('publishing', 'complete') } | Sort-Object root, relativePath -Descending)) {
        $path = Get-MutationPath $mutation $Game $Profiles
        if (Test-Path -LiteralPath $path -PathType Leaf) {
            $quarantine = Join-Path $States ('.' + $ClientId + '.' + [guid]::NewGuid().ToString('N') + '.rollback.tmp')
            Move-Verify-DeleteFile $path ([string]$mutation.sha256) ([string]$mutation.fileIdentity) $quarantine
        }
    }
    foreach ($mutation in @($mutations | Where-Object { $_.type -eq 'createDirectory' -and $_.preExisting -ne $true -and $_.status -in @('publishing', 'complete') } | Sort-Object { ([string]$_.relativePath).Length } -Descending)) {
        $path = Get-MutationPath $mutation $Game $Profiles
        Assert-NoReparseAncestor $path
        if ((Test-Path -LiteralPath $path -PathType Container) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0 -and (Get-DirectoryPhysicalIdentity $path) -ceq $mutation.fileIdentity) {
            $parent = Split-Path -Parent $path
            $lease = Open-DirectoryLease $parent
            try { $lease.AssertPathStillSame($parent); [IO.Directory]::Delete($path); $lease.AssertPathStillSame($parent) }
            finally { $lease.Dispose() }
        }
    }
    $state.status = 'rolledBack'
    Write-StateAtomic $state $statePath
    return $state
}

$modeCount = @($AuditOnly, $Plan, $Apply, $Verify, $Rollback | Where-Object { $_ }).Count
if ($modeCount -ne 1) { throw 'Select exactly one mode: -AuditOnly, -Plan, -Apply, -Verify, or -Rollback.' }
if ($Apply -or $Rollback) {
    $requestedMode = if ($Apply) { 'Apply' } else { 'Rollback' }
    $deferred = [pscustomobject][ordered]@{
        schema = 'skyrim-engineering.laptop-deferred/v1'
        mode = $requestedMode
        status = 'deferred'
        message = 'Component Apply and Rollback are deferred for v0.1 pending a native Windows handle-relative writer and OS-protected journal. Use -AuditOnly, -Plan, or -Verify; make component changes manually outside this workflow.'
        requiredCapabilities = @('nativeWindowsHandleRelativeWriter', 'osProtectedJournal')
        supportedModes = @('AuditOnly', 'Plan', 'Verify')
    }
    throw ($deferred | ConvertTo-Json -Depth 4 -Compress)
}
if ($ConfirmApply -and -not $Apply) { throw '-ConfirmApply is valid only with -Apply.' }
if (-not [string]::IsNullOrWhiteSpace($InterruptAfter) -and -not $Apply) { throw '-InterruptAfter is valid only with -Apply qualification tests.' }
if ($InterruptMutationIndex -ge 0 -and ([string]::IsNullOrWhiteSpace($InterruptAfter) -or -not $Apply)) { throw '-InterruptMutationIndex requires an Apply interruption boundary.' }
foreach ($inputPath in @($GameRoot, $ProfileRoot, $CanonicalManifest, $StateDirectory)) { Assert-FullyQualifiedLocalPath $inputPath }
$game = Get-NormalizedPath $GameRoot
$profiles = Get-NormalizedPath $ProfileRoot
$manifestPath = Get-NormalizedPath $CanonicalManifest
$states = Get-NormalizedPath $StateDirectory
$script:PhysicalRootAnchors = New-Object Collections.ArrayList
try {
    foreach ($root in @($game, $profiles, $states)) {
        if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'GameRoot, ProfileRoot, and StateDirectory must be existing explicit directories.' }
        Assert-NoReparseAncestor $root
        $anchor = Open-PhysicalRootAnchor $root
        [void]$script:PhysicalRootAnchors.Add([pscustomobject]@{ path = $root; lease = $anchor })
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
}
finally {
    foreach ($entry in @($script:PhysicalRootAnchors)) { if ($null -ne $entry.lease) { $entry.lease.Dispose() } }
}
