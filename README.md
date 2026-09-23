# FontInstallerTool

Adds **Install fonts in this folder** to the Windows Explorer context menu. Right-click an
empty area inside a folder to install every `.ttf` and `.otf` font in it for the current
user. Subfolders are not scanned.

- No administrator rights needed. Fonts go to `%LOCALAPPDATA%\Microsoft\Windows\Fonts`.
- Fonts that are already installed, either for you or system-wide, are skipped.
- A summary dialog lists the fonts that were installed, skipped or failed.
- Fonts can be used right away in running apps, without signing out.

## Install

```powershell
powershell -ExecutionPolicy Bypass -File .\install.ps1
```

On Windows 11 the entry appears under **Show more options** (or press Shift+Right-click).

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

This removes the menu entry and the tool files. Fonts you installed with it stay installed.

## Tests

Requires Pester 5 (Windows ships with 3.4):

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester .\tests
```
