# FontInstallerTool

Install every font in a folder with one right-click.

![The "Install fonts in this folder" entry in the Explorer context menu](docs/images/context-menu.png)

Right-click an empty area inside a folder and choose **Install fonts in this folder**.
Every `.ttf` and `.otf` file directly in that folder is installed for your account.
Fonts you already have are skipped, and a summary tells you what happened.

![Summary dialog listing installed and skipped fonts](docs/images/summary-dialog.png)

## Choose your edition

Both editions install the same tool, and neither needs administrator rights.

| | **Installer edition** | **Script edition** |
|---|---|---|
| Best for | Most people | Developers comfortable with PowerShell |
| Install | Run a setup wizard | Run `install.ps1` |
| Uninstall | Settings › Apps | Run `uninstall.ps1` |
| Listed in Installed apps | Yes | No |
| Download | [FontInstallerTool-Setup.exe](https://github.com/FilipeLopesPires/FontInstallerTool/releases/latest/download/FontInstallerTool-Setup.exe) | [FontInstallerTool-Script.zip](https://github.com/FilipeLopesPires/FontInstallerTool/releases/latest/download/FontInstallerTool-Script.zip) |
| Details | [installer/](installer/README.md) | [script/](script/README.md) |

Install only one edition at a time. The Installer edition replaces the Script edition if it
finds it.

> **Windows SmartScreen:** the setup program is not code-signed, so Windows may say
> "Windows protected your PC" the first time you run it. Choose **More info › Run anyway**.

## Using it

- On Windows 11 the entry is in the classic menu: choose **Show more options** first, or
  press Shift+Right-click.
- The entry appears in every folder. In a folder without fonts it tells you so.
- Subfolders are not scanned.
- Remove fonts later from **Settings › Personalization › Fonts**.

## What's next

See the [roadmap](ROADMAP.md): an entry that hides itself in folders without fonts, and a
place at the top of the Windows 11 menu.

## Development

```powershell
Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
Invoke-Pester -Path tests -ExcludeTagFilter Integration   # safe: no system changes
.\build\build.ps1                                          # needs Inno Setup 6
```

The integration tests (`-Tag Integration`) install and uninstall the real tool. CI runs
them on every push.

To release, update the [VERSION](VERSION) file (for example `0.0.2`), then push a matching
tag (`v0.0.2`). CI publishes a release with both downloads, and refuses to if the tag and
the VERSION file disagree.

## License

[MIT](LICENSE.md) © 2026 Filipe Lopes Pires
