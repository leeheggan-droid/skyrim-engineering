[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Low')]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$RepositoryRoot,

    [ValidateNotNullOrEmpty()]
    [string]$CodexSkillsRoot = (Join-Path ([Environment]::GetFolderPath('UserProfile')) '.codex\skills')
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-NormalizedPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
}

function Assert-FullyQualifiedLocalPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    if ($Path -cnotmatch '^[A-Za-z]:[\\/]' -or $Path -match '^\\\\') {
        throw 'RepositoryRoot and CodexSkillsRoot must be fully qualified local paths.'
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
                throw 'A reparse point ancestor was refused.'
            }
        }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrEmpty($parent) -or $parent -eq $current) { break }
        $current = $parent
    }
}

Assert-FullyQualifiedLocalPath -Path $RepositoryRoot
Assert-FullyQualifiedLocalPath -Path $CodexSkillsRoot
$repository = Get-NormalizedPath -Path $RepositoryRoot
$skillsRoot = Get-NormalizedPath -Path $CodexSkillsRoot
$source = Get-NormalizedPath -Path (Join-Path $repository 'skill\skyrim-engineering')
$target = Get-NormalizedPath -Path (Join-Path $skillsRoot 'skyrim-engineering')

Assert-NoReparseAncestor -Path $repository
Assert-NoReparseAncestor -Path $source
Assert-NoReparseAncestor -Path $skillsRoot
Assert-NoReparseAncestor -Path (Split-Path -Parent $target)

if (-not (Test-Path -LiteralPath (Join-Path $source 'SKILL.md') -PathType Leaf)) {
    throw 'The repository source must contain skill/skyrim-engineering/SKILL.md.'
}
if (-not (Test-Path -LiteralPath $skillsRoot -PathType Container)) {
    throw 'CodexSkillsRoot must be an existing directory.'
}
$skillsRootItem = Get-Item -LiteralPath $skillsRoot -Force
if (($skillsRootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
    throw 'CodexSkillsRoot must not be a reparse point.'
}

if (Test-Path -LiteralPath $target) {
    $existing = Get-Item -LiteralPath $target -Force
    if ($existing.LinkType -ne 'Junction') {
        throw 'Installation target exists and is not an existing junction; it will not be replaced.'
    }
    $existingTarget = Get-NormalizedPath -Path ([string]$existing.Target)
    if (-not [string]::Equals($existingTarget, $source, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Installation target is a junction to a different source; it will not be replaced.'
    }
    Write-Output 'Skyrim Engineering skill junction is already installed at the requested root.'
    return
}

if ($PSCmdlet.ShouldProcess($target, "Create junction to '$source'")) {
    Assert-NoReparseAncestor -Path $source
    Assert-NoReparseAncestor -Path $skillsRoot
    if (Test-Path -LiteralPath $target) { throw 'Installation target appeared before junction creation and was refused.' }
    $created = New-Item -ItemType Junction -Path $target -Target $source
    $verified = Get-Item -LiteralPath $target -Force
    if ($verified.LinkType -ne 'Junction' -or
        -not [string]::Equals((Get-NormalizedPath -Path ([string]$verified.Target)), $source, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Created junction did not resolve to the exact requested skill source.'
    }
    Write-Output 'Skyrim Engineering skill junction installed and verified.'
}
elseif ($WhatIfPreference) {
    Write-Output 'Dry run only: no skill junction was created.'
}
