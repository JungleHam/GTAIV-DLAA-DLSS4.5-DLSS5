#define MyAppName "GTA IV DLSS Setup & Maintenance"
#define MyAppVersion "1.0-rc1"
#define MyPublisher "JungleHam"
#define MyRepo "https://github.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5"

[Setup]
AppId={{7E0329D7-03F6-4C99-9D92-C6757AF2E672}
AppName={#MyAppName}
AppVersion={#MyAppVersion}
AppPublisher={#MyPublisher}
AppPublisherURL={#MyRepo}
AppSupportURL={#MyRepo}/issues
DefaultDirName={tmp}\GTAIV-DLSS-Setup
CreateAppDir=no
DisableProgramGroupPage=yes
PrivilegesRequired=admin
PrivilegesRequiredOverridesAllowed=dialog
OutputDir=out
OutputBaseFilename=GTAIV-DLSS-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
Uninstallable=no

[Files]
Source: "..\install\Install-DLAA.bat"; Flags: dontcopy
Source: "..\install\Install-DLSS-Full.bat"; Flags: dontcopy
Source: "..\install\Uninstall-DLSS-Full.bat"; Flags: dontcopy
Source: "..\install\Uninstall-DLAA.bat"; Flags: dontcopy
Source: "Run-Action.ps1"; Flags: dontcopy

[Code]
var
  GamePage: TInputDirWizardPage;
  ActionPage: TInputOptionWizardPage;
  GameDir: string;
  SelectedAction: Integer;
  DetectedDLAA: Boolean;
  DetectedFull: Boolean;

function QuoteArg(const S: string): string;
begin
  Result := '"' + S + '"';
end;

function NormalizeGameDir(const Input: string): string;
var
  P: string;
begin
  P := RemoveBackslashUnlessRoot(Trim(Input));
  if FileExists(AddBackslash(P) + 'GTAIV.exe') then
  begin
    Result := P;
    exit;
  end;

  if FileExists(AddBackslash(P) + 'GTAIV\GTAIV.exe') then
  begin
    Result := AddBackslash(P) + 'GTAIV';
    exit;
  end;

  Result := '';
end;

procedure DetectCurrentState;
begin
  DetectedFull :=
    FileExists(AddBackslash(GameDir) + '.trex\m3k-nr.ini') or
    FileExists(AddBackslash(GameDir) + 'DLSS_FULL_INSTALLED.txt');

  DetectedDLAA := DetectedFull or
    (FileExists(AddBackslash(GameDir) + 'DLAA_INSTALL_MANIFEST.txt') and
     FileExists(AddBackslash(GameDir) + '.trex\NvRemixBridge.exe') and
     FileExists(AddBackslash(GameDir) + '.trex\dlss5-feed.addon64'));
end;

function GetSelectedActionIndex: Integer;
var
  I: Integer;
begin
  Result := -1;
  for I := 0 to 3 do
    if ActionPage.Values[I] then
    begin
      Result := I;
      exit;
    end;
end;

function ActionCode(Index: Integer): string;
begin
  case Index of
    0: Result := 'DLAA';
    1: Result := 'FULL';
    2: Result := 'REMOVE_FULL';
    3: Result := 'REMOVE_ALL';
  else
    Result := '';
  end;
end;

function ActionTitle(Index: Integer): string;
begin
  case Index of
    0: Result := 'Install / repair DLAA';
    1: Result := 'Install / repair Full DLSS';
    2: Result := 'Remove DLSS Full only (keep DLAA)';
    3: Result := 'Remove everything from this project (keep FusionFix)';
  else
    Result := 'Unknown action';
  end;
end;

procedure InitializeWizard;
begin
  WizardForm.Caption := '{#MyAppName}';

  GamePage := CreateInputDirPage(
    wpWelcome,
    'Select GTA IV',
    'Choose the folder that contains GTAIV.exe',
    'Select your GTA IV: Complete Edition folder. FusionFix must already be installed, then click Next.',
    False,
    '');
  GamePage.Add('');

  ActionPage := CreateInputOptionPage(
    GamePage.ID,
    'Install, modify, or remove',
    'Choose one action',
    'Full DLSS automatically installs the DLAA + ReShade foundation first, so installation order cannot be wrong.',
    True,
    False);
  ActionPage.Add('Install / repair DLAA  —  DLAA + ReShade + input patch');
  ActionPage.Add('Install / repair Full DLSS  —  everything above + DLSS 4.5 + DLSS 5 Neural Rendering');
  ActionPage.Add('Remove DLSS Full only  —  return to the preserved DLAA setup');
  ActionPage.Add('Remove everything from this project  —  return to GTA IV + FusionFix');
  ActionPage.Values[1] := True;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var
  P: string;
  ShellResult: Integer;
begin
  Result := True;

  if CurPageID = GamePage.ID then
  begin
    P := NormalizeGameDir(GamePage.Values[0]);
    if P = '' then
    begin
      MsgBox('GTAIV.exe was not found in that folder.', mbError, MB_OK);
      Result := False;
      exit;
    end;

    if not FileExists(AddBackslash(P) + 'dinput8.dll') then
    begin
      if MsgBox(
        'FusionFix was not detected (dinput8.dll is missing).' + #13#10 + #13#10 +
        'Install FusionFix first, launch GTA IV once, close it, then run this setup again.' + #13#10 + #13#10 +
        'Open the FusionFix download page now?',
        mbError,
        MB_YESNO) = IDYES then
        ShellExec('open', 'https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix', '', '', SW_SHOWNORMAL, ewNoWait, ShellResult);
      Result := False;
      exit;
    end;

    GameDir := P;
    GamePage.Values[0] := P;
    DetectCurrentState;

    ActionPage.Values[0] := False;
    ActionPage.Values[1] := False;
    ActionPage.Values[2] := False;
    ActionPage.Values[3] := False;

    if DetectedFull then
      ActionPage.Values[1] := True
    else if DetectedDLAA then
      ActionPage.Values[0] := True
    else
      ActionPage.Values[1] := True;
  end
  else if CurPageID = ActionPage.ID then
  begin
    SelectedAction := GetSelectedActionIndex;
    if SelectedAction < 0 then
    begin
      MsgBox('Choose an action.', mbError, MB_OK);
      Result := False;
      exit;
    end;

    DetectCurrentState;
    if (SelectedAction = 2) and (not DetectedFull) then
    begin
      MsgBox('DLSS Full is not detected in this GTA IV folder.', mbInformation, MB_OK);
      Result := False;
      exit;
    end;

    if (SelectedAction = 3) and (not DetectedDLAA) then
    begin
      MsgBox('No DLAA/DLSS installation from this project is detected in this folder.', mbInformation, MB_OK);
      Result := False;
      exit;
    end;
  end;
end;

function UpdateReadyMemo(
  Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo,
  MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result :=
    'GTA IV folder:' + NewLine +
    '  ' + GameDir + NewLine + NewLine +
    'Action:' + NewLine +
    '  ' + ActionTitle(SelectedAction) + NewLine + NewLine +
    'The setup uses the project''s verified prebuilt release assets. No Git, Python, Visual Studio, or manual ReShade installation is required.';
end;

procedure ExtractSetupFiles;
begin
  ExtractTemporaryFile('Install-DLAA.bat');
  ExtractTemporaryFile('Install-DLSS-Full.bat');
  ExtractTemporaryFile('Uninstall-DLSS-Full.bat');
  ExtractTemporaryFile('Uninstall-DLAA.bat');
  ExtractTemporaryFile('Run-Action.ps1');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  PowerShell: string;
  Args: string;
  ResultCode: Integer;
begin
  if CurStep = ssInstall then
  begin
    ExtractSetupFiles;
    WizardForm.StatusLabel.Caption := ActionTitle(SelectedAction) + '...';

    PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    Args :=
      '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' +
      QuoteArg(ExpandConstant('{tmp}\Run-Action.ps1')) +
      ' -Action ' + ActionCode(SelectedAction) +
      ' -Game ' + QuoteArg(GameDir);

    if not Exec(PowerShell, Args, GameDir, SW_SHOW, ewWaitUntilTerminated, ResultCode) then
      RaiseException('Could not start the setup action.');

    if ResultCode <> 0 then
      RaiseException('The selected action failed. Review the console output and installer log for details.');
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    case SelectedAction of
      0: WizardForm.FinishedLabel.Caption := 'DLAA + ReShade input patch is installed. Launch GTA IV and press Home to verify the ReShade menu.';
      1: WizardForm.FinishedLabel.Caption := 'Full DLSS is installed. Keep GTA IV set to your display native resolution, then use Home → Add-ons → DLSS 5 Feed → GTA IV DLSS.';
      2: WizardForm.FinishedLabel.Caption := 'DLSS Full was removed. The preserved DLAA setup remains installed.';
      3: WizardForm.FinishedLabel.Caption := 'This project was removed. GTA IV has been returned to the saved FusionFix baseline.';
    end;
  end;
end;
