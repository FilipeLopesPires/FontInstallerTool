# Installer Edition (Tier 2) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship FontInstallerTool as two downloadable editions: the existing Script edition (Tier 1) and a new per-user Inno Setup installer (Tier 2). The repo landing page should let a visitor choose one in seconds.

**Architecture:** Both editions install the same unchanged worker, `src/Install-Fonts.ps1`, and register the same HKCU context menu key. So only one menu entry can ever exist. The Script edition moves to `script/`. The installer is defined in `installer/FontInstallerTool.iss`. `build/build.ps1` produces two release assets with stable names, so the README can link to `releases/latest/download/<asset>`. A single GitHub Actions workflow builds and tests on every push, and publishes a GitHub Release when a `v*` tag is pushed.

**Tech Stack:** Windows PowerShell 5.1, Inno Setup 6, Pester 5, GitHub Actions (`windows-latest`), `gh` CLI.

**Spec:** [ROADMAP.md](../../../ROADMAP.md) (Tier 1 and Tier 2 sections), plus the decisions below.

## Global Constraints

- No administrator rights anywhere. Installer: `PrivilegesRequired=lowest`. All registry writes go to HKCU.
- Menu key, shared by both editions: `HKCU\Software\Classes\Directory\Background\shell\FontInstallerTool`
- Menu command: `conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File "<worker path>" -Path "%V"`
- Menu values: `MUIVerb` = `Install fonts in this folder`, `Icon` (REG_EXPAND_SZ) = `%SystemRoot%\System32\fontext.dll,0`
- Installer AppId (never change it, because upgrades and detection depend on it): `{982F438F-8A78-4107-992B-7029A29DAEF7}`
- Installer edition's uninstall registry key: `HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{982F438F-8A78-4107-992B-7029A29DAEF7}_is1`
- Install folders: Script edition `%LOCALAPPDATA%\FontInstallerTool`. Installer edition `%LOCALAPPDATA%\Programs\FontInstallerTool` (Inno's `{autopf}` under lowest privileges).
- Release asset names, with no version in the name: `FontInstallerTool-Setup.exe`, `FontInstallerTool-Script.zip`
- Minimum Windows: 10 version 1809 (`10.0.17763`), the first version with per-user fonts.
- The installer is not code-signed. Docs must explain the SmartScreen "More info › Run anyway" step.
- `src/Install-Fonts.ps1` is not modified by this plan.
- **Commits:** the repo owner approves each commit personally. Every "Commit checkpoint" step means: stop, summarise the changes, propose the message shown, and wait. Never run `git commit` without that approval.

## File Structure

```
README.md                          MODIFY  landing page: pick an edition, download links
ROADMAP.md                         MODIFY  mark Tier 2 as available (Task 5)
.gitignore                         CREATE  ignore dist/
src/Install-Fonts.ps1              (unchanged) shared worker
script/install.ps1                 MOVE from ./install.ps1 + worker lookup, unblock, edition guard
script/uninstall.ps1               MOVE from ./uninstall.ps1 + edition guard
script/README.md                   CREATE  Script edition usage
installer/FontInstallerTool.iss    CREATE  Inno Setup definition
installer/README.md                CREATE  Installer edition usage + how to build it
build/build.ps1                    CREATE  builds both assets into an output folder
tests/Install-Fonts.Tests.ps1      (unchanged) unit tests for the worker
tests/Build.Tests.ps1              CREATE  checks the zip layout
tests/Integration.Tests.ps1        CREATE  real install/uninstall round trips, tag "Integration"
.github/workflows/build.yml        CREATE  build + test on push/PR, release on tag
docs/images/                       CREATE  screenshots used by README (user supplies)
```

**Running tests** (used by every task):
- Unit and build tests only, safe on your own machine:
  `Invoke-Pester -Path tests -ExcludeTagFilter Integration -Output Detailed`
- Everything: `Invoke-Pester -Path tests -Output Detailed`
  **Warning:** the integration tests install and uninstall the real tool. They remove any existing FontInstallerTool installation on the machine. CI always runs them. Run them locally only when you are happy to reinstall afterwards.

Pester 5 is required (Windows ships with 3.4): `Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck`

---

### Task 1: Move the Script edition to `script/` and make it edition-aware

**Files:**
- Move: `install.ps1` → `script/install.ps1`, `uninstall.ps1` → `script/uninstall.ps1` (use `git mv` so history is kept)
- Create: `.gitignore`, `tests/Integration.Tests.ps1`

**Interfaces:**
- Produces:
  - `script/install.ps1` works from two places: a repo clone (worker in `..\src`) and the flat release zip (worker next to it).
  - Both scripts throw an error containing `Installer edition` when the Installer edition is installed.
  - `tests/Integration.Tests.ps1` has a shared `BeforeAll` with `$repo`, `$menuKey`, `$scriptDir`, `$installerDir`, `$installerUninstallKey`, `Reset-FontInstallerTool` and `Wait-Condition`. Task 3 adds a `Describe` block to this file.

- [ ] **Step 1: Move the scripts and ignore build output**

```powershell
New-Item -ItemType Directory script | Out-Null
git mv install.ps1 script/install.ps1
git mv uninstall.ps1 script/uninstall.ps1
Set-Content .gitignore 'dist/' -Encoding ascii
```

- [ ] **Step 2: Write the failing integration tests**

Create `tests/Integration.Tests.ps1`:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

# These tests install and uninstall the real tool on this machine.
# Excluded locally with: Invoke-Pester -Path tests -ExcludeTagFilter Integration

BeforeAll {
    $repo                  = Split-Path $PSScriptRoot -Parent
    $menuKey               = 'HKCU:\Software\Classes\Directory\Background\shell\FontInstallerTool'
    $scriptDir             = Join-Path $env:LOCALAPPDATA 'FontInstallerTool'
    $installerDir          = Join-Path $env:LOCALAPPDATA 'Programs\FontInstallerTool'
    $installerUninstallKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{982F438F-8A78-4107-992B-7029A29DAEF7}_is1'

    function Wait-Condition {
        param([Parameter(Mandatory)][scriptblock]$Condition, [int]$TimeoutSeconds = 30)
        $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
        while (-not (& $Condition)) {
            if ((Get-Date) -gt $deadline) { throw "Timed out after $TimeoutSeconds s waiting for: $Condition" }
            Start-Sleep -Milliseconds 250
        }
    }

    function Get-MenuCommand {
        (Get-Item -LiteralPath "$menuKey\command").GetValue('')
    }

    # Removes both editions, so every Describe block starts from a clean machine
    function Reset-FontInstallerTool {
        $uninstaller = Join-Path $installerDir 'unins000.exe'
        if (Test-Path -LiteralPath $uninstaller) {
            Start-Process $uninstaller -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES' -Wait
            # The Inno uninstaller relaunches itself from %TEMP%, so -Wait can return early
            Wait-Condition { -not (Test-Path -LiteralPath $installerUninstallKey) }
        }
        Remove-Item -LiteralPath $installerUninstallKey -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $menuKey -Recurse -Force -ErrorAction SilentlyContinue
        Remove-Item -LiteralPath $scriptDir -Recurse -Force -ErrorAction SilentlyContinue
    }
}

Describe 'Script edition' -Tag Integration {
    BeforeAll { Reset-FontInstallerTool }
    AfterAll { Reset-FontInstallerTool }

    It 'installs from a repository clone' {
        & (Join-Path $repo 'script\install.ps1') | Out-Null

        Join-Path $scriptDir 'Install-Fonts.ps1' | Should -Exist
        Get-MenuCommand | Should -BeLike "*-File `"$scriptDir\Install-Fonts.ps1`" -Path `"%V`""
    }

    It 'uninstalls completely' {
        & (Join-Path $repo 'script\uninstall.ps1') | Out-Null

        $menuKey | Should -Not -Exist
        $scriptDir | Should -Not -Exist
    }

    It 'installs from the flat release zip layout' {
        $flat = Join-Path $TestDrive 'flat'
        New-Item -ItemType Directory $flat | Out-Null
        Copy-Item (Join-Path $repo 'script\install.ps1'), (Join-Path $repo 'src\Install-Fonts.ps1') $flat

        & (Join-Path $flat 'install.ps1') | Out-Null

        Join-Path $scriptDir 'Install-Fonts.ps1' | Should -Exist
    }

    Context 'when the Installer edition is installed' {
        BeforeAll { New-Item -Path $installerUninstallKey -Force | Out-Null }
        AfterAll { Remove-Item -LiteralPath $installerUninstallKey -Recurse -Force }

        It 'install.ps1 refuses to run' {
            { & (Join-Path $repo 'script\install.ps1') } | Should -Throw '*Installer edition*'
        }

        It 'uninstall.ps1 refuses to remove the installer''s menu entry' {
            { & (Join-Path $repo 'script\uninstall.ps1') } | Should -Throw '*Installer edition*'
        }
    }
}
```

- [ ] **Step 3: Run the tests and confirm they fail**

Run: `Invoke-Pester -Path tests\Integration.Tests.ps1 -Output Detailed`
Expected: FAIL.
- Both install tests throw "Cannot find path '...\script\src\Install-Fonts.ps1'". The moved script still looks in `$PSScriptRoot\src`.
- The `install.ps1` guard test fails because it gets that same error instead of one mentioning the Installer edition.
- The `uninstall.ps1` guard test fails because nothing is thrown.

- [ ] **Step 4: Update `script/install.ps1`**

Replace everything from `$ErrorActionPreference = 'Stop'` down to the `Copy-Item` line with:

```powershell
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
```

Everything after that stays as it is: the `$command` line, the registry block and the `Write-Host` lines.

- [ ] **Step 5: Update `script/uninstall.ps1`**

Insert this after the `$menuSubKey` line:

```powershell
# Must match AppId in installer\FontInstallerTool.iss
$installerEditionKey = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\{982F438F-8A78-4107-992B-7029A29DAEF7}_is1'

# Both editions share the menu key; removing it here would break the Installer edition
if (Test-Path -LiteralPath $installerEditionKey) {
    throw 'The Installer edition of FontInstallerTool is installed. Uninstall it from Settings > Apps instead.'
}
```

- [ ] **Step 6: Run all tests and confirm they pass**

Run: `Invoke-Pester -Path tests -Output Detailed`
Expected: PASS. That is the 13 existing unit tests plus 5 Script edition integration tests.

- [ ] **Step 7: Commit checkpoint**

Proposed message: `refactor: move script edition to script/ and guard against installer edition`

---

### Task 2: Build script and Script edition zip

**Files:**
- Create: `build/build.ps1`, `tests/Build.Tests.ps1`

**Interfaces:**
- Consumes: `script/install.ps1`, `script/uninstall.ps1` (Task 1), `src/Install-Fonts.ps1`
- Produces: `build/build.ps1 [-Version <x.y.z>] [-OutputDir <path>] [-SkipInstaller]`.
  - It writes `<OutputDir>\FontInstallerTool-Script.zip` with the three scripts at the zip root.
  - Unless `-SkipInstaller` is given, it also writes `<OutputDir>\FontInstallerTool-Setup.exe` (Task 3 provides the `.iss`).
  - `-OutputDir` defaults to `<repo>\dist` and `-Version` to `0.0.0`.

- [ ] **Step 1: Write the failing test**

Create `tests/Build.Tests.ps1`:

```powershell
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0' }

BeforeAll {
    $repo = Split-Path $PSScriptRoot -Parent
    $out  = Join-Path $TestDrive 'dist'
    & (Join-Path $repo 'build\build.ps1') -OutputDir $out -SkipInstaller
    $zip  = Join-Path $out 'FontInstallerTool-Script.zip'
}

Describe 'build.ps1 -SkipInstaller' {
    It 'creates the Script edition zip' {
        $zip | Should -Exist
    }

    It 'puts exactly the three scripts at the zip root' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::OpenRead($zip)
        try { $names = @($archive.Entries.FullName | Sort-Object) } finally { $archive.Dispose() }

        $names | Should -Be @(@('install.ps1', 'uninstall.ps1', 'Install-Fonts.ps1') | Sort-Object)
    }

    It 'does not build the installer' {
        Join-Path $out 'FontInstallerTool-Setup.exe' | Should -Not -Exist
    }

    It 'leaves no staging folder behind' {
        @(Get-ChildItem $out -Directory).Count | Should -Be 0
    }
}
```

- [ ] **Step 2: Run the test and confirm it fails**

Run: `Invoke-Pester -Path tests\Build.Tests.ps1 -Output Detailed`
Expected: FAIL with "The term '...\build\build.ps1' is not recognized".

- [ ] **Step 3: Write `build/build.ps1`**

```powershell
<#
.SYNOPSIS
    Builds the FontInstallerTool release assets.

