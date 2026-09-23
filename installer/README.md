# Installer edition

A standard setup wizard that installs FontInstallerTool for your account and lists it in
**Settings › Apps › Installed apps**.

## Install

1. Download [FontInstallerTool-Setup.exe](https://github.com/FilipeLopesPires/FontInstallerTool/releases/latest/download/FontInstallerTool-Setup.exe).
2. Run it. There is no administrator prompt. If SmartScreen appears, choose
   **More info › Run anyway** (the installer is not code-signed).

It installs to `%LOCALAPPDATA%\Programs\FontInstallerTool`. If the Script edition is
installed, setup replaces it.

Silent install: `FontInstallerTool-Setup.exe /VERYSILENT /SUPPRESSMSGBOXES`

## Uninstall

**Settings › Apps › Installed apps › FontInstallerTool › Uninstall.** Fonts you installed
stay installed.

## Building

Requires [Inno Setup 6](https://jrsoftware.org/isinfo.php) (`winget install JRSoftware.InnoSetup`).

```powershell
.\build\build.ps1
```

The version comes from the [VERSION](../VERSION) file. The output is `dist\FontInstallerTool-Setup.exe` and `dist\FontInstallerTool-Script.zip`.
The definition is in [FontInstallerTool.iss](FontInstallerTool.iss). Never change its
`AppId`.
