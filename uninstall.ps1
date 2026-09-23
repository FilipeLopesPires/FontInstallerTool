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

[Microsoft.Win32.Registry]::CurrentUser.DeleteSubKeyTree($menuSubKey, $false)

if (Test-Path -LiteralPath $toolDir) {
    Remove-Item -LiteralPath $toolDir -Recurse -Force
}

Write-Host 'Context menu entry and tool files removed.'
Write-Host 'Fonts installed with the tool are still installed.'
