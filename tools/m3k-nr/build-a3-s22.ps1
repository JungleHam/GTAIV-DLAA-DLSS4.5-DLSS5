[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$s12Out = Join-Path $toolRoot 'out-m3k-a3-s12'
$out = Join-Path $toolRoot 'out-m3k-a3-s22'
$s12Generated = Join-Path $workRoot 'm3k-src-a3-s12'
$generated = Join-Path $workRoot 'm3k-src-a3-s22'
$obj = Join-Path $workRoot 'obj-a3-s22'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A3-S2.2 gate 1/4: reproduce exact A3-S1.2 sign=-1 capture Feeder ==='
& (Join-Path $toolRoot 'build-a3-s12.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $s12Out 'BUILD-VERIFIED.txt'))) {
    throw 'A3-S1.2 build verification marker missing'
}

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan, $s12Generated)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared input: $p" }
}

Write-Host '=== A3-S2.2 gate 2/4: clone exact generated S1.2 headers ==='
if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated -Recurse -Force }
Copy-Item -LiteralPath $s12Generated -Destination $generated -Recurse

Write-Host '=== A3-S2.2 gate 3/4: synchronize Native/DLAA to A3-S2 bridge jitter ==='
& (Join-Path $toolRoot 'a3-s22-native-dlaa-jitter-sync-stage.ps1') -GeneratedRoot $generated

$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$feedSource = Join-Path $feeder 'src\dlss5-feed.cpp'
$feedText = [IO.File]::ReadAllText($feedSource)
$allText = $nrText + $vkText + $feedText
foreach ($marker in @(
    'Custom Ultra Quality (77%)',
    'M3K-A3-S1.1: raster jitter unchanged; DLSS sign=-1',
    'sr.InJitterOffsetX = bridgeJitterActive ? -bridgeJitter.jitterX : 0.0f;',
    'M3K A3-S1.2 Controlled Capture Lab',
    'M3K-A3-S2.2-NATIVE: raster/DLAA jitter active=',
    'dlaa.InJitterOffsetX = nativeBridgeJitterActive ? -nativeBridgeJitter.jitterX : 0.0f;',
    'dlaa.InJitterOffsetY = nativeBridgeJitterActive ? -nativeBridgeJitter.jitterY : 0.0f;',
    'static constexpr unsigned MaxPasses = 5;')) {
    if ($allText.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated A3-S2.2 source missing marker: $marker"
    }
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A3-S2.2 gate 4/4: compile + CPU contract tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath `
    (Join-Path $out 'dlss5-feed.addon64'), `
    (Join-Path $out 'm3k\m3k-nvngx.dll')

@(
    'M3K A3-S2.2 x64 Native/DLAA synchronized-jitter build passed compile and CPU contract tests.',
    'Required bridge=A3-S2 coherent draw-boundary jitter checkpoint (NOT A3-S2.1 gate).',
    'SR profiles 1..5 retain the proven A3-S1.1 sign=-1 synchronized jitter path unchanged.',
    'Native profile 0 now consumes the same Local\\M3K_GTAIV_Jitter_v1 sample at sign=-1 before SafeEvaluateDLSS.',
    'Native jitter transition/epoch state is tracked separately from SR and forces DLAA history reset on discontinuity.',
    'A3-S1.2 deterministic capture overlay remains present.',
    'No ray tracing/path tracing code is introduced.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A3-S2.2 BUILD VERIFIED: $out"
