$ErrorActionPreference = 'Stop'

$ring = Join-Path $PSScriptRoot '..\m2b\feeder-src\src\m3b2a-feed.inc'
if (!(Test-Path $ring)) { throw "Missing generated M3B-2A ring include: $ring" }

$text = [IO.File]::ReadAllText($ring)

# BUILD-M3B2A refreshes this generated include from the pristine M3B-2A source on every
# M3B-2B build. Re-enable the already-proven ring for the native producer afterwards.
# Use a whitespace-tolerant regex here: generated source may use CRLF/LF and spacing can
# differ slightly between prior local build trees.
$pattern = '(?s)static\s+bool\s+M3b2aEnabled\s*\(\s*\)\s*\{\s*return\s+g_cfg\.dlfg_m3b2a_stream\s*!=\s*0(?<native>\s*\|\|\s*g_cfg\.dlfg_m3b2b_native\s*!=\s*0)?\s*;\s*\}'
$m = [regex]::Match($text, $pattern)
if (!$m.Success) {
    throw 'Could not locate M3b2aEnabled() in generated ring include; refusing ambiguous patch.'
}

if ($m.Groups['native'].Success) {
    Write-Host 'M3B-2B reusable ring is already enabled for native mode.'
    exit 0
}

$replacement = @'
static bool M3b2aEnabled()
{
    return g_cfg.dlfg_m3b2a_stream != 0 || g_cfg.dlfg_m3b2b_native != 0;
}
'@

$text = [regex]::Replace($text, $pattern, $replacement, 1)
[IO.File]::WriteAllText($ring, $text, [Text.UTF8Encoding]::new($false))

Write-Host 'Re-enabled proven M3B-2A reusable ring for M3B-2B native mode.'
Write-Host '  - ring resources/consumer timeline will exist when dlfg_m3b2b_native=1'
Write-Host '  - ordinary M3B-2A copied-frame producer remains suppressed by the M3B-2B main integration'
