# Roadmap

FontInstallerTool installs every `.ttf` and `.otf` font in a folder from one right-click.
Different people want different amounts of polish, so the tool is planned as a set of
editions ("tiers"). They all share the same font-installing core. Each tier adds a better
way to install the tool, or a smarter menu entry.

| Tier | Edition | For | Status |
|------|---------|-----|--------|
| 1 | Script edition | Developers who are comfortable with PowerShell | Available |
| 2 | Installer edition | Anyone who wants a normal setup wizard and an uninstall entry | Planned |
| 3 | Smart menu | Users who want the entry shown only where it makes sense | Idea |
| 4 | Store edition | Everyone, including non-technical users | Idea |

None of the tiers need administrator rights. Fonts are always installed for the current
user only.

## Tier 1: Script edition (available)

Two PowerShell scripts, `install.ps1` and `uninstall.ps1`, copy a small worker script into
your user profile and register a context menu entry.

- The entry is in the classic context menu. On Windows 11 it is under **Show more options**,
  or press Shift+Right-click.
- The entry shows in every folder. In a folder with no fonts, clicking it shows
  "No fonts found".
- Fonts that are already installed are skipped. A summary dialog lists what was installed,
  skipped or failed.
- No code signing is needed and nothing needs compiling.

## Tier 2: Installer edition (planned)

The same tool, delivered as a standard Windows setup program built with Inno Setup.

- It shows up in **Settings › Apps › Installed apps** and can be uninstalled from there.
- It installs per-user, so there is no administrator (UAC) prompt.
- It takes over from a Tier 1 installation if it finds one, so you never get two menu
  entries.
- The installer is not code-signed. The first time you run it, Windows SmartScreen may show
  "Windows protected your PC". Choose **More info › Run anyway**. That is a warning, not a
  block.
- Later it could also be published through `winget` and Scoop, which accept unsigned
  installers.

## Tier 3: Smart menu (idea)

The menu entry is hidden, or greyed out, in folders that contain no supported fonts.

- A plain registry entry can't look inside a folder. This needs a small shell extension:
  a C++ DLL that implements `IExplorerCommand`. Its `GetState` method checks the folder and
  returns hidden, disabled or enabled.
- It is registered per-user and appears in the classic menu. The classic menu loads unsigned
  handlers, so **no code signing is needed**.
- The check only needs to find the first matching file, so right-clicking stays instant even
  in large folders.
- It would ship inside the Tier 2 installer, not as a separate download.
- Written in C++ rather than C#, because Explorer loads the DLL into its own process and
  Microsoft advises against managed code there.

## Tier 4: Store edition (idea)

The entry appears at the top level of the Windows 11 context menu, with no need for
**Show more options**.

- The Windows 11 menu only shows commands from apps that have package identity (MSIX).
  Every MSIX package must be signed by a certificate the machine trusts.
- A self-signed certificate would mean asking users to import it into their trusted
  certificates. That is worse than the SmartScreen warning, so it is not an option.
- Two ways to avoid buying a certificate:
  - **Microsoft Store**: the Store signs the package itself and also handles updates.
  - **Azure Trusted Signing**: a low-cost signing service. Who can use it depends on
    country and account type.
- It reuses the Tier 3 DLL, because the same `IExplorerCommand` class works for both menus.
  Tier 4 is mostly packaging work, not new code.

## Known limitations (all tiers)

- If your organisation enforces a PowerShell execution policy through Group Policy, the menu
  command may be blocked. Moving the font-installing logic into native code (a possible part
  of Tier 3) would remove that dependency.
- Fonts are installed for the current user only. A few older applications only see fonts
  installed for all users.
