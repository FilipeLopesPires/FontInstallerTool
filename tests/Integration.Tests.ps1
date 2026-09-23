#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeDiscovery {
    # Tier 2 tests need a built installer: .\build\build.ps1
    $setupMissing = -not (Test-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\FontInstallerTool-Setup.exe'))
}

# These tests install and uninstall the real tool on this machine.
# Excluded locally with: Invoke-Pester -Path tests -ExcludeTagFilter Integration

BeforeAll {
    $repo                  = Split-Path $PSScriptRoot -Parent
    $menuKey               = 'HKCU:\Software\Classes\Directory\Background\shell\FontInstallerTool'
    $scriptDir             = Join-Path $env:LOCALAPPDATA 'FontInstallerTool'
    $installerDir          = Join-Path $env:LOCALAPPDATA 'Programs\FontInstallerTool'
    $installerUninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{982F438F-8A78-4107-992B-7029A29DAEF7}_is1'

    function Wait-Condition {
        param([Parameter(Mandatory)][scriptblock]$Condition, [int]$TimeoutSeconds = 30)
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not (& $Condition)) {
            if ((Get-Date) -gt $deadline) { throw "Timed out after $TimeoutSeconds s waiting for: $Condition" }
            Start-Sleep -Milliseconds 250
        }
    }

    function Get-MenuCommand {
        (Get-Item -LiteralPath "$menuKey\command").GetValue('')
    }

    # Removes both editions, so every Describe block starts from a clean machine
    function Reset-FontInstallerTool {
        $uninstaller = Join-Path $installerDir 'unins000.exe'
        if (Test-Path -LiteralPath $uninstaller) {
            Start-Process $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES' -Wait
            # The Inno uninstaller relaunches itself from %TEMP%, so -Wait can return early
            Wait-Condition { -not (Test-Path -LiteralPath $installerUninstallKey) }
        }
        Remove-Item -LiteralPath $installerUninstallKey -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $menuKey -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $scriptDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Script edition' -Tag Integration {
    BeforeAll { Reset-FontInstallerTool }
    AfterAll { Reset-FontInstallerTool }

    It 'installs from a repository clone' {
        & (Join-Path $repo 'script\install.ps1') | Out-Null

        Join-Path $scriptDir 'Install-Fonts.ps1' | Should -Exist
        Get-MenuCommand | Should -BeLike "*-File `"$scriptDir\Install-Fonts.ps1`" -Path `"%V`""
    }

    It 'uninstalls completely' {
        & (Join-Path $repo 'script\uninstall.ps1') | Out-Null

        $menuKey | Should -Not -Exist
        $scriptDir | Should -Not -Exist
    }

    It 'installs from the flat release zip layout' {
        $flat = Join-Path $TestDrive 'flat'
        New-Item -ItemType Directory $flat | Out-Null
        Copy-Item (Join-Path $repo 'script\install.ps1'), (Join-Path $repo 'src\Install-Fonts.ps1') $flat

        & (Join-Path $flat 'install.ps1') | Out-Null

        Join-Path $scriptDir 'Install-Fonts.ps1' | Should -Exist
    }

    Context 'when the Installer edition is installed' {
        BeforeAll { New-Item -Path $installerUninstallKey -Force | Out-Null }
        AfterAll { Remove-Item -LiteralPath $installerUninstallKey -Recurse -Force }

        It 'install.ps1 refuses to run' {
            { & (Join-Path $repo 'script\install.ps1') } | Should -Throw '*Installer edition*'
        }

        It 'uninstall.ps1 refuses to remove the installer''s menu entry' {
            { & (Join-Path $repo 'script\uninstall.ps1') } | Should -Throw '*Installer edition*'
        }
    }
}

Describe 'Installer edition' -Tag Integration -Skip:$setupMissing {
    BeforeAll {
        Reset-FontInstallerTool
        $setup = Join-Path $repo 'dist\FontInstallerTool-Setup.exe'

        function Invoke-Setup {
            Start-Process $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
        }
    }
    AfterAll { Reset-FontInstallerTool }

    It 'takes over an existing Script edition install' {
        & (Join-Path $repo 'script\install.ps1') | Out-Null

        Invoke-Setup

        $scriptDir | Should -Not -Exist
        Get-MenuCommand | Should -BeLike "*-File `"$installerDir\Install-Fonts.ps1`" -Path `"%V`""
    }

    It 'installs the worker and registers the menu entry' {
        Join-Path $installerDir 'Install-Fonts.ps1' | Should -Exist
        $menu = Get-Item -LiteralPath $menuKey
        $menu.GetValue('MUIVerb') | Should -Be 'Install fonts in this folder'
        $menu.GetValue('Icon', $null, 'DoNotExpandEnvironmentNames') | Should -Be '%SystemRoot%\System32\fontext.dll,0'
        Get-MenuCommand | Should -BeLike 'conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File *'
    }

    It 'appears in Installed apps' {
        (Get-ItemProperty -LiteralPath $installerUninstallKey).DisplayName | Should -Be 'FontInstallerTool'
    }

    It 'uninstalls completely' {
        Start-Process (Join-Path $installerDir 'unins000.exe') -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES' -Wait
        Wait-Condition { -not (Test-Path -LiteralPath $installerUninstallKey) }
        Wait-Condition { -not (Test-Path -LiteralPath $installerDir) }

        $menuKey | Should -Not -Exist
    }
}
