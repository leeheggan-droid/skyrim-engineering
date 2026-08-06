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

    [switch]$ConfirmApply
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Get-RequiredProperty {
    param($InputObject, [string]$Name)
    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        throw "Canonical manifest is missing required property '$Name'."
    }
    return $property.Value
}

function Assert-SafeRelativePath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ([string]::IsNullOrWhiteSpace($Path) -or [IO.Path]::IsPathRooted($Path) -or
        $Path.Contains('\') -or $Path.Contains(':') -or $Path.StartsWith('/') -or
        $Path -match '(?i)(^|/)(\.\.?)(/|$)' -or $Path -match '(?i)(password|credential|secret|token|steamid)') {
        throw 'Manifest paths must be safe relative paths without secrets or personal locations.'
    }
    foreach ($segment in @($Path -split '/')) {
        if ([string]::IsNullOrWhiteSpace($segment)) {
            throw 'Manifest paths must be safe relative paths without empty segments.'
        }
    }
}

function Assert-ContainedPath {
    param([string]$Root, [string]$Candidate)
    $rootPath = Get-NormalizedPath -Path $Root
    $candidatePath = Get-NormalizedPath -Path $Candidate
    $prefix = $rootPath + [IO.Path]::DirectorySeparatorChar
    if (-not $candidatePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Resolved path escapes its explicit root.'
    }
}

function Assert-NoReparsePoint {
    param([string]$Root, [string]$Candidate)
    Assert-ContainedPath -Root $Root -Candidate $Candidate
    $rootPath = Get-NormalizedPath -Path $Root
    $candidatePath = Get-NormalizedPath -Path $Candidate
    $relative = $candidatePath.Substring($rootPath.Length).TrimStart([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $current = $rootPath
    foreach ($segment in @($relative -split '[\\/]')) {
        if ([string]::IsNullOrEmpty($segment)) { continue }
        $current = Join-Path $current $segment
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'A path boundary contains a reparse point and was refused.'
            }
        }
    }
}

