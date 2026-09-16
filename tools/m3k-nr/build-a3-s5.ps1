[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'

$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$baseOut = Join-Path $toolRoot 'out-m3k'
$s4Out = Join-Path $toolRoot 'out-m3k-a3-s4'
$out = Join-Path $toolRoot 'out-m3k-a3-s5'
$s4Generated = Join-Path $workRoot 'm3k-src-a3-s4'
$generated = Join-Path $workRoot 'm3k-src-a3-s5'
$obj = Join-Path $workRoot 'obj-a3-s5'

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}

Write-Host '=== A3-S5 gate 1/4: reproduce exact A3-S4 manual-resolution Feeder ==='
& (Join-Path $toolRoot 'build-a3-s4.ps1')
if (-not (Test-Path -LiteralPath (Join-Path $s4Out 'BUILD-VERIFIED.txt'))) { throw 'A3-S4 verification marker missing' }

$feeder = Join-Path $workRoot 'feeder'
$ngx = Join-Path $workRoot 'ngx-sdk'
$vulkan = Join-Path $workRoot 'vulkan-headers'
foreach ($p in @($feeder,$ngx,$vulkan,$s4Generated)) { if (-not (Test-Path -LiteralPath $p)) { throw "Missing prepared input: $p" } }

Write-Host '=== A3-S5 gate 2/4: clone exact A3-S4 generated headers ==='
if (Test-Path -LiteralPath $generated) { Remove-Item -LiteralPath $generated -Recurse -Force }
Copy-Item -LiteralPath $s4Generated -Destination $generated -Recurse

Write-Host '=== A3-S5 gate 3/4: add automatic known-good startup primer ==='
& (Join-Path $toolRoot 'a3-s5-startup-prime-stage.ps1') -GeneratedRoot $generated

$nrText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_nr.h'))
$vkText = [IO.File]::ReadAllText((Join-Path $generated 'm3k_vk.h'))
$feedText = [IO.File]::ReadAllText((Join-Path $feeder 'src\dlss5-feed.cpp'))
$allText = $nrText + $vkText + $feedText
foreach ($marker in @(
    'M3K-A3-S1.1: raster jitter unchanged; DLSS sign=-1',
    'M3K-A3-S5: STARTUP PRIME armed',
    'M3K-A3-S5: STARTUP PRIME COMPLETE',
    'STARTUP PRIME: Quality contract',
    'StartupPrimeWidth',
    'M3kStartupPrimeObserve(bridgeJitterActive')) {
    if ($allText.IndexOf($marker,[StringComparison]::Ordinal) -lt 0) { throw "Generated A3-S5 source missing marker: $marker" }
}

if (Test-Path -LiteralPath $out) { Remove-Item -LiteralPath $out -Recurse -Force }
if (Test-Path -LiteralPath $obj) { Remove-Item -LiteralPath $obj -Recurse -Force }
New-Item -ItemType Directory -Force -Path $out,(Join-Path $out 'm3k'),$obj,(Join-Path $out 'licenses') | Out-Null

Write-Host '=== A3-S5 gate 4/4: compile + CPU tests ==='
Run (Join-Path $toolRoot 'compile-s2.bat') @($feeder,$ngx,$vulkan,$out,$obj,$generated)
Run (Join-Path $out 'm3k-tests.exe') @((Join-Path $out 'm3k\m3k-nvngx.dll'))

Copy-Item -LiteralPath (Join-Path $toolRoot 'm3k-nr.ini') -Destination $out
Copy-Item -LiteralPath (Join-Path $toolRoot 'README.md'),(Join-Path $toolRoot 'NOTICE') -Destination $out
Copy-Item -Path (Join-Path $baseOut 'licenses\*') -Destination (Join-Path $out 'licenses') -Force

$hashes = Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $out 'dlss5-feed.addon64'),(Join-Path $out 'm3k\m3k-nvngx.dll')
@(
  'M3K A3-S5 x64 production-candidate Feeder: automatic startup primer.',
  'Base=A3-S4 diagnostics; intended bridge=exact accepted A3-S2 coherent-jitter d3d9.dll.',
  'StartupPrime=1 forces 1485x835 with supported Quality contract until A3-S2 jitter handoff is live for 180 successful SR frames.',
  'Then the primer invalidates the resolution plan and releases automatically to the already-saved SRProfile.',
  'ManualRender remains available but is disabled in the portable production-candidate config.',
  'No A3-S2 bridge binary, projection math, jitter sequence, jitter sign, NR math, or MV scaling is changed.',
  ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })
) | Set-Content -Encoding UTF8 -LiteralPath (Join-Path $out 'BUILD-VERIFIED.txt')

Write-Host "M3K A3-S5 BUILD VERIFIED: $out"