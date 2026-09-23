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
# Must match AppId in installer\FontInstallerTool.iss
$installerEditionKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{982F438F-8A78-4107-992B-7029A29DAEF7}_is1'

if (Test-Path -LiteralPath $installerEditionKey) {
    throw 'The Installer edition of FontInstallerTool is already installed. Keep using it, or uninstall it from Settings > Apps before installing the Script edition.'
}

# Release zip: the worker sits next to this script. Repository clone: it is in ..\src
$source = @(
    (Join-Path $PSScriptRoot 'Install-Fonts.ps1'),
    (Join-Path $PSScriptRoot '..\src\Install-Fonts.ps1')
) | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
if (-not $source) { throw 'Install-Fonts.ps1 was not found next to install.ps1 or in ..\src.' }

New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
Copy-Item -LiteralPath $source -Destination $worker -Force
# Files extracted from a downloaded zip carry the "downloaded from the internet" mark
Unblock-File -LiteralPath $worker

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
