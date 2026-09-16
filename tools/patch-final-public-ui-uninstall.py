#!/usr/bin/env python3
from pathlib import Path
import argparse, json

ROOT = Path('.')
STAGE = ROOT / 'install' / 'Public-ReShade-Controls-Stage.ps1'
UNINSTALL = ROOT / 'install' / 'Uninstall-DLSS-Full.bat'
INSTALLER = ROOT / 'install' / 'Install-DLSS-Full.bat'
MANIFEST = ROOT / 'manifests' / 'versions.json'
WORKFLOW = ROOT / '.github' / 'workflows' / 'dlss-full-module.yml'
README = ROOT / 'install' / 'README.md'


def replace_once(text: str, old: str, new: str, label: str) -> str:
    c = text.count(old)
    if c != 1:
        raise RuntimeError(f'{label}: expected exactly one source match, found {c}')
    return text.replace(old, new, 1)


def phase1():
    text = STAGE.read_text(encoding='utf-8')

    panel_anchor = '''$feed = Replace-ExactOnce $feed `
    '    if (ImGui::CollapsingHeader("M3K Neural Rendering"))' `
    '    if (ImGui::CollapsingHeader("GTA IV DLSS"))' `
    'panel title'
'''
    panel_new = panel_anchor + '''
# The frozen engineering checkpoint still contains the old A3-S1.2 screenshot lab.
# Keep its dead implementation out of the public settings surface by removing its
# ReShade overlay registration/unregistration. The renderer path itself is untouched.
$feed = Replace-ExactOnce $feed `
    '        reshade::register_overlay("M3K Capture Lab", M3kCaptureOverlay);' `
    '' `
    'Capture Lab registration removal'
$feed = Replace-ExactOnce $feed `
    '        reshade::unregister_overlay("M3K Capture Lab", M3kCaptureOverlay);' `
    '' `
    'Capture Lab unregister removal'
'''
    text = replace_once(text, panel_anchor, panel_new, 'capture lab public removal')

    q_start = text.index("$qualityNew = @'\n")
    q_end_marker = "\n'@\n\n$feed = ("
    q_end = text.index(q_end_marker, q_start)
    old_q = text[q_start:q_end+3]
    new_q = '''$qualityNew = @'
        ImGui::TextUnformatted("DLSS / DLAA mode");
        int reconstruction = static_cast<int>(M3kRequestedSrProfile());
        if (reconstruction < 0 || reconstruction > 5) reconstruction = 2;
        const char *reconstructionItems = "DLAA Native\\0Custom Ultra Quality (77%)\\0Quality\\0Balanced\\0Performance\\0Ultra Performance\\0\\0";
        if (ImGui::Combo("Mode##M3KSRProfile", &reconstruction, reconstructionItems))
            M3kRequestSrProfileLive(static_cast<UINT>(reconstruction));
        ImGui::Text("Applied: %s", M3kSrProfileName(M3kAppliedSrProfile()));
        ImGui::Text("True render target: %u x %u", M3kDesiredRenderWidth(), M3kDesiredRenderHeight());
        ImGui::Text("DXVK source now:    %u x %u", M3kCurrentSourceWidth(), M3kCurrentSourceHeight());
        if (M3kDesiredRenderWidth() != M3kCurrentSourceWidth() || M3kDesiredRenderHeight() != M3kCurrentSourceHeight())
            ImGui::TextColored(ImVec4(1.0f, 0.78f, 0.25f, 1.0f), "Applying GTA/DXVK render resize...");
        if (M3kRequestedSrProfile() == 0)
            ImGui::TextWrapped("DLAA Native renders GTA at the full output resolution and applies DLAA without Super Resolution upscaling.");
        else
            ImGui::TextWrapped("DLSS modes resize GTA to NVIDIA's matching input resolution, then reconstruct to the native presenter. Changes are saved automatically and apply live.");
        ImGui::Separator();
'@'''
    text = text[:q_start] + new_q + text[q_end+3:]

    text = text.replace("'DLSS Super Resolution quality',\n", "'DLSS / DLAA mode',\n        'DLAA Native',\n        'True render target:',\n        'DXVK source now:',\n")
    verify_anchor = "Write-Host 'Public ReShade controls ready: Neural Rendering Off/On + 1-pass default guidance + five DLSS quality modes.'"
    verify_new = '''if ($verify.IndexOf('reshade::register_overlay("M3K Capture Lab"', [StringComparison]::Ordinal) -ge 0 -or
    $verify.IndexOf('reshade::unregister_overlay("M3K Capture Lab"', [StringComparison]::Ordinal) -ge 0) {
    throw 'Public ReShade controls verification failed: M3K Capture Lab is still registered'
}

Write-Host 'Public ReShade controls ready: DLAA Native + five DLSS modes + live resolution diagnostics + Neural Rendering controls.' '''.rstrip()
    text = replace_once(text, verify_anchor, verify_new, 'public verification summary')
    STAGE.write_text(text, encoding='utf-8', newline='\n')

    uninstall = r'''@rem GTAIV-DLAA-DLSS4.5-DLSS5 - roll DLSS Full back to the preserved DLAA + ReShade input-patch baseline.
@echo off
setlocal
set "DLSSU_SELF=%~f0"
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:DLSSU_SELF);$m=('#==POWER'+'SHELL==#');$i=$s.IndexOf($m);if($i -lt 0){exit 90};iex $s.Substring($i+$m.Length)"
exit /b %errorlevel%

#==POWERSHELL==#
$ErrorActionPreference = 'Stop'
$Self = $env:DLSSU_SELF
$Game = Split-Path -Parent $Self
$Trex = Join-Path $Game '.trex'
$Log = Join-Path $Game 'DLSS_FULL_uninstall.log'
$TranscriptStarted = $false
$Safety = $null

function Fail([string]$Message) { throw $Message }

$RuntimeFiles = @(
    'd3d9.dll',
    '.trex\NvRemixBridge.exe',
    '.trex\d3d9vk_x64.dll',
    '.trex\dlss5-feed.addon64',
    '.trex\dlss5-feed.cfg',
    '.trex\m3k-nr.ini',
    '.trex\m3k\m3k-nvngx.dll',
    '.trex\m3k\nvngx_dlssnr.dll'
)
$DlaaRequired = @(
    'd3d9.dll',
    '.trex\NvRemixBridge.exe',
    '.trex\d3d9vk_x64.dll',
    '.trex\dlss5-feed.addon64',
    '.trex\dlss5-feed.cfg'
)
$FullOnly = @(
    '.trex\m3k-nr.ini',
    '.trex\m3k\m3k-nvngx.dll',
    '.trex\m3k\nvngx_dlssnr.dll'
)

function Copy-IfExists([string]$Source,[string]$Destination) {
    if (Test-Path -LiteralPath $Source) {
        $parent = Split-Path -Parent $Destination
        if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $Source -Destination $Destination -Force
    }
}

function Snapshot-Files([string]$Destination) {
    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
    foreach ($rel in $RuntimeFiles) { Copy-IfExists (Join-Path $Game $rel) (Join-Path $Destination $rel) }
    foreach ($rel in @('DLSS-Full-Control.bat','DLSS_FULL_INSTALLED.txt')) { Copy-IfExists (Join-Path $Game $rel) (Join-Path $Destination $rel) }
}

function Test-DlaaBaseline([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    foreach ($rel in $DlaaRequired) { if (-not (Test-Path -LiteralPath (Join-Path $Path $rel))) { return $false } }
    foreach ($rel in $FullOnly) { if (Test-Path -LiteralPath (Join-Path $Path $rel)) { return $false } }
    return $true
}

function Restore-RuntimeSnapshot([string]$Path) {
    foreach ($rel in $RuntimeFiles) {
        $dst = Join-Path $Game $rel
        if (Test-Path -LiteralPath $dst) { Remove-Item -LiteralPath $dst -Force -ErrorAction SilentlyContinue }
        $src = Join-Path $Path $rel
        if (Test-Path -LiteralPath $src) {
            $parent = Split-Path -Parent $dst
            if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            Copy-Item -LiteralPath $src -Destination $dst -Force
        }
    }
}

try {
    Start-Transcript -LiteralPath $Log -Force | Out-Null
    $TranscriptStarted = $true
    Write-Host ''
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host ' GTA IV - UNINSTALL DLSS FULL -> RESTORE DLAA BASELINE' -ForegroundColor Green
    Write-Host ' ReShade input patch / FusionFix / DLSS 4.5 DLAA stay installed' -ForegroundColor Green
    Write-Host '============================================================' -ForegroundColor Green
    Write-Host "Game folder: $Game"

    if (-not (Test-Path -LiteralPath (Join-Path $Game 'GTAIV.exe'))) { Fail 'Put this BAT beside GTAIV.exe.' }
    if (Get-Process GTAIV -ErrorAction SilentlyContinue) { Fail 'Close GTA IV before uninstalling DLSS Full.' }
    if (Get-Process NvRemixBridge -ErrorAction SilentlyContinue) { Fail 'Close NvRemixBridge.exe before uninstalling DLSS Full.' }

    $Baseline = Join-Path $Game '_DLSS_FULL_DLAA_BASELINE'
    if (-not (Test-DlaaBaseline $Baseline)) {
        $Baseline = $null
        $candidates = @(Get-ChildItem -LiteralPath $Game -Directory -Filter '_DLSS_FULL_PREINSTALL_BACKUP_*' -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($candidate in $candidates) {
            if (Test-DlaaBaseline $candidate.FullName) { $Baseline = $candidate.FullName; break }
        }
    }
    if (-not $Baseline) {
        Fail 'No trustworthy DLAA-only baseline snapshot was found. Nothing was changed. Reinstall the clean DLAA step before attempting removal.'
    }

    Write-Host "DLAA baseline selected: $Baseline" -ForegroundColor Cyan
    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $Safety = Join-Path $Game ("_DLSS_FULL_UNINSTALL_SAFETY_" + $stamp)
    Snapshot-Files $Safety
    Write-Host "Current DLSS Full runtime backed up to: $Safety" -ForegroundColor DarkGray

    Restore-RuntimeSnapshot $Baseline

    foreach ($rel in $FullOnly) {
        $p = Join-Path $Game $rel
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }
    $m3kDir = Join-Path $Trex 'm3k'
    if (Test-Path -LiteralPath $m3kDir) {
        $remaining = @(Get-ChildItem -LiteralPath $m3kDir -Force -ErrorAction SilentlyContinue)
        if ($remaining.Count -eq 0) { Remove-Item -LiteralPath $m3kDir -Force }
    }
    foreach ($rel in @('DLSS-Full-Control.bat','DLSS_FULL_INSTALLED.txt')) {
        $p = Join-Path $Game $rel
        if (Test-Path -LiteralPath $p) { Remove-Item -LiteralPath $p -Force }
    }

    foreach ($rel in $DlaaRequired) {
        if (-not (Test-Path -LiteralPath (Join-Path $Game $rel))) { Fail "DLAA restore validation failed: missing $rel" }
    }
    foreach ($rel in $FullOnly) {
        if (Test-Path -LiteralPath (Join-Path $Game $rel)) { Fail "DLSS Full removal validation failed: still present $rel" }
    }

    Write-Host ''
    Write-Host 'SUCCESS: DLSS Full removed; DLAA-only runtime restored.' -ForegroundColor Green
    Write-Host 'FusionFix, ReShade, the ReShade input patch, LumeniteFX and nvngx_dlss.dll were left in place.' -ForegroundColor Green
    Write-Host 'Launch GTA IV normally and verify DLAA before reinstalling DLSS Full.' -ForegroundColor Yellow
    Write-Host "Safety backup of the removed Full runtime: $Safety" -ForegroundColor DarkGray
    Write-Host "Log: $Log" -ForegroundColor DarkGray
}
catch {
    $msg = $_.Exception.Message
    Write-Host ''
    Write-Host 'UNINSTALL FAILED' -ForegroundColor Red
    Write-Host $msg -ForegroundColor Red
    if ($Safety -and (Test-Path -LiteralPath $Safety)) {
        Write-Host 'Attempting to restore the pre-uninstall DLSS Full runtime...' -ForegroundColor Yellow
        try {
            Restore-RuntimeSnapshot $Safety
            Copy-IfExists (Join-Path $Safety 'DLSS-Full-Control.bat') (Join-Path $Game 'DLSS-Full-Control.bat')
            Copy-IfExists (Join-Path $Safety 'DLSS_FULL_INSTALLED.txt') (Join-Path $Game 'DLSS_FULL_INSTALLED.txt')
            Write-Host 'Pre-uninstall runtime restored where possible.' -ForegroundColor Green
        } catch { Write-Host ('Rollback error: ' + $_.Exception.Message) -ForegroundColor Red }
    }
    Write-Host "Log: $Log" -ForegroundColor Yellow
    exit 1
}
finally {
    if ($TranscriptStarted) { try { Stop-Transcript | Out-Null } catch {} }
}
exit 0
'''
    UNINSTALL.write_text(uninstall, encoding='utf-8', newline='\n')


