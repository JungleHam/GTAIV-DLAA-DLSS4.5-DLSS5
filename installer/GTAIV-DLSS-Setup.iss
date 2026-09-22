#define MyAppName "GTA IV DLSS Setup & Maintenance"
#define MyAppVersion "1.1.0"
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
OutputDir=out
OutputBaseFilename=GTAIV-DLSS-Setup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
SetupLogging=yes
Uninstallable=no

[Files]
Source: "..\install\Install-DLAA.bat"; Flags: dontcopy
Source: "..\install\core\Install-DLAA-Core.bat"; Flags: dontcopy; DestName: "Install-DLAA-Core.bat"
Source: "..\install\Install-DLSS-Full.bat"; Flags: dontcopy
Source: "..\install\DLSS-Full-Control.bat"; Flags: dontcopy
Source: "..\install\Uninstall-DLSS-Full.bat"; Flags: dontcopy
Source: "..\install\Uninstall-DLAA.bat"; Flags: dontcopy
Source: "Run-Action.ps1"; Flags: dontcopy

[Code]
var
  PrepPage: TOutputMsgMemoWizardPage;
  GamePage: TInputDirWizardPage;
  ActionPage: TInputOptionWizardPage;
  GpuPage: TOutputMsgWizardPage;
  ReShadePage: TInputFileWizardPage;
  ReShadeGitHubButton: TNewButton;
  NrGitHubButton: TNewButton;
  OwnNrCheck: TNewCheckBox;
  OwnNrLabel: TNewStaticText;
  OwnNrEdit: TNewEdit;
  OwnNrBrowseButton: TNewButton;
  GameDir: string;
  SelectedAction: Integer;
  DetectedDLAA: Boolean;
  DetectedFull: Boolean;
  DetectedFusionFixFirstRun: Boolean;
  NeedFusionFixPackage: Boolean;
  FusionFixInstalledThisRun: Boolean;
  DetectedGpuSeries: Integer;

function QuoteArg(const S: string): string;
begin Result := '"' + S + '"'; end;

procedure OpenReShadeGitHub(Sender: TObject);
var ShellResult: Integer;
begin
  ShellExec('open', 'https://github.com/crosire/reshade', '', '', SW_SHOWNORMAL, ewNoWait, ShellResult);
end;

procedure OpenNrGitHub(Sender: TObject);
var ShellResult: Integer;
begin
  { Intentionally open the repository root, not a direct asset or release URL. }
  ShellExec('open', 'https://github.com/RankFTW/rhi-repo', '', '', SW_SHOWNORMAL, ewNoWait, ShellResult);
end;

function DetectNvidiaGpuSeries: Integer;
var PowerShell, Cmd: string; ResultCode: Integer;
begin
  Result := 0;
  PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
  Cmd := '$n=((Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue | Where-Object {$_.Name -match ''NVIDIA''} | Select-Object -ExpandProperty Name) -join '' ''); if($n -match ''RTX\s*50''){exit 50}; if($n -match ''RTX\s*40''){exit 40}; exit 1';
  if Exec(PowerShell, '-NoLogo -NoProfile -ExecutionPolicy Bypass -Command ' + QuoteArg(Cmd), '', SW_HIDE, ewWaitUntilTerminated, ResultCode) then begin
    if ResultCode = 50 then Result := 50
    else if ResultCode = 40 then Result := 40;
  end;
end;

function NrInstructions(Series: Integer): string;
begin
  if Series = 40 then
    Result := 'Detected: RTX 40 Series' + #13#10 + #13#10 +
      'DLSS NR: 310.8.0 RTX 40 compatibility build' + #13#10 +
      'Source: RankFTW/rhi-repo on GitHub' + #13#10 +
      'Setup will download and verify it automatically.' + #13#10 + #13#10 +
      'Neural Rendering starts OFF.'
  else if Series = 50 then
    Result := 'Detected: RTX 50 Series' + #13#10 + #13#10 +
      'DLSS NR: original NVIDIA 310.8.0 build' + #13#10 +
      'Source: RankFTW/rhi-repo on GitHub' + #13#10 +
      'Setup will download and verify it automatically.' + #13#10 + #13#10 +
      'Neural Rendering starts OFF.'
  else
    Result := 'No supported RTX 40/50 GPU was detected.' + #13#10 + #13#10 +
      'Full DLSS cannot continue.' + #13#10 +
      'Click Back and choose DLAA.';
