<#
.SYNOPSIS
    Removes the "Install fonts in this folder" context menu entry and the tool files.

.DESCRIPTION
    Fonts that were installed with the tool are left installed. Remove them from
    Settings > Personalization > Fonts if needed.
#>
[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$toolDir    = Join-Path $env:LOCALAPPDATA 'FontInstallerTool'
$menuSubKey = 'Software\Classes\Directory\Background\shell\FontInstallerTool'
# Must match AppId in installer\FontInstallerTool.iss
$installerEditionKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{982F438F-8A78-4107-992B-7029A29DAEF7}_is1'

# Both editions share the menu key; removing it here would break the Installer edition
if (Test-Path -LiteralPath $installerEditionKey) {
    throw 'The Installer edition of FontInstallerTool is installed. Uninstall it from Settings > Apps instead.'
}

[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($menuSubKey, $false)

if (Test-Path -LiteralPath $toolDir) {
    Remove-Item -LiteralPath $toolDir -Recurse -Force
}

Write-Host 'Context menu entry and tool files removed.'
Write-Host 'Fonts installed with the tool are still installed.'
