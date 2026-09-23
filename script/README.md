# Script edition

Two PowerShell scripts. There is no setup program and nothing is listed in Installed apps.

## Install

1. Download [FontInstallerTool-Script.zip](https://github.com/FilipeLopesPires/FontInstallerTool/releases/latest/download/FontInstallerTool-Script.zip) and extract it.
2. In that folder, run:

   ```powershell
   powershell -ExecutionPolicy Bypass -File .\install.ps1
   ```

From a clone of the repository, run `.\script\install.ps1` instead.

The tool is copied to `%LOCALAPPDATA%\FontInstallerTool` and the menu entry is registered
for your account only.

## Uninstall

```powershell
powershell -ExecutionPolicy Bypass -File .\uninstall.ps1
```

This removes the menu entry and the tool files. Fonts you installed stay installed.

If the Installer edition is installed, both scripts refuse to run. Use Settings › Apps to
manage it.
