#define MyAppName "FullTech"
#define MyAppSlug "FullTech"

; Permite overrides desde linea de comandos:
;   ISCC setup.iss /DMyAppVersion=1.0.0+1 /DMyAppVersionInfo=1.0.0.1
#ifndef MyAppVersion
  #define MyAppVersion "1.0.0+1"
#endif

#ifndef MyAppVersionInfo
  #define MyAppVersionInfo "1.0.0.1"
#endif

#define MyAppVersionFile StringChange(MyAppVersion, "+", "_")

#ifndef MyAppPublisher
  #define MyAppPublisher "FullTech"
#endif

#ifndef MyAppExeName
  #define MyAppExeName "fulltech_app.exe"
#endif

#ifndef MyAppSourceDir
  #define MyAppSourceDir "..\apps\fulltech_app\build\windows\x64\runner\Release"
#endif

#ifndef BrandSetupIcon
  #define BrandSetupIcon "..\apps\fulltech_app\windows\runner\resources\app_icon.ico"
#endif

#ifndef BrandWizardImage
  #define BrandWizardImage ""
#endif

#ifndef BrandWizardSmallImage
  #define BrandWizardSmallImage ""
#endif

#ifndef MyAppPublisherURL
  #define MyAppPublisherURL ""
#endif

#ifndef MyAppSupportURL
  #define MyAppSupportURL ""
#endif

#ifndef SupportLabel
  #define SupportLabel ""
#endif

#ifndef MyAppLicenseFile
  #define MyAppLicenseFile ""
#endif

