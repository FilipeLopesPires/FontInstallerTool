<#
.SYNOPSIS
    Adds "Install fonts in this folder" to the Explorer folder-background context menu.

.DESCRIPTION
    Copies the worker script to %LOCALAPPDATA%\FontInstallerTool and registers a
    per-user (HKCU) context menu entry. No administrator rights are required.
    Safe to run again: it overwrites the previous installation.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$toolDir    = Join-Path $env:LOCALAPPDATA 'FontInstallerTool'
$worker     = Join-Path $toolDir 'Install-Fonts.ps1'
$menuSubKey = 'Software\Classes\Directory\Background\shell\FontInstallerTool'

New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $PSScriptRoot 'src\Install-Fonts.ps1') -Destination $worker -Force

# conhost --headless runs PowerShell without the console window flashing on screen
$command = "conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass " +
           "-File `"$worker`" -Path `"%V`""

# The .NET API creates any missing parent keys, which New-Item does not do reliably
$menuKey = [Microsoft.Win32.Registry]::CurrentUser.CreateSubKey($menuSubKey)
try {
    $menuKey.SetValue('MUIVerb', 'Install fonts in this folder')
    $menuKey.SetValue('Icon', '%SystemRoot%\System32\fontext.dll,0', [Microsoft.Win32.RegistryValueKind]::ExpandString)

    $commandKey = $menuKey.CreateSubKey('command')
    try {
        $commandKey.SetValue('', $command)
    } finally {
        $commandKey.Close()
    }
} finally {
    $menuKey.Close()
}

Write-Host "Installed to $toolDir"
Write-Host 'Right-click an empty area inside a folder (Show more options on Windows 11) and choose "Install fonts in this folder".'
