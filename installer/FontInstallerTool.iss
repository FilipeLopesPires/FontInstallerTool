; Inno Setup 6 script for the FontInstallerTool Installer edition.
; Build with: .\build\build.ps1   (passes /DAppVersion and /O<output dir>)

; The real version comes from the VERSION file via build.ps1; this is only a
; fallback for compiling the script directly in the Inno Setup IDE
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
AppPublisher=Filipe Lopes Pires
AppPublisherURL=https://github.com/FilipeLopesPires/FontInstallerTool
AppSupportURL=https://github.com/FilipeLopesPires/FontInstallerTool/issues
VersionInfoVersion={#AppVersion}
; Per-user install: no UAC prompt, {autopf} becomes %LOCALAPPDATA%\Programs
PrivilegesRequired=lowest
DefaultDirName={autopf}\{#AppName}
DisableProgramGroupPage=yes
DisableDirPage=yes
MinVersion=10.0.17763
; 64-bit mode stops the 32-bit setup from rewriting System32 paths to SysWOW64
ArchitecturesInstallIn64BitMode=x64compatible
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
