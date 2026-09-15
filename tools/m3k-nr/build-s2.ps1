[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$out = Join-Path $toolRoot 'out-m3k-s2'
$generated = Join-Path $workRoot 'm3k-src-s2'
$obj = Join-Path $workRoot 'obj-s2'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

# First reproduce the already-proven A2-S1A Feeder build. Besides acting as a
# regression gate, this deterministically creates the pinned dependency checkouts
# and the generated Feeder source with the A2-S1 staging transforms applied.
Write-Host '=== A2-S2 gate 1/3: reproduce proven A2-S1 build ==='
& (Join-Path $toolRoot 'build.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $baseOut 'BUILD-VERIFIED.txt'))) {
    throw 'Baseline A2-S1 build verification marker missing'
}

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder, $ngx, $vulkan)) {
    if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared dependency: $p" }
}

# Build-only transform: the committed A2-S1 headers remain untouched until the
# first real GTA runtime test proves the NR->SR chain.
Write-Host '=== A2-S2 gate 2/3: generate low-res NR->SR source ==='
$stage = Join-Path $toolRoot 'a2-s2-stage.ps1'
if (-not (Test-Path -LiteralPath $stage)) { throw "Missing A2-S2 stage: $stage" }
& $stage -SourceRoot (Join-Path $toolRoot 'src') -GeneratedRoot $generated

$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
foreach ($marker in @(
    'M3K-A2-S2: feature 18 armed at true source',
    'M3K-A2-S2: SR color source=',
    'M3K-A2-S2: feature 18 uses')) {
    if (($vkText + $nrText).IndexOf($marker, [StringComparison]::Ordinal) -lt 0) {
        throw "Generated source missing marker: $marker"
    }
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out, (Join-Path $out 'm3k'), $obj, (Join-Path $out 'licenses') | Out-Null

Write-Host '=== A2-S2 gate 3/3: compile generated source + CPU tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder, $ngx, $vulkan, $out, $obj, $generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'), (Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -LiteralPath (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $out 'dlss5-feed.addon64'), (Join-Path $out 'm3k\m3k-nvngx.dll')
@(
    'M3K A2-S2 x64 build passed compile and CPU-only contract/fallback/shim tests.',
    'Functional target: true low-res DXVK source -> feature18 NR at low-res -> DLSS SR -> presenter.',
    'Jitter remains 0 for the first GPU runtime gate.',
    'This is NOT yet a GTA/feature18 GPU runtime validation.',
    'Feeder=3f624855276c4bde55145c712782477639b30e85',
    'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
    'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
    ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A2-S2 BUILD VERIFIED: $out (manual install only)"