[Setup]
AppId={{0ED49D5E-6E78-4F11-8E78-6D37FDE2078A}}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppVerName={#MyAppName} {#MyAppVersion}
AppPublisher={#MyAppPublisher}
#if MyAppPublisherURL != ""
AppPublisherURL={#MyAppPublisherURL}
#endif
#if MyAppSupportURL != ""
AppSupportURL={#MyAppSupportURL}
#endif
DefaultDirName={autopf64}\{#MyAppName}
DefaultGroupName={#MyAppName}
OutputDir=output
OutputBaseFilename=setup
SetupIconFile={#BrandSetupIcon}
#if BrandWizardImage != ""
WizardImageFile={#BrandWizardImage}
#endif
#if BrandWizardSmallImage != ""
WizardSmallImageFile={#BrandWizardSmallImage}
#endif
Compression=lzma2/max
SolidCompression=yes
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
DisableProgramGroupPage=yes
PrivilegesRequired=admin
CloseApplications=yes
RestartApplications=no
UninstallDisplayIcon={app}\{#MyAppExeName}
WizardStyle=modern
MinVersion=10.0
SetupLogging=yes
VersionInfoCompany={#MyAppPublisher}
VersionInfoDescription={#MyAppName} installer
VersionInfoProductName={#MyAppName}
VersionInfoProductTextVersion={#MyAppVersion}
VersionInfoVersion={#MyAppVersionInfo}
#if MyAppLicenseFile != ""
LicenseFile={#MyAppLicenseFile}
#endif

[Tasks]
Name: "desktopicon"; Description: "Crear icono en el escritorio"; GroupDescription: "Iconos:"; Flags: unchecked

[Files]
; Copiar todo el release de Flutter Windows.
Source: "{#MyAppSourceDir}\*"; DestDir: "{app}"; Excludes: "*.pdb,*.ilk,*.exp,*.lib"; Flags: ignoreversion recursesubdirs createallsubdirs

; Redistributables requeridos por Windows desktop.
Source: "redist\VC_redist.x64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall
Source: "redist\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; DestDir: "{tmp}"; Flags: deleteafterinstall

[Icons]
Name: "{group}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"
Name: "{group}\Abrir carpeta de instalacion"; Filename: "{app}"; WorkingDir: "{app}"
#if MyAppSupportURL != ""
Name: "{group}\Soporte"; Filename: "{#MyAppSupportURL}"
#endif
Name: "{commondesktop}\{#MyAppName}"; Filename: "{app}\{#MyAppExeName}"; WorkingDir: "{app}"; Tasks: desktopicon

[Run]
; VC++ runtime (solo si falta)
Filename: "{tmp}\VC_redist.x64.exe"; Parameters: "/install /quiet /norestart"; StatusMsg: "Instalando Microsoft Visual C++ Runtime..."; Flags: waituntilterminated; Check: NeedsVCRedist

; WebView2 runtime (solo si falta)
Filename: "{tmp}\MicrosoftEdgeWebView2RuntimeInstallerX64.exe"; Parameters: "/silent /install"; StatusMsg: "Instalando Microsoft WebView2 Runtime..."; Flags: waituntilterminated; Check: NeedsWebView2

Filename: "{app}\{#MyAppExeName}"; Description: "Abrir {#MyAppName}"; Flags: nowait postinstall skipifsilent
#if MyAppSupportURL != ""
Filename: "{#MyAppSupportURL}"; Description: "Abrir soporte"; Flags: postinstall shellexec skipifsilent unchecked
#endif

[Code]
var
  SupportAccentLabel: TNewStaticText;

function RGB(const R, G, B: Integer): Integer;
begin
  Result := (R and $FF) or ((G and $FF) shl 8) or ((B and $FF) shl 16);
end;

function IsInstalledByDisplayName(const DisplayNamePart: string): Boolean;
var
  SubKeys: TArrayOfString;
  I: Integer;
  KeyName: string;
  DisplayName: string;
begin
  Result := False;

  if RegGetSubkeyNames(HKLM, 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall', SubKeys) then
  begin
    for I := 0 to GetArrayLength(SubKeys)-1 do
    begin
      KeyName := 'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\' + SubKeys[I];
      if RegQueryStringValue(HKLM, KeyName, 'DisplayName', DisplayName) then
        if Pos(Lowercase(DisplayNamePart), Lowercase(DisplayName)) > 0 then
        begin
          Result := True;
          Exit;
        end;
    end;
  end;

  if RegGetSubkeyNames(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall', SubKeys) then
  begin
    for I := 0 to GetArrayLength(SubKeys)-1 do
    begin
      KeyName := 'SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\' + SubKeys[I];
      if RegQueryStringValue(HKLM, KeyName, 'DisplayName', DisplayName) then
        if Pos(Lowercase(DisplayNamePart), Lowercase(DisplayName)) > 0 then
        begin
          Result := True;
          Exit;
        end;
    end;
  end;
end;

function FileExistsInSystemDirs(const FileName: string): Boolean; forward;
function VcRuntimeFilesPresent(): Boolean; forward;

function NeedsVCRedist(): Boolean;
var
  Installed: Cardinal;
begin
  if not VcRuntimeFilesPresent() then
  begin
    Result := True;
    Exit;
  end;

  if RegQueryDWordValue(HKLM, 'SOFTWARE\Microsoft\VisualStudio\14.0\VC\Runtimes\x64', 'Installed', Installed) then
  begin
    Result := Installed <> 1;
    Exit;
  end;

  Result := not IsInstalledByDisplayName('Microsoft Visual C++ 2015-2022 Redistributable (x64)');
end;

function FileExistsInSystemDirs(const FileName: string): Boolean;
var
  P: string;
begin
  P := ExpandConstant('{sys}\' + FileName);
  Result := FileExists(P);

  if (not Result) and IsWin64 then
  begin
    P := ExpandConstant('{sysnative}\' + FileName);
    Result := FileExists(P);
  end;
end;

function VcRuntimeFilesPresent(): Boolean;
begin
  Result :=
    FileExistsInSystemDirs('VCRUNTIME140.dll') and
    FileExistsInSystemDirs('VCRUNTIME140_1.dll') and
    FileExistsInSystemDirs('MSVCP140.dll');
end;

function NeedsWebView2(): Boolean;
var
  Pv: string;
begin
  if RegQueryStringValue(HKLM, 'SOFTWARE\Microsoft\EdgeUpdate\Clients\{F1E7C265-6C31-4F67-BB8C-6D5F8A2A321A}', 'pv', Pv) then
  begin
    Result := Trim(Pv) = '';
    Exit;
  end;

  if RegQueryStringValue(HKLM, 'SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F1E7C265-6C31-4F67-BB8C-6D5F8A2A321A}', 'pv', Pv) then
  begin
    Result := Trim(Pv) = '';
    Exit;
  end;

  Result := not IsInstalledByDisplayName('Microsoft Edge WebView2 Runtime');
end;

procedure InitializeWizard();
begin
  WizardForm.Color := clWhite;
  WizardForm.WelcomeLabel1.Font.Color := RGB(0, 48, 176);
  WizardForm.WelcomeLabel1.Font.Style := [fsBold];
  WizardForm.WelcomeLabel2.Font.Color := clBlack;

  WizardForm.WelcomeLabel1.Caption := 'Bienvenido a ' + ExpandConstant('{#MyAppName}');
  WizardForm.WelcomeLabel2.Caption :=
    'Este asistente instalara ' + ExpandConstant('{#MyAppName}') + ' en su computadora.' + #13#10#13#10 +
    'Haga clic en "Siguiente" para continuar.';

  if (ExpandConstant('{#SupportLabel}') <> '') and (SupportAccentLabel = nil) then
  begin
    SupportAccentLabel := TNewStaticText.Create(WizardForm);
    SupportAccentLabel.Parent := WizardForm.WelcomePage;
    SupportAccentLabel.Left := WizardForm.WelcomeLabel2.Left;
    SupportAccentLabel.Top := WizardForm.WelcomeLabel2.Top + WizardForm.WelcomeLabel2.Height + ScaleY(6);
    SupportAccentLabel.AutoSize := True;
    SupportAccentLabel.Font.Style := [fsBold];
    SupportAccentLabel.Font.Color := RGB(200, 0, 0);
    SupportAccentLabel.Caption := ExpandConstant('{#SupportLabel}');
  end;
end;
