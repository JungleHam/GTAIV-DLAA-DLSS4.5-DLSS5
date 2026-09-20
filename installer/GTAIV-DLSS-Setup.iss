#define MyAppName "GTA IV DLSS Setup & Maintenance"
#define MyAppVersion "1.0.0"
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

procedure OpenFusionFixGitHub(Sender: TObject);
var ShellResult: Integer;
begin
  ShellExec('open', 'https://github.com/ThirteenAG/GTAIV.EFLC.FusionFix', '', '', SW_SHOWNORMAL, ewNoWait, ShellResult);
end;

procedure OpenReShadeGitHub(Sender: TObject);
var ShellResult: Integer;
begin
  ShellExec('open', 'https://github.com/crosire/reshade', '', '', SW_SHOWNORMAL, ewNoWait, ShellResult);
end;

procedure OpenLumeniteGitHub(Sender: TObject);
var ShellResult: Integer;
begin
  ShellExec('open', 'https://github.com/umar-afzaal/LumeniteFX/tree/f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9', '', '', SW_SHOWNORMAL, ewNoWait, ShellResult);
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
    Result := 'Detected: RTX 40 Series.' + #13#10 + #13#10 +
      'You need the RTX 40 compatibility Neural Rendering ZIP.' + #13#10 + #13#10 +
      '1. Click the RankFTW/rhi-repo GitHub button below.' + #13#10 +
      '2. Make sure the repository name at the top is RankFTW/rhi-repo (NOT RankFTW/RHI).' + #13#10 +
      '3. On the RIGHT side of the repository page, click Releases.' + #13#10 +
      '4. The release you need is older and may not be on the first page. Scroll to the bottom of the Releases list and click Next to show older releases. You may need to click Next a couple of times; the exact number changes as new releases are added.' + #13#10 +
      '5. Stop when you find the exact release/tag: dlssnr-310.8.0-RTX40.' + #13#10 +
      '   Tip: if GitHub shows a Find a release box, you can also search that exact text.' + #13#10 +
      '6. Open that release, find Assets, and download: nvngx_dlssnr_310.8.0-RTX40.zip' + #13#10 +
      '7. Save the ZIP in the SAME folder as GTAIV-DLSS-Setup.exe.' + #13#10 +
      '8. Do NOT extract or install it. This setup handles it.'
  else if Series = 50 then
    Result := 'Detected: RTX 50 Series.' + #13#10 + #13#10 +
      'You need the ORIGINAL 310.8.0 Neural Rendering ZIP, not the RTX40 compatibility package.' + #13#10 + #13#10 +
      '1. Click Open RankFTW/rhi-repo GitHub below.' + #13#10 +
      '2. Make sure the repository name at the top is RankFTW/rhi-repo (NOT RankFTW/RHI).' + #13#10 +
      '3. On the RIGHT side of the repository page, click Releases.' + #13#10 +
      '4. The release you need is older and may not be on the first page. Scroll to the bottom of the Releases list and click Next to show older releases. You may need to click Next a couple of times; the exact number changes as new releases are added.' + #13#10 +
      '5. Stop when you find the exact release/tag: dlssnr-310.8.0.' + #13#10 +
      '   Tip: if GitHub shows a Find a release box, you can also search that exact text.' + #13#10 +
      '6. Be careful: choose the PLAIN 310.8.0 release, NOT dlssnr-310.8.0-RTX40.' + #13#10 +
      '7. Open Assets and download: nvngx_dlssnr_310.8.0.zip' + #13#10 +
      '8. Save the ZIP in the SAME folder as GTAIV-DLSS-Setup.exe.' + #13#10 +
      '9. Do NOT extract or install it. This setup handles it.'
  else
    Result := 'Full DLSS / Neural Rendering currently supports the project-tested RTX 40 and RTX 50 runtime paths.' + #13#10 + #13#10 +
      'Setup could not identify a supported RTX 40/50 GPU, so Full DLSS will not continue. You can still choose the DLAA install mode.';
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