def phase2(commit: str, stage_hash: str, uninstall_hash: str):
    installer = INSTALLER.read_text(encoding='utf-8')
    old_pc = "cb3d3635ab746b603d1155b92424d24a9469eb2c"
    old_ph = "2AAAD1F94477BB16874F2047B65950B5C678759B8772FC566C4708E19B812EAE"
    installer = replace_once(installer, f"$PublicControlsCommit = '{old_pc}'", f"$PublicControlsCommit = '{commit}'", 'public controls commit pin')
    installer = replace_once(installer, f"$PublicControlsHash = '{old_ph}'", f"$PublicControlsHash = '{stage_hash}'", 'public controls hash pin')

    control_anchor = "$ControlHash = 'F209610F26970939D5B12EFCC13BEE84BB08348B045B2C4442D3177ED142661D'\n"
    control_new = control_anchor + f"$UninstallerCommit = '{commit}'\n$UninstallerUrl = \"https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/$UninstallerCommit/install/Uninstall-DLSS-Full.bat\"\n$UninstallerHash = '{uninstall_hash}'\n"
    installer = replace_once(installer, control_anchor, control_new, 'uninstaller pin variables')

    helper_anchor = "function Set-KeyEquals([string]$Path,[string]$Key,[string]$Value) {\n"
    baseline_helpers = r'''function Test-DlaaBaselineSnapshot([string]$Path) {
    if (-not $Path -or -not (Test-Path -LiteralPath $Path -PathType Container)) { return $false }
    foreach ($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Path $rel))) { return $false }
    }
    foreach ($rel in @('.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll')) {
        if (Test-Path -LiteralPath (Join-Path $Path $rel)) { return $false }
    }
    return $true
}

function Save-DlaaBaselineIfPossible {
    $canonical = Join-Path $Game '_DLSS_FULL_DLAA_BASELINE'
    if (Test-DlaaBaselineSnapshot $canonical) { return $canonical }
    if (Test-Path -LiteralPath $canonical) { Remove-Item -LiteralPath $canonical -Recurse -Force }

    $source = $null
    $currentLooksDlaa = $true
    foreach ($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg')) {
        if (-not (Test-Path -LiteralPath (Join-Path $Game $rel))) { $currentLooksDlaa = $false; break }
    }
    foreach ($rel in @('.trex\m3k-nr.ini','.trex\m3k\m3k-nvngx.dll','.trex\m3k\nvngx_dlssnr.dll')) {
        if (Test-Path -LiteralPath (Join-Path $Game $rel)) { $currentLooksDlaa = $false }
    }
    if ($currentLooksDlaa) { $source = $Game }
    if (-not $source) {
        $candidates = @(Get-ChildItem -LiteralPath $Game -Directory -Filter '_DLSS_FULL_PREINSTALL_BACKUP_*' -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($candidate in $candidates) {
            if (Test-DlaaBaselineSnapshot $candidate.FullName) { $source = $candidate.FullName; break }
        }
    }
    if (-not $source) {
        Write-Host 'WARNING: Could not establish a trustworthy canonical DLAA rollback snapshot. Existing timestamped backups are left untouched.' -ForegroundColor Yellow
        return $null
    }

    New-Item -ItemType Directory -Path $canonical -Force | Out-Null
    foreach ($rel in @('d3d9.dll','.trex\NvRemixBridge.exe','.trex\d3d9vk_x64.dll','.trex\dlss5-feed.addon64','.trex\dlss5-feed.cfg')) {
        Copy-IfExists (Join-Path $source $rel) (Join-Path $canonical $rel)
    }
    [IO.File]::WriteAllText((Join-Path $canonical 'BASELINE.txt'),
        "DLAA-only rollback baseline`r`nCreated=$(Get-Date -Format o)`r`nSource=$source`r`n",
        (New-Object Text.UTF8Encoding($false)))
    if (-not (Test-DlaaBaselineSnapshot $canonical)) { Fail 'Canonical DLAA rollback baseline validation failed.' }
    Write-Host "Canonical DLAA rollback baseline: $canonical" -ForegroundColor DarkGray
    return $canonical
}

'''
    installer = replace_once(installer, helper_anchor, baseline_helpers + helper_anchor, 'DLAA baseline helper insertion')

    backup_anchor = "    $stamp = Get-Date -Format 'yyyyMMdd_HHmmss'\n    $Backup = Join-Path $Game (\"_DLSS_FULL_PREINSTALL_BACKUP_\" + $stamp)\n"
    backup_new = "    $DlaaBaseline = Save-DlaaBaselineIfPossible\n\n" + backup_anchor
    installer = replace_once(installer, backup_anchor, backup_new, 'canonical baseline creation')

    install_control_anchor = '''    Copy-Item -LiteralPath $controlTemp -Destination $controlPath -Force

    $receipt = @(
'''
    install_control_new = f'''    Copy-Item -LiteralPath $controlTemp -Destination $controlPath -Force

    $uninstallerPath = Join-Path $Game 'Uninstall-DLSS-Full.bat'
    $uninstallerTemp = Join-Path $Temp 'Uninstall-DLSS-Full.bat'
    Write-Host 'Installing Uninstall-DLSS-Full.bat (restore DLAA-only baseline)...' -ForegroundColor Cyan
    Download-File $UninstallerUrl $uninstallerTemp
    Assert-SHA256 $uninstallerTemp $UninstallerHash
    Copy-Item -LiteralPath $uninstallerTemp -Destination $uninstallerPath -Force

    $receipt = @(
'''
    installer = replace_once(installer, install_control_anchor, install_control_new, 'install uninstaller')

    receipt_anchor = '        "PublicControlsSHA256=$PublicControlsHash",\n'
    receipt_new = receipt_anchor + '        "UninstallerCommit=$UninstallerCommit",\n        "UninstallerSHA256=$UninstallerHash",\n        "DlaaBaseline=$DlaaBaseline",\n'
    installer = replace_once(installer, receipt_anchor, receipt_new, 'receipt uninstaller pins')

    success_anchor = "    Write-Host 'Use DLSS-Full-Control.bat only for launch, repair, status, and logs.' -ForegroundColor Yellow\n"
    success_new = success_anchor + "    Write-Host 'Use Uninstall-DLSS-Full.bat to roll back to the preserved DLAA + ReShade input-patch baseline.' -ForegroundColor Yellow\n"
    installer = replace_once(installer, success_anchor, success_new, 'success uninstaller guidance')
    INSTALLER.write_text(installer, encoding='utf-8', newline='\n')

    manifest = json.loads(MANIFEST.read_text(encoding='utf-8'))
    full = manifest['components']['dlss-full']
    full['public_reshade_controls_commit'] = commit
    full['public_reshade_controls_sha256'] = stage_hash.lower()
    full['public_modes'] = ['DLAA Native','Custom Ultra Quality (77%)','Quality','Balanced','Performance','Ultra Performance']
    full['uninstaller_commit'] = commit
    full['uninstaller_sha256'] = uninstall_hash.lower()
    full['uninstaller_path'] = 'Uninstall-DLSS-Full.bat'
    full['rollback_target'] = 'DLAA-only baseline + ReShade input patch'
    MANIFEST.write_text(json.dumps(manifest, indent=2) + '\n', encoding='utf-8', newline='\n')

    wf = WORKFLOW.read_text(encoding='utf-8')
    wf = replace_once(wf, "      - 'install/DLSS-Full-Control.bat'\n", "      - 'install/DLSS-Full-Control.bat'\n      - 'install/Uninstall-DLSS-Full.bat'\n", 'workflow uninstall trigger')
    wf = wf.replace(old_pc, commit).replace(old_ph, stage_hash)
    wf = replace_once(wf, "          $control = Get-Content install/DLSS-Full-Control.bat -Raw\n", "          $control = Get-Content install/DLSS-Full-Control.bat -Raw\n          $uninstaller = Get-Content install/Uninstall-DLSS-Full.bat -Raw\n", 'workflow uninstaller load')
    old_ui_markers = '''            'DLSS Super Resolution quality',
            'Custom Ultra Quality (77%)')) {
'''
    new_ui_markers = '''            'DLSS / DLAA mode',
            'DLAA Native',
            'Custom Ultra Quality (77%)',
            'True render target:',
            'DXVK source now:')) {
'''
    wf = replace_once(wf, old_ui_markers, new_ui_markers, 'workflow public UI markers')
    insert_after_ui = '''          foreach ($marker in @(
            'M3kRequestNrEnabledLive',
            'GTA IV DLSS',
            'Neural Rendering##M3KNrEnabled',
            'Neural Rendering passes (advanced)',
            '1 pass is the tested public default',
            'DLSS / DLAA mode',
            'DLAA Native',
            'Custom Ultra Quality (77%)',
            'True render target:',
            'DXVK source now:')) {
            if (-not $uiStage.Contains($marker)) { throw "Public ReShade controls stage missing marker: $marker" }
          }
'''
    uninstaller_checks = f'''
          foreach ($marker in @(
            'UNINSTALL DLSS FULL -> RESTORE DLAA BASELINE',
            '_DLSS_FULL_DLAA_BASELINE',
            '_DLSS_FULL_PREINSTALL_BACKUP_',
            'Test-DlaaBaseline',
            'DLAA-only runtime restored',
            'ReShade input patch')) {{
            if (-not $uninstaller.Contains($marker)) {{ throw "Uninstaller missing marker: $marker" }}
          }}
          foreach ($forbidden in @('Remove-Item -LiteralPath $Trex -Recurse','nvngx_dlss.dll')) {{
            if ($uninstaller.Contains($forbidden)) {{ throw "Uninstaller contains unsafe removal marker: $forbidden" }}
          }}

          $uninstallerCommit = '{commit}'
          $uninstallerHash = '{uninstall_hash}'
          $uninstallerRaw = Join-Path $env:RUNNER_TEMP 'Uninstall-DLSS-Full.raw.bat'
          Invoke-WebRequest -UseBasicParsing -Uri "https://raw.githubusercontent.com/JungleHam/GTAIV-DLAA-DLSS4.5-DLSS5/$uninstallerCommit/install/Uninstall-DLSS-Full.bat" -OutFile $uninstallerRaw
          if ((Get-FileHash -Algorithm SHA256 $uninstallerRaw).Hash.ToUpperInvariant() -ne $uninstallerHash) {{ throw 'Raw uninstaller hash mismatch' }}
'''
    wf = replace_once(wf, insert_after_ui, insert_after_ui + uninstaller_checks, 'workflow uninstaller validation')

    gen_anchor = "          foreach ($marker in @('M3kRequestNrEnabledLive','GTA IV DLSS','Neural Rendering##M3KNrEnabled','DLSS Super Resolution quality','Custom Ultra Quality (77%)')) {\n"
    gen_new = "          foreach ($marker in @('M3kRequestNrEnabledLive','GTA IV DLSS','Neural Rendering##M3KNrEnabled','DLSS / DLAA mode','DLAA Native','Custom Ultra Quality (77%)','True render target:','DXVK source now:')) {\n"
    wf = replace_once(wf, gen_anchor, gen_new, 'generated UI markers')
    gen_check_anchor = '''          foreach ($marker in @('M3kRequestNrEnabledLive','GTA IV DLSS','Neural Rendering##M3KNrEnabled','DLSS / DLAA mode','DLAA Native','Custom Ultra Quality (77%)','True render target:','DXVK source now:')) {
            if (-not (($generatedVk + $generatedFeed).Contains($marker))) { throw "Generated public UI marker missing: $marker" }
          }
'''
    gen_check_new = gen_check_anchor + '''          if ($generatedFeed.Contains('reshade::register_overlay("M3K Capture Lab"') -or $generatedFeed.Contains('reshade::unregister_overlay("M3K Capture Lab"')) {
            throw 'Generated public Feeder still registers M3K Capture Lab'
          }
'''
    wf = replace_once(wf, gen_check_anchor, gen_check_new, 'capture lab generated verification')
    WORKFLOW.write_text(wf, encoding='utf-8', newline='\n')

    readme = README.read_text(encoding='utf-8')
    readme = readme.replace('- **Neural Rendering OFF / ON**;\n- **Neural Rendering passes (advanced)** — 1 is the tested public default;\n- **DLSS Super Resolution quality** — Custom Ultra Quality (77%), Quality, Balanced, Performance, Ultra Performance.\n',
'''- **DLSS / DLAA mode** — DLAA Native, Custom Ultra Quality (77%), Quality, Balanced, Performance, Ultra Performance;\n- **live resolution diagnostics** — true GTA render target and current DXVK source;\n- **Neural Rendering OFF / ON**;\n- **Neural Rendering passes (advanced)** — 1 is the tested public default.\n''')
    backup_anchor = '## Backup\n\n`Backup-Working-Stack.bat` snapshots the current integration, including the bridge, ReShade configuration, DLSS configuration and Neural Rendering runtime.\n'
    uninstall_doc = '''## Removing DLSS Full\n\nRun `Uninstall-DLSS-Full.bat` beside `GTAIV.exe` with the game and bridge closed. It restores the preserved DLAA-only bridge/DXVK/Feeder baseline while leaving FusionFix, ReShade, the ReShade cross-process input patch, LumeniteFX and `nvngx_dlss.dll` in place.\n\nThe uninstaller prefers `_DLSS_FULL_DLAA_BASELINE`. For older installations it safely falls back to the oldest `_DLSS_FULL_PREINSTALL_BACKUP_*` snapshot that validates as DLAA-only. It creates `_DLSS_FULL_UNINSTALL_SAFETY_*` before changing anything.\n\nAfter removal, launch once and verify DLAA before running `Install-DLSS-Full.bat` again.\n\n'''
    readme = replace_once(readme, backup_anchor, uninstall_doc + backup_anchor, 'README uninstall section')
    README.write_text(readme, encoding='utf-8', newline='\n')


if __name__ == '__main__':
    p = argparse.ArgumentParser()
    p.add_argument('phase', choices=['phase1','phase2'])
    p.add_argument('--commit')
    p.add_argument('--stage-hash')
    p.add_argument('--uninstall-hash')
    a = p.parse_args()
    if a.phase == 'phase1':
        phase1()
    else:
        if not (a.commit and a.stage_hash and a.uninstall_hash):
            raise SystemExit('phase2 requires --commit --stage-hash --uninstall-hash')
        phase2(a.commit, a.stage_hash.upper(), a.uninstall_hash.upper())