function Convert-ToPortablePath {
    param([string]$Path)
    return $Path.Replace('\', '/')
}

function New-Difference {
    param([string]$RelativePath)
    return [pscustomobject][ordered]@{ relativePath = $RelativePath }
}

function Read-CanonicalManifest {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw 'CanonicalManifest must be an existing file.'
    }
    try {
        $manifest = Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw 'CanonicalManifest is not valid JSON.'
    }
    if ((Get-RequiredProperty -InputObject $manifest -Name 'schema') -cne 'skyrim-engineering.laptop-canonical/v1') {
        throw 'CanonicalManifest schema must be skyrim-engineering.laptop-canonical/v1.'
    }
    [void](Get-RequiredProperty -InputObject $manifest -Name 'runtimeVersion')
    $items = @(Get-RequiredProperty -InputObject $manifest -Name 'items')
    $loadOrder = @(Get-RequiredProperty -InputObject $manifest -Name 'loadOrder')
    $seen = @{}
    foreach ($item in $items) {
        foreach ($name in @('id', 'category', 'root', 'relativePath', 'sha256', 'version')) {
            [void](Get-RequiredProperty -InputObject $item -Name $name)
        }
        if ([string]$item.id -cnotmatch '^[a-z0-9][a-z0-9-]*$') {
            throw 'Canonical item ids must be anonymous lowercase identifiers.'
        }
        if ([string]$item.category -cnotin @('anniversaryBaseline', 'approvedShared')) {
            throw 'Canonical item category is not approved.'
        }
        if ([string]$item.root -cnotin @('game', 'profile')) {
            throw 'Canonical item root must be game or profile.'
        }
        Assert-SafeRelativePath -Path ([string]$item.relativePath)
        if ([string]$item.sha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'Canonical item SHA-256 must be pinned lowercase hexadecimal.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$item.version)) {
            throw 'Canonical item version must be pinned.'
        }
        $key = ('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()
        if ($seen.ContainsKey($key)) {
            throw 'Canonical manifest contains a duplicate item path.'
        }
        $seen[$key] = $true
        if ($item.category -eq 'approvedShared') {
            $approved = Get-RequiredProperty -InputObject $item -Name 'approved'
            $free = Get-RequiredProperty -InputObject $item -Name 'free'
            $sourceRelativePath = [string](Get-RequiredProperty -InputObject $item -Name 'sourceRelativePath')
            if ($approved -isnot [bool] -or -not $approved -or $free -isnot [bool] -or -not $free) {
                throw 'Only explicitly approved free packages are permitted.'
            }
            Assert-SafeRelativePath -Path $sourceRelativePath
            if ($item.root -ne 'profile') {
                throw 'Approved shared packages may target only the isolated profile.'
            }
        }
    }
    foreach ($entry in $loadOrder) {
        if ($entry -isnot [string]) { throw 'Canonical load order entries must be strings.' }
        Assert-SafeRelativePath -Path ([string]$entry)
    }
    return $manifest
}

function Get-FileVersionMap {
    param([string]$Root)
    $map = @{}
    $path = Join-Path $Root 'versions.json'
    if (Test-Path -LiteralPath $path -PathType Leaf) {
        try { $versions = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -ErrorAction Stop }
        catch { throw 'The local versions.json metadata is invalid.' }
        foreach ($property in $versions.PSObject.Properties) {
            Assert-SafeRelativePath -Path ([string]$property.Name)
            $map[$property.Name.ToLowerInvariant()] = [string]$property.Value
        }
    }
    return $map
}

function Get-Inventory {
    param($Manifest, [string]$Game, [string]$Profiles)
    $expected = @{}
    foreach ($item in @($Manifest.items)) {
        $expected[('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()] = $item
    }
    $versions = Get-FileVersionMap -Root $Game
    $inventory = New-Object System.Collections.ArrayList
    $dataRoot = Join-Path $Game 'Data'
    if (Test-Path -LiteralPath $dataRoot -PathType Container) {
        foreach ($file in @(Get-ChildItem -LiteralPath $dataRoot -File -Recurse -Force | Sort-Object FullName)) {
            Assert-NoReparsePoint -Root $Game -Candidate $file.FullName
            $relative = Convert-ToPortablePath -Path $file.FullName.Substring((Get-NormalizedPath -Path $Game).Length + 1)
            $key = ('game|{0}' -f $relative).ToLowerInvariant()
            $version = $null
            if ($versions.ContainsKey($relative.ToLowerInvariant())) { $version = $versions[$relative.ToLowerInvariant()] }
            [void]$inventory.Add([pscustomobject]@{
                root = 'game'; relativePath = $relative; sha256 = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                version = $version; expected = $(if ($expected.ContainsKey($key)) { $expected[$key] } else { $null })
            })
        }
    }
    $profilePath = Join-Path $Profiles 'Anniversary Together'
    $profilePathNormalized = Get-NormalizedPath -Path $profilePath
    foreach ($file in @(Get-ChildItem -LiteralPath $Profiles -File -Recurse -Force | Sort-Object FullName)) {
        Assert-NoReparsePoint -Root $Profiles -Candidate $file.FullName
        $full = Get-NormalizedPath -Path $file.FullName
        if ($full.StartsWith($profilePathNormalized + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) {
            $relative = Convert-ToPortablePath -Path $full.Substring($profilePathNormalized.Length + 1)
        }
        else {
            $relative = Convert-ToPortablePath -Path $full.Substring((Get-NormalizedPath -Path $Profiles).Length + 1)
        }
        $key = ('profile|{0}' -f $relative).ToLowerInvariant()
        $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $version = $null
        if ($expected.ContainsKey($key) -and $expected[$key].sha256 -ceq $hash) { $version = [string]$expected[$key].version }
        [void]$inventory.Add([pscustomobject]@{
            root = 'profile'; relativePath = $relative; sha256 = $hash; version = $version
            expected = $(if ($expected.ContainsKey($key)) { $expected[$key] } else { $null })
        })
    }
    return @($inventory)
}

function New-Audit {
    param($Manifest, [string]$ModeName, [string]$Game, [string]$Profiles)
    $inventory = @(Get-Inventory -Manifest $Manifest -Game $Game -Profiles $Profiles)
    $actual = @{}
    $categories = [ordered]@{
        anniversaryBaseline = New-Object System.Collections.ArrayList
        approvedShared = New-Object System.Collections.ArrayList
        machineSpecific = New-Object System.Collections.ArrayList
        unknownOrIncompatible = New-Object System.Collections.ArrayList
    }
    foreach ($entry in $inventory) {
        $key = ('{0}|{1}' -f $entry.root, $entry.relativePath).ToLowerInvariant()
        $actual[$key] = $entry
        if ($null -ne $entry.expected) { $category = [string]$entry.expected.category }
        elseif ($entry.root -eq 'profile') { $category = 'machineSpecific' }
        else { $category = 'unknownOrIncompatible' }
        [void]$categories[$category].Add([pscustomobject][ordered]@{
            relativePath = $entry.relativePath
            version = $entry.version
            sha256 = $entry.sha256
        })
    }
    foreach ($key in @($categories.Keys)) {
        $categories[$key] = @($categories[$key] | Sort-Object relativePath)
    }
    $missing = New-Object System.Collections.ArrayList
    $extra = New-Object System.Collections.ArrayList
    $hashDifferent = New-Object System.Collections.ArrayList
    $versionDifferent = New-Object System.Collections.ArrayList
    foreach ($item in @($Manifest.items)) {
        $key = ('{0}|{1}' -f $item.root, $item.relativePath).ToLowerInvariant()
        if (-not $actual.ContainsKey($key)) {
            [void]$missing.Add((New-Difference -RelativePath $item.relativePath))
            continue
        }
        if ($actual[$key].sha256 -cne $item.sha256) { [void]$hashDifferent.Add((New-Difference -RelativePath $item.relativePath)) }
        if ([string]$actual[$key].version -cne [string]$item.version) { [void]$versionDifferent.Add((New-Difference -RelativePath $item.relativePath)) }
    }
    foreach ($entry in $inventory) {
        if ($null -eq $entry.expected) { [void]$extra.Add((New-Difference -RelativePath $entry.relativePath)) }
    }
    $actualOrder = @()
    $pluginsPath = Join-Path $Game 'Data\plugins.txt'
    if (Test-Path -LiteralPath $pluginsPath -PathType Leaf) {
        $actualOrder = @(Get-Content -LiteralPath $pluginsPath | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object { 'Data/' + $_.Trim() })
    }
    $expectedOrder = @($Manifest.loadOrder)
    $orderDifferent = New-Object System.Collections.ArrayList
    $orderPaths = @($expectedOrder + $actualOrder | Sort-Object -Unique)
    foreach ($path in $orderPaths) {
        $expectedIndex = [array]::IndexOf([object[]]$expectedOrder, $path)
        $actualIndex = [array]::IndexOf([object[]]$actualOrder, $path)
        if ($expectedIndex -ne $actualIndex) { [void]$orderDifferent.Add((New-Difference -RelativePath $path)) }
    }
    return [pscustomobject][ordered]@{
        schema = 'skyrim-engineering.laptop-audit/v1'
        clientId = $ClientId
        mode = $ModeName
        runtimeVersion = [string]$Manifest.runtimeVersion
        categories = [pscustomobject]$categories
        differences = [pscustomobject][ordered]@{
            missing = @($missing | Sort-Object relativePath)
            extra = @($extra | Sort-Object relativePath)
            hashDifferent = @($hashDifferent | Sort-Object relativePath)
            versionDifferent = @($versionDifferent | Sort-Object relativePath)
            orderDifferent = @($orderDifferent | Sort-Object relativePath)
        }
    }
}

function Get-Plan {
    param($Manifest, $Audit, [string]$Profiles)
    $actions = New-Object System.Collections.ArrayList
    $profile = Join-Path $Profiles 'Anniversary Together'
    if (-not (Test-Path -LiteralPath $profile -PathType Container)) {
        [void]$actions.Add([pscustomobject][ordered]@{ type = 'createProfile'; relativePath = 'Anniversary Together' })
    }
    $missing = @{}
    foreach ($difference in @($Audit.differences.missing)) { $missing[$difference.relativePath.ToLowerInvariant()] = $true }
    foreach ($item in @($Manifest.items | Where-Object { $_.category -eq 'approvedShared' } | Sort-Object relativePath)) {
        if ($missing.ContainsKey($item.relativePath.ToLowerInvariant())) {
            [void]$actions.Add([pscustomobject][ordered]@{
                type = 'installApprovedPackage'; id = [string]$item.id; relativePath = [string]$item.relativePath
                version = [string]$item.version; sha256 = [string]$item.sha256
            })
        }
    }
    return [pscustomobject][ordered]@{
        schema = 'skyrim-engineering.laptop-plan/v1'
        clientId = $ClientId
        actions = @($actions)
        differences = $Audit.differences
    }
}

function Write-StateFile {
    param($State, [string]$Path)
    $json = $State | ConvertTo-Json -Depth 8 -Compress
    [IO.File]::WriteAllText($Path, $json, (New-Object Text.UTF8Encoding($false)))
}

function Add-JournaledDirectory {
    param([string]$Directory, [string]$Profiles, $State, [string]$StatePath)
    Assert-NoReparsePoint -Root $Profiles -Candidate $Directory
    if (Test-Path -LiteralPath $Directory) {
        if (-not (Test-Path -LiteralPath $Directory -PathType Container)) { throw 'A required profile directory path is occupied by a file.' }
        return
    }
    $parent = Split-Path -Parent $Directory
    if (-not [string]::Equals((Get-NormalizedPath -Path $parent), (Get-NormalizedPath -Path $Profiles), [StringComparison]::OrdinalIgnoreCase)) {
        Add-JournaledDirectory -Directory $parent -Profiles $Profiles -State $State -StatePath $StatePath
    }
    [void](New-Item -ItemType Directory -Path $Directory)
    $relative = Convert-ToPortablePath -Path (Get-NormalizedPath -Path $Directory).Substring((Get-NormalizedPath -Path $Profiles).Length + 1)
    [void]$State.mutations.Add([pscustomobject][ordered]@{ type = 'createDirectory'; root = 'profile'; relativePath = $relative; sha256 = $null })
    Write-StateFile -State $State -Path $StatePath
}

function Invoke-Apply {
    param($Manifest, [string]$ManifestPath, [string]$Profiles, [string]$States)
    if (-not $ConfirmApply) { throw 'Apply requires the separate -ConfirmApply switch.' }
    $statePath = Join-Path $States ($ClientId + '.state.json')
    if (Test-Path -LiteralPath $statePath) { throw 'An existing client state journal must be rolled back or archived before Apply.' }
    $manifestDirectory = Split-Path -Parent (Get-NormalizedPath -Path $ManifestPath)
    $profile = Join-Path $Profiles 'Anniversary Together'
    $packages = @($Manifest.items | Where-Object { $_.category -eq 'approvedShared' } | Sort-Object relativePath)
    foreach ($package in $packages) {
        $source = Join-Path $manifestDirectory ([string]$package.sourceRelativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        Assert-NoReparsePoint -Root $manifestDirectory -Candidate $source
        if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { throw 'An approved package source is missing.' }
        if ((Get-FileHash -LiteralPath $source -Algorithm SHA256).Hash.ToLowerInvariant() -cne $package.sha256) {
            throw 'An approved package source failed its pinned SHA-256 check.'
        }
        $destination = Join-Path $profile ([string]$package.relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        Assert-NoReparsePoint -Root $Profiles -Candidate $destination
        Assert-ContainedPath -Root $profile -Candidate $destination
        if (Test-Path -LiteralPath $destination) { throw 'Apply will not overwrite an existing profile add-on or file.' }
    }
    if (-not $PSCmdlet.ShouldProcess('Anniversary Together', 'Create isolated profile and install approved hash-verified free packages')) { return }
    $state = [pscustomobject][ordered]@{
        schema = 'skyrim-engineering.laptop-state/v1'; clientId = $ClientId; status = 'applying'
        manifestSha256 = (Get-FileHash -LiteralPath $ManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        mutations = New-Object System.Collections.ArrayList
    }
    Write-StateFile -State $state -Path $statePath
    Add-JournaledDirectory -Directory $profile -Profiles $Profiles -State $state -StatePath $statePath
    foreach ($package in $packages) {
        $source = Join-Path $manifestDirectory ([string]$package.sourceRelativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        $destination = Join-Path $profile ([string]$package.relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        Add-JournaledDirectory -Directory (Split-Path -Parent $destination) -Profiles $Profiles -State $state -StatePath $statePath
        Copy-Item -LiteralPath $source -Destination $destination
        [void]$state.mutations.Add([pscustomobject][ordered]@{
            type = 'createFile'; root = 'profile'
            relativePath = Convert-ToPortablePath -Path (Get-NormalizedPath -Path $destination).Substring((Get-NormalizedPath -Path $Profiles).Length + 1)
            sha256 = [string]$package.sha256
        })
        Write-StateFile -State $state -Path $statePath
    }
    $state.status = 'applied'
    Write-StateFile -State $state -Path $statePath
    return $state
}

function Invoke-Rollback {
    param([string]$Profiles, [string]$States)
    $statePath = Join-Path $States ($ClientId + '.state.json')
    if (-not (Test-Path -LiteralPath $statePath -PathType Leaf)) { throw 'No journaled state exists for this client.' }
    try { $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json -ErrorAction Stop }
    catch { throw 'The client state journal is invalid.' }
    if ($state.schema -cne 'skyrim-engineering.laptop-state/v1' -or $state.clientId -cne $ClientId -or $state.status -cne 'applied') {
        throw 'The client state journal is not an applied journal for this anonymous client.'
    }
    $mutations = @($state.mutations)
    foreach ($mutation in $mutations) {
        Assert-SafeRelativePath -Path ([string]$mutation.relativePath)
        if (-not ([string]$mutation.relativePath).StartsWith('Anniversary Together/', [StringComparison]::OrdinalIgnoreCase) -and
            [string]$mutation.relativePath -cne 'Anniversary Together') {
            throw 'The journal contains a mutation outside the isolated profile.'
        }
        $path = Join-Path $Profiles ([string]$mutation.relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        Assert-NoReparsePoint -Root $Profiles -Candidate $path
        if ($mutation.type -eq 'createFile' -and (Test-Path -LiteralPath $path -PathType Leaf)) {
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($hash -cne [string]$mutation.sha256) { throw 'A journaled file hash no longer matches; rollback refused without changing files.' }
        }
        elseif ($mutation.type -cnotin @('createFile', 'createDirectory')) { throw 'The journal contains an unsupported mutation type.' }
    }
    if (-not $PSCmdlet.ShouldProcess('Anniversary Together', 'Rollback only journaled bootstrap changes')) { return }
    foreach ($mutation in @($mutations | Where-Object { $_.type -eq 'createFile' } | Sort-Object relativePath -Descending)) {
        $path = Join-Path $Profiles ([string]$mutation.relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        if (Test-Path -LiteralPath $path -PathType Leaf) { Remove-Item -LiteralPath $path }
    }
    $directories = @($mutations | Where-Object { $_.type -eq 'createDirectory' } | Sort-Object { ([string]$_.relativePath).Length } -Descending)
    foreach ($mutation in $directories) {
        $path = Join-Path $Profiles ([string]$mutation.relativePath).Replace('/', [IO.Path]::DirectorySeparatorChar)
        if ((Test-Path -LiteralPath $path -PathType Container) -and @(Get-ChildItem -LiteralPath $path -Force).Count -eq 0) {
            Remove-Item -LiteralPath $path
        }
    }
    $state.status = 'rolledBack'
    Write-StateFile -State $state -Path $statePath
    return $state
}

$modeCount = @($AuditOnly, $Plan, $Apply, $Verify, $Rollback | Where-Object { $_ }).Count
if ($modeCount -ne 1) { throw 'Select exactly one mode: -AuditOnly, -Plan, -Apply, -Verify, or -Rollback.' }
if ($ConfirmApply -and -not $Apply) { throw '-ConfirmApply is valid only with -Apply.' }

$game = Get-NormalizedPath -Path $GameRoot
$profiles = Get-NormalizedPath -Path $ProfileRoot
$manifestPath = Get-NormalizedPath -Path $CanonicalManifest
$states = Get-NormalizedPath -Path $StateDirectory
foreach ($root in @($game, $profiles, $states)) {
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'GameRoot, ProfileRoot, and StateDirectory must be existing explicit directories.' }
    if (((Get-Item -LiteralPath $root -Force).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Explicit roots must not be reparse points.' }
}
$manifest = Read-CanonicalManifest -Path $manifestPath

if ($AuditOnly) {
    New-Audit -Manifest $manifest -ModeName 'auditOnly' -Game $game -Profiles $profiles | ConvertTo-Json -Depth 8 -Compress
}
elseif ($Plan) {
    $audit = New-Audit -Manifest $manifest -ModeName 'plan' -Game $game -Profiles $profiles
    Get-Plan -Manifest $manifest -Audit $audit -Profiles $profiles | ConvertTo-Json -Depth 8 -Compress
}
elseif ($Apply) {
    $result = Invoke-Apply -Manifest $manifest -ManifestPath $manifestPath -Profiles $profiles -States $states
    if ($null -ne $result) { $result | ConvertTo-Json -Depth 8 -Compress }
}
elseif ($Verify) {
    New-Audit -Manifest $manifest -ModeName 'verify' -Game $game -Profiles $profiles | ConvertTo-Json -Depth 8 -Compress
}
elseif ($Rollback) {
    $result = Invoke-Rollback -Profiles $profiles -States $states
    if ($null -ne $result) { $result | ConvertTo-Json -Depth 8 -Compress }
}
