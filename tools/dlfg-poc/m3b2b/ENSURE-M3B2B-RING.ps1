$ErrorActionPreference = 'Stop'

$ring = Join-Path $PSScriptRoot '..\m2b\feeder-src\src\m3b2a-feed.inc'
if (!(Test-Path $ring)) { throw "Missing generated M3B-2A ring include: $ring" }

$text = [IO.File]::ReadAllText($ring)
$hadCrLf = $text.Contains("`r`n")
$norm = $text.Replace("`r`n", "`n")

$native = @'
static bool M3b2aEnabled()
{
    return g_cfg.dlfg_m3b2a_stream != 0 || g_cfg.dlfg_m3b2b_native != 0;
}
'@

$base = @'
static bool M3b2aEnabled()
{
    return g_cfg.dlfg_m3b2a_stream != 0;
}
'@

if ($norm.Contains($native)) {
    Write-Host 'M3B-2B reusable ring is already enabled for native mode.'
    exit 0
}

if (!$norm.Contains($base)) {
    throw 'Could not find M3B-2A transport enable helper; refusing ambiguous patch.'
}

$norm = $norm.Replace($base, $native)
if ($hadCrLf) { $norm = $norm.Replace("`n", "`r`n") }
[IO.File]::WriteAllText($ring, $norm, [Text.UTF8Encoding]::new($false))

Write-Host 'Re-enabled proven M3B-2A reusable ring for M3B-2B native mode.'
Write-Host '  - ring resources/consumer timeline will exist when dlfg_m3b2b_native=1'
Write-Host '  - ordinary M3B-2A copied-frame producer remains suppressed by the M3B-2B main integration'