.DESCRIPTION
    Produces FontInstallerTool-Script.zip (Script edition) and, unless -SkipInstaller
    is given, FontInstallerTool-Setup.exe (Installer edition, needs Inno Setup 6).
    Asset names carry no version so README links to releases/latest/download keep working.

.PARAMETER Version
    Version stamped into the installer, e.g. 1.2.0.

.PARAMETER OutputDir
    Folder that receives the assets. It is emptied first.

.PARAMETER SkipInstaller
    Only build the zip, so Inno Setup is not required.
#>
[CmdletBinding()]
param(
    [ValidatePattern('^\d+\.\d+\.\d+$')]
    [string]$Version = '0.0.0',

    [string]$OutputDir = (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist'),

    [switch]$SkipInstaller
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path $PSScriptRoot -Parent

if (Test-Path -LiteralPath $OutputDir) { Remove-Item -LiteralPath $OutputDir -Recurse -Force }
New-Item -ItemType Directory -Path $OutputDir | Out-Null

# Script edition: a flat zip, where install.ps1 finds the worker next to itself
$staging = Join-Path $OutputDir 'script-staging'
New-Item -ItemType Directory -Path $staging | Out-Null
Copy-Item -Destination $staging -LiteralPath @(
    (Join-Path $repo 'script\install.ps1'),
    (Join-Path $repo 'script\uninstall.ps1'),
    (Join-Path $repo 'src\Install-Fonts.ps1'))
Compress-Archive -Path (Join-Path $staging '*') -DestinationPath (Join-Path $OutputDir 'FontInstallerTool-Script.zip')
Remove-Item -LiteralPath $staging -Recurse -Force
Write-Host "Built $(Join-Path $OutputDir 'FontInstallerTool-Script.zip')"

if ($SkipInstaller) { return }

$iscc = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue).Source,
    "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe",
    "$env:ProgramFiles\Inno Setup 6\ISCC.exe",
    "$env:LOCALAPPDATA\Programs\Inno Setup 6\ISCC.exe"
) | Where-Object { $_ -and (Test-Path -LiteralPath $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 was not found. Install it with: winget install JRSoftware.InnoSetup' }

& $iscc "/DAppVersion=$Version" "/O$OutputDir" (Join-Path $repo 'installer\FontInstallerTool.iss')
if ($LASTEXITCODE -ne 0) { throw "Inno Setup compiler failed with exit code $LASTEXITCODE" }
Write-Host "Built $(Join-Path $OutputDir 'FontInstallerTool-Setup.exe')"
```

- [ ] **Step 4: Run the tests and confirm they pass**

Run: `Invoke-Pester -Path tests -ExcludeTagFilter Integration -Output Detailed`
Expected: PASS. That is 13 unit tests plus 4 build tests.

- [ ] **Step 5: Commit checkpoint**

Proposed message: `build: add build script producing the script edition zip`

---

### Task 3: Inno Setup installer

**Files:**
- Create: `installer/FontInstallerTool.iss`
- Modify: `tests/Integration.Tests.ps1` (append a `Describe` block)

**Interfaces:**
- Consumes: `build/build.ps1` (Task 2) and the helpers in `tests/Integration.Tests.ps1` (Task 1).
- Produces: `FontInstallerTool-Setup.exe`. It installs to `%LOCALAPPDATA%\Programs\FontInstallerTool`, writes the shared menu key, and appears in Installed apps as `FontInstallerTool`. It removes a Script edition install if it finds one, and its uninstaller is `unins000.exe`.

- [ ] **Step 1: Install Inno Setup 6 (one-time, ask the repo owner first)**

Run: `winget install JRSoftware.InnoSetup`
Expected: `ISCC.exe` exists under `%LOCALAPPDATA%\Programs\Inno Setup 6` or `Program Files (x86)\Inno Setup 6`.

- [ ] **Step 2: Write the failing integration tests**

Add to `tests/Integration.Tests.ps1`:
- a `BeforeDiscovery` block at the top of the file, right after the `#Requires` line
- the `Describe` block at the end of the file

```powershell
BeforeDiscovery {
    # Tier 2 tests need a built installer: .\build\build.ps1
    $setupMissing = -not (Test-Path (Join-Path (Split-Path $PSScriptRoot -Parent) 'dist\FontInstallerTool-Setup.exe'))
}
```

```powershell
Describe 'Installer edition' -Tag Integration -Skip:$setupMissing {
    BeforeAll {
        Reset-FontInstallerTool
        $setup = Join-Path $repo 'dist\FontInstallerTool-Setup.exe'

        function Invoke-Setup {
            Start-Process $setup -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES', '/NORESTART' -Wait
        }
    }
    AfterAll { Reset-FontInstallerTool }

    It 'takes over an existing Script edition install' {
        & (Join-Path $repo 'script\install.ps1') | Out-Null

        Invoke-Setup

        $scriptDir | Should -Not -Exist
        Get-MenuCommand | Should -BeLike "*-File `"$installerDir\Install-Fonts.ps1`" -Path `"%V`""
    }

    It 'installs the worker and registers the menu entry' {
        Join-Path $installerDir 'Install-Fonts.ps1' | Should -Exist
        $menu = Get-Item -LiteralPath $menuKey
        $menu.GetValue('MUIVerb') | Should -Be 'Install fonts in this folder'
        $menu.GetValue('Icon', $null, 'DoNotExpandEnvironmentNames') | Should -Be '%SystemRoot%\System32\fontext.dll,0'
        Get-MenuCommand | Should -BeLike 'conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File *'
    }

    It 'appears in Installed apps' {
        (Get-ItemProperty -LiteralPath $installerUninstallKey).DisplayName | Should -Be 'FontInstallerTool'
    }

    It 'uninstalls completely' {
        Start-Process (Join-Path $installerDir 'unins000.exe') -ArgumentList '/VERYSILENT', '/SUPPRESSMSGBOXES' -Wait
        Wait-Condition { -not (Test-Path -LiteralPath $installerUninstallKey) }
        Wait-Condition { -not (Test-Path -LiteralPath $installerDir) }

        $menuKey | Should -Not -Exist
    }
}
```

- [ ] **Step 3: Confirm the tests fail**

Run: `.\build\build.ps1`
Expected: FAIL with an ISCC error that `installer\FontInstallerTool.iss` does not exist. (Without a setup exe, the Tier 2 tests would only show as skipped. The build failing is the real red state here.)

- [ ] **Step 4: Write `installer/FontInstallerTool.iss`**

```ini
; Inno Setup 6 script for the FontInstallerTool Installer edition.
; Build with: .\build\build.ps1   (passes /DAppVersion and /O<output dir>)