end;

function NormalizeGameDir(const Input: string): string;
var P: string;
begin
  P := RemoveBackslashUnlessRoot(Trim(Input));
  if FileExists(AddBackslash(P) + 'GTAIV.exe') then begin Result := P; exit; end;
  if FileExists(AddBackslash(P) + 'GTAIV\GTAIV.exe') then begin Result := AddBackslash(P) + 'GTAIV'; exit; end;
  Result := '';
end;

function FusionFixFirstRunDetected(const Root: string): Boolean;
var CfgName: string;
begin
  CfgName := 'GTAIV.EFLC.FusionFix.cfg';
  Result := FileExists(AddBackslash(Root) + 'plugins\' + CfgName) or
            FileExists(AddBackslash(Root) + CfgName) or
            FileExists(AddBackslash(ExpandConstant('{localappdata}\Rockstar Games\GTA IV')) + CfgName) or
            FileExists(AddBackslash(ExpandConstant('{localappdata}\GTAIV.EFLC.FusionFix')) + CfgName) or
            FileExists(AddBackslash(ExpandConstant('{userdocs}\GTAIV.EFLC.FusionFix')) + CfgName);
end;

procedure DetectCurrentState;
begin
  DetectedFull := FileExists(AddBackslash(GameDir) + '.trex\m3k-nr.ini') or FileExists(AddBackslash(GameDir) + 'DLSS_FULL_INSTALLED.txt');
  DetectedDLAA := DetectedFull or (FileExists(AddBackslash(GameDir) + 'DLAA_INSTALL_MANIFEST.txt') and FileExists(AddBackslash(GameDir) + '.trex\NvRemixBridge.exe') and FileExists(AddBackslash(GameDir) + '.trex\dlss5-feed.addon64'));
  NeedFusionFixPackage := not FileExists(AddBackslash(GameDir) + 'dinput8.dll');
  if NeedFusionFixPackage then DetectedFusionFixFirstRun := False
  else DetectedFusionFixFirstRun := FusionFixFirstRunDetected(GameDir);
end;

function GetSelectedActionIndex: Integer;
var I: Integer;
begin
  Result := -1;
  for I := 0 to 3 do if ActionPage.Values[I] then begin Result := I; exit; end;
end;

function ActionCode(Index: Integer): string;
begin
  case Index of 0: Result := 'DLAA'; 1: Result := 'FULL'; 2: Result := 'REMOVE_FULL'; 3: Result := 'REMOVE_ALL'; else Result := ''; end;
end;

function ActionTitle(Index: Integer): string;
begin
  case Index of
    0: Result := 'Install / repair DLAA';
    1: Result := 'Install / repair Full DLSS';
    2: Result := 'Remove DLSS Full only (keep DLAA)';
    3: Result := 'Remove everything from this project (keep FusionFix and official ReShade)';
    else Result := 'Unknown action';
  end;
end;

procedure PrefillIfPresent(Page: TInputFileWizardPage; const FileName: string);
var P: string;
begin
  P := AddBackslash(ExpandConstant('{src}')) + FileName;
  if FileExists(P) then Page.Values[0] := P;
end;

procedure UpdateOwnNrControls;
var Visible: Boolean;
begin
  Visible := OwnNrCheck.Checked;
  OwnNrLabel.Visible := Visible;
  OwnNrEdit.Visible := Visible;
  OwnNrBrowseButton.Visible := Visible;
end;

procedure OwnNrCheckClick(Sender: TObject);
begin
  UpdateOwnNrControls;
end;

procedure OwnNrBrowseClick(Sender: TObject);
var P: string;
begin
  P := OwnNrEdit.Text;
  if GetOpenFileName('Select nvngx_dlssnr.dll', P, '', 'DLL files|*.dll|All files|*.*', 'dll') then
    OwnNrEdit.Text := P;
end;

procedure InitializeWizard;
var PrepText: AnsiString;
begin
  WizardForm.Caption := '{#MyAppName}';
  FusionFixInstalledThisRun := False;

  PrepText :=
    'Setup now downloads all GitHub-hosted prerequisites automatically.' + #13#10 + #13#10 +
    'You only need to provide the official ReShade 6.8.0 Full Add-On installer when a fresh DLAA foundation is required.' + #13#10 + #13#10 +
    'FusionFix, LumeniteFX, the correct RTX 40/50 Neural Rendering package, this project''s runtime, and the ReShade input patch are downloaded/verified automatically.' + #13#10 + #13#10 +
    'If FusionFix is installed for you, setup will stop once and ask you to launch GTA IV to the main menu before continuing.';
  PrepPage := CreateOutputMsgMemoPage(wpWelcome, 'Simplified setup', 'Only ReShade may need a manual download', 'GitHub-hosted dependencies are automatic.', PrepText);

  GamePage := CreateInputDirPage(PrepPage.ID, 'Select GTA IV', 'Choose the folder that contains GTAIV.exe', 'Select the game folder only.', False, '');
  GamePage.Add('');

  ActionPage := CreateInputOptionPage(GamePage.ID, 'Install, modify, or remove', 'Choose one action', 'Full DLSS automatically installs the DLAA foundation first.', True, False);
  ActionPage.Add('Install / repair DLAA');
  ActionPage.Add('Install / repair Full DLSS');
  ActionPage.Add('Remove DLSS Full only');
  ActionPage.Add('Remove everything from this project');
  ActionPage.Values[1] := True;

  GpuPage := CreateOutputMsgPage(ActionPage.ID, 'Full DLSS GPU', 'GPU detection and Neural Rendering package', 'GPU detection will run after you choose Full DLSS.');

  NrGitHubButton := TNewButton.Create(WizardForm);
  NrGitHubButton.Parent := GpuPage.Surface;
  NrGitHubButton.Caption := 'Open NR source on GitHub';
  NrGitHubButton.Left := ScaleX(0);
  NrGitHubButton.Top := GpuPage.MsgLabel.Top + GpuPage.MsgLabel.Height + ScaleY(16);
  NrGitHubButton.Width := ScaleX(180);
  NrGitHubButton.OnClick := @OpenNrGitHub;

  OwnNrCheck := TNewCheckBox.Create(WizardForm);
  OwnNrCheck.Parent := GpuPage.Surface;
  OwnNrCheck.Caption := 'I brought my own';
  OwnNrCheck.Left := ScaleX(0);
  OwnNrCheck.Top := NrGitHubButton.Top + NrGitHubButton.Height + ScaleY(14);
  OwnNrCheck.Width := ScaleX(180);
  OwnNrCheck.Checked := False;
  OwnNrCheck.OnClick := @OwnNrCheckClick;

  OwnNrLabel := TNewStaticText.Create(WizardForm);
  OwnNrLabel.Parent := GpuPage.Surface;
  OwnNrLabel.Caption := 'Path to nvngx_dlssnr.dll:';
  OwnNrLabel.Left := ScaleX(0);
  OwnNrLabel.Top := OwnNrCheck.Top + OwnNrCheck.Height + ScaleY(10);

  OwnNrEdit := TNewEdit.Create(WizardForm);
  OwnNrEdit.Parent := GpuPage.Surface;
  OwnNrEdit.Left := ScaleX(0);
  OwnNrEdit.Top := OwnNrLabel.Top + OwnNrLabel.Height + ScaleY(4);
  OwnNrEdit.Width := ScaleX(330);

  OwnNrBrowseButton := TNewButton.Create(WizardForm);
  OwnNrBrowseButton.Parent := GpuPage.Surface;
  OwnNrBrowseButton.Caption := 'Browse...';
  OwnNrBrowseButton.Left := OwnNrEdit.Left + OwnNrEdit.Width + ScaleX(8);
  OwnNrBrowseButton.Top := OwnNrEdit.Top - ScaleY(1);
  OwnNrBrowseButton.Width := ScaleX(80);
  OwnNrBrowseButton.OnClick := @OwnNrBrowseClick;

  UpdateOwnNrControls;

  ReShadePage := CreateInputFilePage(GpuPage.ID, 'Official ReShade prerequisite', 'Select ReShade 6.8.0 Full Add-On Support', 'Open the ReShade GitHub repository below. In its About box, open the official project website and download ReShade 6.8.0 with full add-on support. Select that EXE here. Setup runs it for you.');
  ReShadePage.Add('ReShade setup EXE:', 'Executable files|*.exe|All files|*.*', '.exe');
  ReShadeGitHubButton := TNewButton.Create(WizardForm);
  ReShadeGitHubButton.Parent := ReShadePage.Surface;
  ReShadeGitHubButton.Caption := 'Open ReShade repository on GitHub';
  ReShadeGitHubButton.Left := ReShadePage.Edits[0].Left;
  ReShadeGitHubButton.Top := ReShadePage.Edits[0].Top + ReShadePage.Edits[0].Height + ScaleY(12);
  ReShadeGitHubButton.Width := ScaleX(245);
  ReShadeGitHubButton.OnClick := @OpenReShadeGitHub;

  PrefillIfPresent(ReShadePage, 'ReShade_Setup_6.8.0_Addon.exe');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = GpuPage.ID then
    Result := SelectedAction <> 1
  else if PageID = ReShadePage.ID then
    Result := (SelectedAction = 2) or (SelectedAction = 3) or NeedFusionFixPackage or ((SelectedAction = 1) and DetectedDLAA);
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var P: string;
begin
  Result := True;

  if CurPageID = GamePage.ID then begin
    P := NormalizeGameDir(GamePage.Values[0]);
    if P = '' then begin
      MsgBox('GTAIV.exe was not found in that folder.', mbError, MB_OK);
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

    if DetectedFull then ActionPage.Values[1] := True
    else if DetectedDLAA then ActionPage.Values[0] := True
    else ActionPage.Values[1] := True;
  end
  else if CurPageID = ActionPage.ID then begin
    SelectedAction := GetSelectedActionIndex;
    if SelectedAction < 0 then begin
      MsgBox('Choose an action.', mbError, MB_OK);
      Result := False;
      exit;
    end;

    DetectCurrentState;

    if (SelectedAction = 2) and (not DetectedFull) then begin
      MsgBox('DLSS Full is not detected in this GTA IV folder.', mbInformation, MB_OK);
      Result := False;
      exit;
    end;

    if (SelectedAction = 3) and (not DetectedDLAA) then begin
      MsgBox('No DLAA/DLSS installation from this project is detected.', mbInformation, MB_OK);
      Result := False;
      exit;
    end;

    if ((SelectedAction = 0) or (SelectedAction = 1)) and (not NeedFusionFixPackage) and (not DetectedFusionFixFirstRun) then begin
      MsgBox('FusionFix is installed but has not completed its first run.' + #13#10 + #13#10 +
        'Launch GTA IV once to the main menu, close it, then run this setup again.', mbInformation, MB_OK);
      Result := False;
      exit;
    end;

    if SelectedAction = 1 then begin
      DetectedGpuSeries := DetectNvidiaGpuSeries;
      GpuPage.MsgLabel.Caption := NrInstructions(DetectedGpuSeries);
    end;
  end
  else if CurPageID = GpuPage.ID then begin
    if (SelectedAction = 1) and (DetectedGpuSeries = 0) then begin
      Result := False;
      exit;
    end;
    if OwnNrCheck.Checked then begin
      if not FileExists(OwnNrEdit.Text) then begin
        MsgBox('Select your nvngx_dlssnr.dll file.', mbError, MB_OK);
        Result := False;
        exit;
      end;
      if CompareText(ExtractFileExt(OwnNrEdit.Text), '.dll') <> 0 then begin
        MsgBox('The NR path must point to a DLL file.', mbError, MB_OK);
        Result := False;
        exit;
      end;
    end;
  end
  else if CurPageID = ReShadePage.ID then begin
    if ((SelectedAction = 0) or ((SelectedAction = 1) and (not DetectedDLAA))) and (not FileExists(ReShadePage.Values[0])) then begin
      MsgBox('Select the official ReShade 6.8.0 Full Add-On Support installer.', mbError, MB_OK);
      Result := False;
    end;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := 'GTA IV folder:' + NewLine + '  ' + GameDir + NewLine + NewLine +
            'Action:' + NewLine + '  ' + ActionTitle(SelectedAction) + NewLine + NewLine;

  if SelectedAction <= 1 then begin
    Result := Result + 'Automatic GitHub downloads:' + NewLine;
    if NeedFusionFixPackage then Result := Result + '  FusionFix 5.0.1' + NewLine;
    if (SelectedAction = 0) or ((SelectedAction = 1) and (not DetectedDLAA)) then
      Result := Result + '  Pinned LumeniteFX' + NewLine;
    if SelectedAction = 1 then begin
      if OwnNrCheck.Checked then
        Result := Result + '  Neural Rendering: use your DLL' + NewLine
      else
        Result := Result + '  GPU-matched DLSS Neural Rendering 310.8.0' + NewLine;
    end;
    Result := Result + '  Project runtime / input patch' + NewLine + NewLine;

    if ((SelectedAction = 0) or ((SelectedAction = 1) and (not DetectedDLAA))) and (not NeedFusionFixPackage) then
      Result := Result + 'Manual file:' + NewLine + '  ReShade: ' + ReShadePage.Values[0] + NewLine + NewLine;
    if (SelectedAction = 1) and OwnNrCheck.Checked then
      Result := Result + 'Own NR DLL:' + NewLine + '  ' + OwnNrEdit.Text + NewLine + NewLine;

    Result := Result + 'All downloaded components are hash-verified before use.';
  end;
end;

procedure ExtractSetupFiles;
begin
  ExtractTemporaryFile('Install-DLAA.bat'); ExtractTemporaryFile('Install-DLAA-Core.bat'); ExtractTemporaryFile('Install-DLSS-Full.bat'); ExtractTemporaryFile('DLSS-Full-Control.bat'); ExtractTemporaryFile('Uninstall-DLSS-Full.bat'); ExtractTemporaryFile('Uninstall-DLAA.bat'); ExtractTemporaryFile('Run-Action.ps1');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var
  PowerShell, Args, ResultPath, Detail: string;
  RawDetail: AnsiString;
  ResultCode: Integer;
begin
  if CurStep = ssInstall then begin
    ExtractSetupFiles;
    WizardForm.StatusLabel.Caption := 'Downloading verified dependencies and installing...';

    PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    ResultPath := ExpandConstant('{tmp}\GTAIV-DLSS-action-result.txt');
    DeleteFile(ResultPath);

    Args := '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' +
      QuoteArg(ExpandConstant('{tmp}\Run-Action.ps1')) +
      ' -Action ' + ActionCode(SelectedAction) +
      ' -Game ' + QuoteArg(GameDir) +
      ' -SetupSource ' + QuoteArg(ExpandConstant('{src}')) +
      ' -ResultFile ' + QuoteArg(ResultPath);

    if ((SelectedAction = 0) or ((SelectedAction = 1) and (not DetectedDLAA))) and (not NeedFusionFixPackage) then
      Args := Args + ' -ReShadeSetup ' + QuoteArg(ReShadePage.Values[0]);

    if (SelectedAction = 1) and OwnNrCheck.Checked then
      Args := Args + ' -NrPackage ' + QuoteArg(OwnNrEdit.Text);

    if not Exec(PowerShell, Args, GameDir, SW_SHOW, ewWaitUntilTerminated, ResultCode) then
      RaiseException('Could not start the setup action.');

    if ResultCode = 20 then begin
      FusionFixInstalledThisRun := True;
      exit;
    end;

    if ResultCode <> 0 then begin
      Detail := '';
      if LoadStringFromFile(ResultPath, RawDetail) then Detail := String(RawDetail);
      if Detail = '' then Detail := 'Unknown setup error. Check the console window for the last failing step.';
      RaiseException('Install failed:' + #13#10 + #13#10 + Detail);
    end;
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if FusionFixInstalledThisRun then begin
      WizardForm.FinishedLabel.Caption := 'FusionFix 5.0.1 was downloaded from GitHub and installed automatically. Launch GTA IV once to the main menu, close it, then run GTAIV-DLSS-Setup.exe again. Other GitHub prerequisites will download automatically on the next run.';
      exit;
    end;
    case SelectedAction of
      0: WizardForm.FinishedLabel.Caption := 'DLAA + ReShade input patch is installed. Setup handled the prerequisite installation. Launch GTA IV and press Home to verify the ReShade menu.';
      1: WizardForm.FinishedLabel.Caption := 'Full DLSS is installed. Initial profile: Quality. Neural Rendering is installed but intentionally OFF on the first launch. Verify DLSS 4.5 first; then enable NR later from Home → Add-ons → DLSS 5 Feed → GTA IV DLSS if wanted.';
      2: WizardForm.FinishedLabel.Caption := 'DLSS Full was removed. The preserved DLAA setup remains installed.';
      3: WizardForm.FinishedLabel.Caption := 'This project was removed. FusionFix and the official ReShade installation were left installed.';
    end;
  end;
end;
