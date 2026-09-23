<#
.SYNOPSIS
    Installs every .ttf/.otf font found directly in a folder, for the current user only.

.DESCRIPTION
    Launched from the Explorer folder-background context menu (see install.ps1).
    Scans the folder non-recursively, skips fonts that are already installed
    (per-user or system-wide), installs the rest into the per-user fonts folder
    and shows a summary dialog. No administrator rights are required.

.PARAMETER Path
    Folder to scan. Explorer passes it through %V.
#>
[CmdletBinding()]
param(
    [string]$Path
)

$FontExtensions = @('.ttf', '.otf')
$UserFontDir    = Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Fonts'
$SystemFontDir  = Join-Path $env:SystemRoot 'Fonts'
$UserFontKey    = 'HKCU:\Software\Microsoft\Windows NT\CurrentVersion\Fonts'
$SystemFontKey  = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'
$DialogTitle    = 'Font Installer'
$MaxListedNames = 15

function ConvertTo-NormalizedFolderPath {
    # Explorer passes a drive root as "E:\" and PowerShell's -File parsing turns
    # the trailing \" into an escaped quote, so the script receives E:"
    param([Parameter(Mandatory)][string]$RawPath)

    $normalized = $RawPath.Trim().TrimEnd('"')
    if ($normalized -match '^[A-Za-z]:$') { $normalized += '\' }
    return $normalized
}

function Get-FontFiles {
    param([Parameter(Mandatory)][string]$Folder)

    # Non-recursive on purpose: only fonts sitting directly in the folder
    @(Get-ChildItem -LiteralPath $Folder -File |
        Where-Object { $FontExtensions -contains $_.Extension.ToLowerInvariant() } |
        Sort-Object Name)
}

function Get-EnglishName {
    param([Parameter(Mandatory)]$Names)

    $enUs = [System.Globalization.CultureInfo]::GetCultureInfo('en-US')
    $value = $null
    if ($Names.TryGetValue($enUs, [ref]$value)) { return $value }
    return @($Names.Values)[0]
}

function Get-FontDisplayName {
    # Builds the registry value name Windows uses, e.g. "Arial Bold (TrueType)".
    # GlyphTypeface (WPF) is used because it reads CFF-based .otf files,
    # which GDI+'s PrivateFontCollection cannot. Throws on invalid font files.
    param([Parameter(Mandatory)][string]$FontPath)

    Add-Type -AssemblyName PresentationCore
    $glyph = [System.Windows.Media.GlyphTypeface]::new([Uri]::new($FontPath))

    $family = Get-EnglishName $glyph.Win32FamilyNames
    $face   = Get-EnglishName $glyph.Win32FaceNames

    $name = if ($face -and $face -ne 'Regular') { "$family $face" } else { $family }
    return "$name (TrueType)"
}

function Test-FontInstalled {
    param(
        [Parameter(Mandatory)][string]$DisplayName,
        [Parameter(Mandatory)][string]$FileName
    )

    foreach ($key in $UserFontKey, $SystemFontKey) {
        $values = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
        if ($values -and $values.PSObject.Properties[$DisplayName]) { return $true }
    }
    foreach ($dir in $UserFontDir, $SystemFontDir) {
        if (Test-Path -LiteralPath (Join-Path $dir $FileName)) { return $true }
    }
    return $false
}

function Initialize-NativeMethods {
    if ('FontInstaller.NativeMethods' -as [type]) { return }

    Add-Type -Namespace FontInstaller -Name NativeMethods -MemberDefinition @'
[DllImport("gdi32.dll", CharSet = CharSet.Unicode)]
public static extern int AddFontResourceW(string lpszFilename);

[DllImport("user32.dll", CharSet = CharSet.Unicode)]
public static extern IntPtr SendMessageTimeoutW(IntPtr hWnd, uint Msg, UIntPtr wParam, IntPtr lParam,
    uint fuFlags, uint uTimeout, out UIntPtr lpdwResult);
'@
}

function Install-FontFile {
    param(
        [Parameter(Mandatory)][System.IO.FileInfo]$File,
        [Parameter(Mandatory)][string]$DisplayName
    )

    if (-not (Test-Path -LiteralPath $UserFontDir)) {
        New-Item -ItemType Directory -Path $UserFontDir -Force | Out-Null
    }
    $target = Join-Path $UserFontDir $File.Name
    Copy-Item -LiteralPath $File.FullName -Destination $target -ErrorAction Stop

    if (-not (Test-Path -LiteralPath $UserFontKey)) {
        New-Item -Path $UserFontKey -Force | Out-Null
    }
    # Per-user fonts must be registered with their full path, not just the file name
    New-ItemProperty -LiteralPath $UserFontKey -Name $DisplayName -Value $target -PropertyType String -Force | Out-Null

    # Makes the font usable in running apps right away; the registry entry alone
    # would only take effect at next sign-in
    Initialize-NativeMethods
    [FontInstaller.NativeMethods]::AddFontResourceW($target) | Out-Null
}

function Send-FontChangeBroadcast {
    Initialize-NativeMethods
    $HWND_BROADCAST   = [IntPtr]0xFFFF
    $WM_FONTCHANGE    = 0x001D
    $SMTO_ABORTIFHUNG = 0x0002
    $result = [UIntPtr]::Zero
    # Timeout variant so one hung window cannot block the script
    [FontInstaller.NativeMethods]::SendMessageTimeoutW(
        $HWND_BROADCAST, $WM_FONTCHANGE, [UIntPtr]::Zero, [IntPtr]::Zero,
        $SMTO_ABORTIFHUNG, 1000, [ref]$result) | Out-Null
}

function Install-Fonts {
    param([Parameter(Mandatory)][System.IO.FileInfo[]]$Files)

    $result = [pscustomobject]@{
        Installed = [System.Collections.Generic.List[string]]::new()
        Skipped   = [System.Collections.Generic.List[string]]::new()
        Failed    = [System.Collections.Generic.List[string]]::new()
    }

    foreach ($file in $Files) {
        try {
            $displayName = Get-FontDisplayName $file.FullName
        } catch {
            $result.Failed.Add("$($file.Name): not a valid font file")
            continue
        }

        if (Test-FontInstalled -DisplayName $displayName -FileName $file.Name) {
            $result.Skipped.Add($file.Name)
            continue
        }

        try {
            Install-FontFile -File $file -DisplayName $displayName
            $result.Installed.Add($file.Name)
        } catch {
            $result.Failed.Add("$($file.Name): $($_.Exception.Message)")
        }
    }

    if ($result.Installed.Count -gt 0) { Send-FontChangeBroadcast }
    return $result
}

function Format-NameList {
    param([string[]]$Names)

    $shown = @($Names | Select-Object -First $MaxListedNames | ForEach-Object { "   - $_" })
    if ($Names.Count -gt $MaxListedNames) {
        $shown += "   ... and $($Names.Count - $MaxListedNames) more"
    }
    return $shown -join "`n"
}

function Format-Summary {
    param([Parameter(Mandatory)]$Result)

    $sections = @()
    foreach ($entry in @(
            @{ Label = 'Installed'; Names = $Result.Installed },
            @{ Label = 'Skipped (already installed)'; Names = $Result.Skipped },
            @{ Label = 'Failed'; Names = $Result.Failed })) {
        if ($entry.Names.Count -eq 0) { continue }
        $sections += "$($entry.Label): $($entry.Names.Count)`n$(Format-NameList $entry.Names)"
    }
    return $sections -join "`n`n"
}

function Show-Message {
    param(
        [Parameter(Mandatory)][string]$Text,
        [ValidateSet('Information', 'Warning', 'Error')][string]$Icon = 'Information'
    )

    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show($Text, $DialogTitle, 'OK', $Icon) | Out-Null
}

# Main. Skipped when the file is dot-sourced (e.g. by the Pester tests).
if ($MyInvocation.InvocationName -ne '.') {
    try {
        if (-not $Path) { throw 'No folder path was given.' }
        $folder = ConvertTo-NormalizedFolderPath $Path
        if (-not (Test-Path -LiteralPath $folder -PathType Container)) {
            throw "Folder not found: $folder"
        }

        $fonts = Get-FontFiles $folder
        if ($fonts.Count -eq 0) {
            Show-Message "No .ttf or .otf fonts found in:`n$folder"
            return
        }

        $result = Install-Fonts -Files $fonts
        $icon = if ($result.Failed.Count -gt 0) { 'Warning' } else { 'Information' }
        Show-Message (Format-Summary $result) $icon
    } catch {
        Show-Message "Font installation stopped because of an error:`n$($_.Exception.Message)" 'Error'
    }
}