procedure PrefillNrForSeries(Series: Integer);
begin
  if Series = 40 then PrefillIfPresent(NrPage, 'nvngx_dlssnr_310.8.0-RTX40.zip')
  else if Series = 50 then PrefillIfPresent(NrPage, 'nvngx_dlssnr_310.8.0.zip');
end;

procedure InitializeWizard;
var PrepText: AnsiString;
begin
  WizardForm.Caption := '{#MyAppName}';
  FusionFixInstalledThisRun := False;

  PrepText :=
    'Before you start, make ONE temporary folder somewhere easy to find, for example:' + #13#10 +
    'Desktop\GTA IV DLSS Setup Files' + #13#10 + #13#10 +
    'Put GTAIV-DLSS-Setup.exe and every prerequisite file you download into that SAME folder.' + #13#10 + #13#10 +
    'IMPORTANT: Do NOT extract ZIP files. Do NOT run ReShade yourself. Do NOT copy prerequisite files into GTA IV yourself. This installer validates and installs/extracts them for you.' + #13#10 + #13#10 +
    'If FusionFix is not already installed, setup can install it from GTAIV.EFLC.FusionFix.zip. FusionFix requires one normal GTA IV launch before the DLAA/DLSS part can continue; setup will tell you exactly when to do that.' + #13#10 + #13#10 +
    'Keeping all downloads beside this setup EXE lets setup find the normal filenames automatically.';
  PrepPage := CreateOutputMsgMemoPage(wpWelcome, 'Put all setup files in one folder', 'No manual installation is required', 'Download the requested files, keep them together, and let this installer do the installation.', PrepText);

  GamePage := CreateInputDirPage(PrepPage.ID, 'Select GTA IV', 'Choose the folder that contains GTAIV.exe', 'You only select the game folder. Do not copy prerequisites into it yourself.', False, '');
  GamePage.Add('');

  ActionPage := CreateInputOptionPage(GamePage.ID, 'Install, modify, or remove', 'Choose one action', 'Full DLSS automatically installs the DLAA foundation first.', True, False);
  ActionPage.Add('Install / repair DLAA  —  DLAA + ReShade + input patch');
  ActionPage.Add('Install / repair Full DLSS  —  everything above + DLSS 4.5 + DLSS 5 Neural Rendering');
  ActionPage.Add('Remove DLSS Full only  —  return to the preserved DLAA setup');
  ActionPage.Add('Remove everything from this project  —  keep FusionFix and official ReShade installed');
  ActionPage.Values[1] := True;

  FusionFixPage := CreateInputFilePage(ActionPage.ID, 'FusionFix prerequisite', 'Select GTAIV.EFLC.FusionFix.zip', 'Only shown when FusionFix is missing. Click the GitHub button below. Confirm the page says ThirteenAG/GTAIV.EFLC.FusionFix. On the RIGHT side click Releases, open GTAIV.EFLC.FusionFix v5.0.1, expand Assets, and download GTAIV.EFLC.FusionFix.zip. Save it beside this setup EXE. Do NOT extract it; setup installs it.');
  FusionFixPage.Add('FusionFix ZIP:', 'ZIP archives|*.zip|All files|*.*', '.zip');
  FusionFixGitHubButton := TNewButton.Create(WizardForm);
  FusionFixGitHubButton.Parent := FusionFixPage.Surface;
  FusionFixGitHubButton.Caption := 'Open FusionFix repository on GitHub';
  FusionFixGitHubButton.Left := FusionFixPage.Edits[0].Left;
  FusionFixGitHubButton.Top := FusionFixPage.Edits[0].Top + FusionFixPage.Edits[0].Height + ScaleY(12);
  FusionFixGitHubButton.Width := ScaleX(245);
  FusionFixGitHubButton.OnClick := @OpenFusionFixGitHub;

  ReShadePage := CreateInputFilePage(FusionFixPage.ID, 'Official ReShade prerequisite', 'Select ReShade 6.8.0 Full Add-On Support', 'Click the GitHub button below. Confirm the page says crosire/reshade. ReShade does NOT provide the installer EXE as a GitHub Release. In the GitHub About box on the RIGHT, click the official project website shown there. On that site look for ReShade 6.8.0 with full add-on support (NOT the normal build). Save the EXE beside this setup EXE. Do NOT run it yourself; setup runs it correctly for GTA IV.');
  ReShadePage.Add('ReShade setup EXE:', 'Executable files|*.exe|All files|*.*', '.exe');
  ReShadeGitHubButton := TNewButton.Create(WizardForm);
  ReShadeGitHubButton.Parent := ReShadePage.Surface;
  ReShadeGitHubButton.Caption := 'Open ReShade repository on GitHub';
  ReShadeGitHubButton.Left := ReShadePage.Edits[0].Left;
  ReShadeGitHubButton.Top := ReShadePage.Edits[0].Top + ReShadePage.Edits[0].Height + ScaleY(12);
  ReShadeGitHubButton.Width := ScaleX(245);
  ReShadeGitHubButton.OnClick := @OpenReShadeGitHub;

  LumenitePage := CreateInputFilePage(ReShadePage.ID, 'LumeniteFX prerequisite', 'Select the pinned LumeniteFX ZIP', 'Click the GitHub button below. It opens the exact pinned LumeniteFX commit. On GitHub click the green Code button, then Download ZIP. Save that ZIP beside this setup EXE. Do NOT extract it; setup extracts exactly what GTA IV needs.');
  LumenitePage.Add('LumeniteFX ZIP:', 'ZIP archives|*.zip|All files|*.*', '.zip');
  LumeniteGitHubButton := TNewButton.Create(WizardForm);
  LumeniteGitHubButton.Parent := LumenitePage.Surface;
  LumeniteGitHubButton.Caption := 'Open pinned LumeniteFX on GitHub';
  LumeniteGitHubButton.Left := LumenitePage.Edits[0].Left;
  LumeniteGitHubButton.Top := LumenitePage.Edits[0].Top + LumenitePage.Edits[0].Height + ScaleY(12);
  LumeniteGitHubButton.Width := ScaleX(245);
  LumeniteGitHubButton.OnClick := @OpenLumeniteGitHub;

  NrPage := CreateInputFilePage(LumenitePage.ID, 'Neural Rendering prerequisite', 'Select the GPU-matched NR ZIP', 'Setup detects RTX 40/50 and shows the exact old release/tag and ZIP filename. Click the GitHub button below and confirm the page says RankFTW/rhi-repo (NOT RankFTW/RHI). On the RIGHT side click Releases. Do NOT use the newest release. Scroll to the bottom and click Next through older pages until the exact 310.8.0 tag setup tells you to find appears. Open Assets, download the exact ZIP setup names, save it beside this EXE, and do NOT extract it.');
  NrPage.Add('NR ZIP:', 'ZIP archives|*.zip|All files|*.*', '.zip');
  NrGitHubButton := TNewButton.Create(WizardForm);
  NrGitHubButton.Parent := NrPage.Surface;
  NrGitHubButton.Caption := 'Open RankFTW/rhi-repo on GitHub';
  NrGitHubButton.Left := NrPage.Edits[0].Left;
  NrGitHubButton.Top := NrPage.Edits[0].Top + NrPage.Edits[0].Height + ScaleY(12);
  NrGitHubButton.Width := ScaleX(245);
  NrGitHubButton.OnClick := @OpenNrGitHub;

  PrefillIfPresent(FusionFixPage, 'GTAIV.EFLC.FusionFix.zip');
  PrefillIfPresent(ReShadePage, 'ReShade_Setup_6.8.0_Addon.exe');
  PrefillIfPresent(LumenitePage, 'LumeniteFX-f8cbbb4eccfcb7adf0d74bb358ba349272e3c1e9.zip');
