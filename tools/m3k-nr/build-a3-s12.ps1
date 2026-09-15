[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$s11Out = Join-Path $toolRoot 'out-m3k-a3-s11'
$out = Join-Path $toolRoot 'out-m3k-a3-s12'
$s11Generated = Join-Path $workRoot 'm3k-src-a3-s11'
$generated = Join-Path $workRoot 'm3k-src-a3-s12'
$obj = Join-Path $workRoot 'obj-a3-s12'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A3-S1.2 gate 1/4: reproduce exact A3-S1.1 sign-flipped jitter Feeder ==='
& (Join-Path $toolRoot 'build-a3-s11.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $s11Out 'BUILD-VERIFIED.txt'))) {
    throw 'A3-S1.1 build verification marker missing'
}

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan, $s11Generated)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared input: $p" }
}

Write-Host '=== A3-S1.2 gate 2/4: clone exact generated A3-S1.1 headers ==='
if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated -Recurse -Force }
Copy-Item -LiteralPath $s11Generated -Destination $generated -Recurse

Write-Host '=== A3-S1.2 gate 3/4: add controlled in-game 4-state / 3-frame capture lab ==='
$feedSource = Join-Path $feeder 'src\dlss5-feed.cpp'
& (Join-Path $toolRoot 'a3-s12-capture-lab-stage.ps1') -FeederSource $feedSource

$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$feedText = [IO.File]::ReadAllText($feedSource)
$allText = $nrText + $vkText + $feedText
foreach ($marker in @(
    'Custom Ultra Quality (77%)',
    'M3K-A3-S1.1: raster jitter unchanged; DLSS sign=-1',
    'sr.InJitterOffsetX = bridgeJitterActive ? -bridgeJitter.jitterX : 0.0f;',
    'M3K A3-S1.2 Controlled Capture Lab',
    'M3K-A3-S1.2-CAP: SAVED',
    'save_screenshot(postfix)',
    'reshade::register_overlay("M3K Capture Lab", M3kCaptureOverlay)',
    'static constexpr unsigned MaxPasses = 5;')) {
    if ($allText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated A3-S1.2 source missing marker: $marker"
    }
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A3-S1.2 gate 4/4: compile + CPU contract tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath `
    (Join-Path $out 'dlss5-feed.addon64'), `
    (Join-Path $out 'm3k\m3k-nvngx.dll')

@(
    'M3K A3-S1.2 x64 capture-lab build passed compile and CPU-only contract/fallback/shim tests.',
    'Base=A3-S1.1 sign=-1 paired with the unchanged A3-S1 raster-jitter bridge.',
    'Renderer/jitter/NR/SR math is unchanged; this milestone adds only a controlled capture harness.',
    'ReShade overlay exposes four states: NR OFF/ON x Custom UQ77/Ultra Performance.',
    'Each Capture 3 request applies the state, closes overlay, settles >=3.5 s, verifies applied SR and live bridge jitter, then calls ReShade save_screenshot on exactly three consecutive presents.',
    'NR-ON capture additionally waits until Feature18 reports Ready().',
    'Capture metadata is written to dlss5-feed.log with M3K-A3-S1.2-CAP markers.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A3-S1.2 BUILD VERIFIED: $out (reuse exact A3-S1 bridge binary)"