#ifndef AppVersion
  #define AppVersion "0.0.0"
#endif

#define AppName "FontInstallerTool"
#define MenuKey "Software\Classes\Directory\Background\shell\FontInstallerTool"

[Setup]
; Never change AppId: upgrades and the Script edition's guard depend on it
AppId={{982F438F-8A78-4107-992B-7029A29DAEF7}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher=Filipe Pires
AppPublisherURL=https://github.com/FilipeLopesPires/FontInstallerTool
AppSupportURL=https://github.com/FilipeLopesPires/FontInstallerTool/issues
VersionInfoVersion={#AppVersion}
; Per-user install: no UAC prompt, {autopf} becomes %LOCALAPPDATA%\Programs
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
MinVersion=10.0.17763
OutputDir=..\dist
OutputBaseFilename=FontInstallerTool-Setup
UninstallDisplayName={#AppName}
UninstallDisplayIcon={sys}\fontext.dll,0
Compression=lzma2
SolidCompression=yes
WizardStyle=modern

[Files]
Source: "..\src\Install-Fonts.ps1"; DestDir: "{app}"; Flags: ignoreversion

[InstallDelete]
; Take over from a Script edition install (the menu key itself is overwritten below)
Type: filesandordirs; Name: "{localappdata}\FontInstallerTool"

[Registry]
Root: HKCU; Subkey: "{#MenuKey}"; Flags: uninsdeletekey
Root: HKCU; Subkey: "{#MenuKey}"; ValueType: string; ValueName: "MUIVerb"; ValueData: "Install fonts in this folder"
Root: HKCU; Subkey: "{#MenuKey}"; ValueType: expandsz; ValueName: "Icon"; ValueData: "%SystemRoot%\System32\fontext.dll,0"
; conhost --headless runs PowerShell without a console window flashing on screen
Root: HKCU; Subkey: "{#MenuKey}\command"; ValueType: string; ValueName: ""; ValueData: "conhost.exe --headless powershell.exe -NoProfile -ExecutionPolicy Bypass -File ""{app}\Install-Fonts.ps1"" -Path ""%V"""

[Messages]
FinishedLabel=Setup has installed [name].%n%nRight-click an empty area inside any folder (on Windows 11, choose Show more options first) and pick "Install fonts in this folder".
```

- [ ] **Step 5: Build, then run all tests**

Run: `.\build\build.ps1; Invoke-Pester -Path tests -Output Detailed`
Expected: the build prints both "Built ..." lines. All tests pass, including 4 Installer edition tests.

- [ ] **Step 6: Manual check of the wizard (repo owner)**

1. Double-click `dist\FontInstallerTool-Setup.exe`. There is no UAC prompt, and the finish page shows the usage text.
2. **Settings › Apps › Installed apps** lists FontInstallerTool with the font icon.
3. Right-click a folder that contains fonts, then pick the entry. The fonts install.
4. Uninstall from Settings. The menu entry is gone.

- [ ] **Step 7: Commit checkpoint**

Proposed message: `feat: add per-user Inno Setup installer edition`

---

### Task 4: GitHub Actions build, test and release

**Files:**
- Create: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `build/build.ps1 -Version`, and every test in `tests/`.
- Produces:
  - On every push or PR: a workflow artifact `FontInstallerTool` holding both assets.
  - On a `vX.Y.Z` tag: a GitHub Release with both assets attached.

- [ ] **Step 1: Write the workflow**

```yaml
name: Build

on:
  push:
    branches: [main]
    tags: ['v*.*.*']
  pull_request:

permissions:
  contents: write   # needed to create releases on tags

jobs:
  build:
    runs-on: windows-latest
    defaults:
      run:
        shell: powershell
    steps:
      - uses: actions/checkout@v4

      - name: Install Pester 5 and Inno Setup
        run: |
          Install-Module Pester -MinimumVersion 5.0 -Scope CurrentUser -Force -SkipPublisherCheck
          if (-not (Test-Path "${env:ProgramFiles(x86)}\Inno Setup 6\ISCC.exe")) {
            choco install innosetup -y --no-progress
          }

      - name: Build
        run: |
          $version = if ($env:GITHUB_REF_TYPE -eq 'tag') { $env:GITHUB_REF_NAME.TrimStart('v') } else { '0.0.0' }
          .\build\build.ps1 -Version $version

      - name: Test (unit, build and integration)
        run: |
          $config = New-PesterConfiguration
          $config.Run.Path = 'tests'
          $config.Run.Exit = $true
          $config.Output.Verbosity = 'Detailed'
          Invoke-Pester -Configuration $config

      - uses: actions/upload-artifact@v4
        with:
          name: FontInstallerTool
          path: dist/*

      - name: Publish release
        if: github.ref_type == 'tag'
        env:
          GH_TOKEN: ${{ github.token }}
        run: gh release create $env:GITHUB_REF_NAME dist\FontInstallerTool-Setup.exe dist\FontInstallerTool-Script.zip --title $env:GITHUB_REF_NAME --generate-notes
```

- [ ] **Step 2: Check the YAML parses locally**

Run: `python -c "import yaml,sys; yaml.safe_load(open('.github/workflows/build.yml'))"` if Python is available. Otherwise skip; the first push validates it.
Expected: no output.

- [ ] **Step 3: Commit checkpoint, then push (repo owner)**

Proposed message: `ci: build, test and release both editions on GitHub Actions`
After the owner pushes to `main`, open the **Actions** tab. Expected: the run is green, and the `FontInstallerTool` artifact contains both files. If an integration test fails only on CI, check whether `conhost` or Inno timings differ on the runner before changing the code.

---

### Task 5: Landing page and edition docs

**Files:**
- Modify: `README.md`, `ROADMAP.md`
- Create: `script/README.md`, `installer/README.md`, `docs/images/` (screenshots)

**Interfaces:**
- Consumes: asset names and URLs from Task 4. Download links are `https://github.com/FilipeLopesPires/FontInstallerTool/releases/latest/download/<asset>`.

- [ ] **Step 1: Screenshots (repo owner)**

Save two PNGs:
- `docs/images/context-menu.png`: the right-click menu with the entry visible
- `docs/images/summary-dialog.png`: the dialog after installing a few fonts

Keep each under about 300 KB.

- [ ] **Step 2: Replace `README.md`**

````markdown
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
them on every push. Tagging `vX.Y.Z` publishes a release with both downloads.

## License

[MIT](LICENSE.md) © 2026 Filipe Lopes Pires
````

- [ ] **Step 3: Write `script/README.md`**

````markdown
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
````

- [ ] **Step 4: Write `installer/README.md`**

````markdown
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
.\build\build.ps1 -Version 1.0.0
```

The output is `dist\FontInstallerTool-Setup.exe` and `dist\FontInstallerTool-Script.zip`.
The definition is in [FontInstallerTool.iss](FontInstallerTool.iss). Never change its
`AppId`.
````

- [ ] **Step 5: Mark Tier 2 as available in `ROADMAP.md`**

- In the table, change the Tier 2 status `Planned` to `Available`.
- Change the heading `## Tier 2: Installer edition (planned)` to `## Tier 2: Installer edition (available)`.
- In the Tier 2 bullets, replace "Later it could also be published through `winget` and Scoop, which accept unsigned installers." with "Next: publish it through `winget` and Scoop, which accept unsigned installers."

- [ ] **Step 6: Check links**

Run: `Get-ChildItem -Recurse -Filter *.md | Select-String -Pattern '\]\((?!https?://)([^)#]+)' -AllMatches | ForEach-Object { $_.Matches } | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique`
Expected: every relative path printed exists in the repo. The `releases/latest/download` links only work after the first release (Task 6).

- [ ] **Step 7: Commit checkpoint**

Proposed message: `docs: add edition picker landing page and per-edition guides`

---

### Task 6: First release (repo owner)

- [ ] **Step 1:** Make sure `main` is pushed and the latest Build run is green.
- [ ] **Step 2:** Confirm the `VERSION` file says `0.0.1`. Then tag and push: `git tag v0.0.1; git push origin v0.0.1` (only with the owner's explicit go-ahead).
- [ ] **Step 3:** Open the Releases page. Expected: `v0.0.1` with both assets attached.

> **Change after this plan was written:** the version now lives in a `VERSION` file at the repo root. `build.ps1 -Version` defaults to it, and CI fails a tag that doesn't match it. The code blocks in Tasks 2–4 show the original `0.0.0` defaults; the implemented files are the source of truth.
- [ ] **Step 4:** In a private browser window, click both README download links. Both files download.
- [ ] **Step 5:** On a clean user account (or after uninstalling), install from the downloaded `Setup.exe`. Confirm the SmartScreen flow matches what the README describes.

---

## Out of scope / open decisions

- winget/Scoop manifests, Tier 3 (smart menu DLL) and Tier 4 (Store) are covered by [ROADMAP.md](../../../ROADMAP.md) and get their own plans.