end;

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if PageID = FusionFixPage.ID then
    Result := (SelectedAction = 2) or (SelectedAction = 3) or (not NeedFusionFixPackage)
  else if (PageID = ReShadePage.ID) or (PageID = LumenitePage.ID) then
    Result := (SelectedAction = 2) or (SelectedAction = 3) or ((SelectedAction = 1) and DetectedDLAA)
  else if PageID = NrPage.ID then Result := SelectedAction <> 1;
end;

function NextButtonClick(CurPageID: Integer): Boolean;
var P: string;
begin
  Result := True;
  if CurPageID = GamePage.ID then begin
    P := NormalizeGameDir(GamePage.Values[0]);
    if P = '' then begin MsgBox('GTAIV.exe was not found in that folder.', mbError, MB_OK); Result := False; exit; end;
    GameDir := P; GamePage.Values[0] := P; DetectCurrentState;
    ActionPage.Values[0] := False; ActionPage.Values[1] := False; ActionPage.Values[2] := False; ActionPage.Values[3] := False;
    if DetectedFull then ActionPage.Values[1] := True else if DetectedDLAA then ActionPage.Values[0] := True else ActionPage.Values[1] := True;
  end else if CurPageID = ActionPage.ID then begin
    SelectedAction := GetSelectedActionIndex;
    if SelectedAction < 0 then begin MsgBox('Choose an action.', mbError, MB_OK); Result := False; exit; end;
    DetectCurrentState;
    if (SelectedAction = 2) and (not DetectedFull) then begin MsgBox('DLSS Full is not detected in this GTA IV folder.', mbInformation, MB_OK); Result := False; exit; end;
    if (SelectedAction = 3) and (not DetectedDLAA) then begin MsgBox('No DLAA/DLSS installation from this project is detected.', mbInformation, MB_OK); Result := False; exit; end;
    if ((SelectedAction = 0) or (SelectedAction = 1)) and (not NeedFusionFixPackage) and (not DetectedFusionFixFirstRun) then begin
      MsgBox('FusionFix is already installed, but its first-run file was not found.' + #13#10 + #13#10 + 'Do not install anything else manually. Close setup, launch GTA IV normally once, wait until the main menu appears, close the game, then run this same setup EXE again from your setup-files folder.', mbInformation, MB_OK);
      Result := False; exit;
    end;
    if SelectedAction = 1 then begin
      DetectedGpuSeries := DetectNvidiaGpuSeries;
      PrefillNrForSeries(DetectedGpuSeries);
      MsgBox(NrInstructions(DetectedGpuSeries), mbInformation, MB_OK);
      if DetectedGpuSeries = 0 then begin Result := False; exit; end;
    end;
  end else if CurPageID = FusionFixPage.ID then begin
    if ((SelectedAction = 0) or (SelectedAction = 1)) and NeedFusionFixPackage and (not FileExists(FusionFixPage.Values[0])) then begin
      MsgBox('Select GTAIV.EFLC.FusionFix.zip. Keep it as a ZIP; setup installs it for you.', mbError, MB_OK); Result := False;
    end;
  end else if CurPageID = ReShadePage.ID then begin
    if ((SelectedAction = 0) or ((SelectedAction = 1) and (not DetectedDLAA))) and (not FileExists(ReShadePage.Values[0])) then begin MsgBox('Select the official ReShade 6.8.0 Full Add-On Support installer. Do not run it yourself.', mbError, MB_OK); Result := False; end;
  end else if CurPageID = LumenitePage.ID then begin
    if ((SelectedAction = 0) or ((SelectedAction = 1) and (not DetectedDLAA))) and (not FileExists(LumenitePage.Values[0])) then begin MsgBox('Select the pinned official LumeniteFX ZIP. Do not extract it.', mbError, MB_OK); Result := False; end;
  end else if CurPageID = NrPage.ID then begin
    if (SelectedAction = 1) and (not FileExists(NrPage.Values[0])) then begin MsgBox('Select the downloaded Neural Rendering ZIP. Do not extract it.', mbError, MB_OK); Result := False; end;
  end;
end;

function UpdateReadyMemo(Space, NewLine, MemoUserInfoInfo, MemoDirInfo, MemoTypeInfo, MemoComponentsInfo, MemoGroupInfo, MemoTasksInfo: String): String;
begin
  Result := 'GTA IV folder:' + NewLine + '  ' + GameDir + NewLine + NewLine + 'Action:' + NewLine + '  ' + ActionTitle(SelectedAction) + NewLine + NewLine;
  if SelectedAction <= 1 then begin
    Result := Result + 'Prerequisite files (setup will install/extract them; you do not do that manually):' + NewLine;
    if NeedFusionFixPackage then Result := Result + '  FusionFix: ' + FusionFixPage.Values[0] + NewLine;
    if (SelectedAction = 0) or ((SelectedAction = 1) and (not DetectedDLAA)) then begin
      Result := Result + '  ReShade: ' + ReShadePage.Values[0] + NewLine + '  LumeniteFX: ' + LumenitePage.Values[0] + NewLine;
    end;
    if SelectedAction = 1 then Result := Result + '  Neural Rendering ZIP: ' + NrPage.Values[0] + NewLine;
    Result := Result + NewLine + 'Keep the prerequisite files beside GTAIV-DLSS-Setup.exe. Setup validates them before use. Repository navigation starts on GitHub; no direct third-party binary/archive download URL is embedded.';
  end;
end;

procedure ExtractSetupFiles;
begin
  ExtractTemporaryFile('Install-DLAA.bat'); ExtractTemporaryFile('Install-DLAA-Core.bat'); ExtractTemporaryFile('Install-DLSS-Full.bat'); ExtractTemporaryFile('DLSS-Full-Control.bat'); ExtractTemporaryFile('Uninstall-DLSS-Full.bat'); ExtractTemporaryFile('Uninstall-DLAA.bat'); ExtractTemporaryFile('Run-Action.ps1');
end;

procedure CurStepChanged(CurStep: TSetupStep);
var PowerShell, Args: string; ResultCode: Integer;
begin
  if CurStep = ssInstall then begin
    ExtractSetupFiles; WizardForm.StatusLabel.Caption := ActionTitle(SelectedAction) + '...';
    PowerShell := ExpandConstant('{sys}\WindowsPowerShell\v1.0\powershell.exe');
    Args := '-NoLogo -NoProfile -ExecutionPolicy Bypass -File ' + QuoteArg(ExpandConstant('{tmp}\Run-Action.ps1')) + ' -Action ' + ActionCode(SelectedAction) + ' -Game ' + QuoteArg(GameDir) + ' -SetupSource ' + QuoteArg(ExpandConstant('{src}'));
    if NeedFusionFixPackage and ((SelectedAction = 0) or (SelectedAction = 1)) then
      Args := Args + ' -FusionFixPackage ' + QuoteArg(FusionFixPage.Values[0]);
    if (SelectedAction = 0) or ((SelectedAction = 1) and (not DetectedDLAA)) then
      Args := Args + ' -ReShadeSetup ' + QuoteArg(ReShadePage.Values[0]) + ' -LumenitePackage ' + QuoteArg(LumenitePage.Values[0]);
    if SelectedAction = 1 then Args := Args + ' -NrPackage ' + QuoteArg(NrPage.Values[0]);
    if not Exec(PowerShell, Args, GameDir, SW_SHOW, ewWaitUntilTerminated, ResultCode) then RaiseException('Could not start the setup action.');
    if ResultCode = 20 then begin FusionFixInstalledThisRun := True; exit; end;
    if ResultCode <> 0 then RaiseException('The selected action failed. Review the console output and installer log for details.');
  end;
end;

procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then begin
    if FusionFixInstalledThisRun then begin
      WizardForm.FinishedLabel.Caption := 'FusionFix 5.0.1 was installed for you. One first-run step is required: launch GTA IV normally, wait until the main menu appears, then close the game. After that, run GTAIV-DLSS-Setup.exe again from the SAME setup-files folder. Leave ReShade, LumeniteFX and the NR ZIP untouched; setup will install/extract them on the next run.';
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
