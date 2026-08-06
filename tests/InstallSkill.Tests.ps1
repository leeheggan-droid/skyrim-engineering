#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.9.0' }

Describe 'install-skill junction safety' {
    BeforeAll {
        $script:installer = Join-Path $PSScriptRoot '..\skill\skyrim-engineering\scripts\install-skill.ps1'
        $script:repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    }

    BeforeEach {
        $script:skillsRoot = Join-Path $TestDrive ('skills-' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $skillsRoot -Force | Out-Null
        $script:target = Join-Path $skillsRoot 'skyrim-engineering'
    }

    It 'reports a dry run without creating a target' {
        $output = & $installer -RepositoryRoot $repositoryRoot -CodexSkillsRoot $skillsRoot -WhatIf 4>&1 | Out-String

        Test-Path -LiteralPath $target | Should -BeFalse
        $output | Should -Match 'Dry run only'
    }

    It 'creates exactly the requested junction and is idempotent' {
        & $installer -RepositoryRoot $repositoryRoot -CodexSkillsRoot $skillsRoot -Confirm:$false
        & $installer -RepositoryRoot $repositoryRoot -CodexSkillsRoot $skillsRoot -Confirm:$false

        $item = Get-Item -LiteralPath $target -Force
        $item.LinkType | Should -Be 'Junction'
        [IO.Path]::GetFullPath([string]$item.Target) | Should -Be ([IO.Path]::GetFullPath((Join-Path $repositoryRoot 'skill\skyrim-engineering')))
    }

    It 'refuses to replace a real directory' {
        New-Item -ItemType Directory -Path $target | Out-Null

        { & $installer -RepositoryRoot $repositoryRoot -CodexSkillsRoot $skillsRoot -Confirm:$false } | Should -Throw '*not an existing junction*'
        (Get-Item -LiteralPath $target -Force).LinkType | Should -BeNullOrEmpty
    }

    It 'refuses a junction targeting elsewhere' {
        $elsewhere = Join-Path $TestDrive 'elsewhere'
        New-Item -ItemType Directory -Path $elsewhere | Out-Null
        New-Item -ItemType Junction -Path $target -Target $elsewhere | Out-Null

        { & $installer -RepositoryRoot $repositoryRoot -CodexSkillsRoot $skillsRoot -Confirm:$false } | Should -Throw '*different source*'
        [IO.Path]::GetFullPath([string](Get-Item -LiteralPath $target -Force).Target) | Should -Be ([IO.Path]::GetFullPath($elsewhere))
    }

    It 'requires a source SKILL.md and refuses a reparse-point skills root' {
        $emptyRepository = Join-Path $TestDrive 'empty-repository'
        New-Item -ItemType Directory -Path $emptyRepository | Out-Null
        { & $installer -RepositoryRoot $emptyRepository -CodexSkillsRoot $skillsRoot -Confirm:$false } | Should -Throw '*SKILL.md*'

        $realSkills = Join-Path $TestDrive 'real-skills'
        $linkedSkills = Join-Path $TestDrive 'linked-skills'
        New-Item -ItemType Directory -Path $realSkills | Out-Null
        New-Item -ItemType Junction -Path $linkedSkills -Target $realSkills | Out-Null
        { & $installer -RepositoryRoot $repositoryRoot -CodexSkillsRoot $linkedSkills -Confirm:$false } | Should -Throw '*reparse point*'
    }

    It 'refuses repository and skills paths reached through reparse-point ancestors' {
        $realParent = Join-Path $TestDrive 'real-parent'
        $linkedParent = Join-Path $TestDrive 'linked-parent'
        New-Item -ItemType Directory -Path $realParent | Out-Null
        New-Item -ItemType Junction -Path $linkedParent -Target $realParent | Out-Null
        $nestedSkills = Join-Path $linkedParent 'nested-skills'
        New-Item -ItemType Directory -Path $nestedSkills | Out-Null

        { & $installer -RepositoryRoot $repositoryRoot -CodexSkillsRoot $nestedSkills -Confirm:$false } | Should -Throw '*reparse*ancestor*'
    }

    It 'requires fully qualified repository and skills roots' {
        { & $installer -RepositoryRoot '.' -CodexSkillsRoot $skillsRoot -Confirm:$false } | Should -Throw '*fully qualified*'
        { & $installer -RepositoryRoot $repositoryRoot -CodexSkillsRoot '.\skills' -Confirm:$false } | Should -Throw '*fully qualified*'
    }
}
