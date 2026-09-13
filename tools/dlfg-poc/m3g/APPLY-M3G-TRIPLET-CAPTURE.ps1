$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m2b = Join-Path $root 'm2b'
$feedCpp = Join-Path $m2b 'feeder-src\src\dlss5-feed.cpp'
if (!(Test-Path $feedCpp)) { throw "Missing $feedCpp. Run BUILD-M3F.bat first." }

function Read-Normalized([string]$path) {
    return (Get-Content $path -Raw).Replace("`r`n", "`n")
}
function Write-Normalized([string]$path, [string]$text) {
    Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8
}

$text = Read-Normalized $feedCpp

# M3G deliberately does not change the DLSS-G inputs, transport, or pacing. It only
# exports the already-existing M3B-1 validation triplet that the Feeder has in CPU
# readback memory: sequential real A, generated midpoint G, sequential real B.
if (!$text.Contains('// M3G objective triplet writer')) {
    $anchor = @'
static void M2bPollReadback()
{
'@
    if (!$text.Contains($anchor)) { throw 'M3G anchor not found: M2bPollReadback' }

    $helper = @'
// M3G objective triplet writer. The M3B-1 bootstrap already owns three CPU readbacks
// (previous real, current real, generated output). Save all three without changing the
// render path so they can be analysed offline instead of judged by eye in real time.
static bool M3gWriteBmpNamed(const uint8_t *p, UINT row_pitch, const char *name, char path[MAX_PATH])
{
    if (p == nullptr || name == nullptr || name[0] == '\0') return false;
    GetModuleFileNameA(g_self, path, MAX_PATH);
    char *slash = strrchr(path, '\\');
    if (slash == nullptr) return false;
    strcpy_s(slash + 1, MAX_PATH - static_cast<size_t>(slash + 1 - path), name);

    FILE *f = nullptr;
    if (fopen_s(&f, path, "wb") != 0 || f == nullptr) return false;

    BITMAPFILEHEADER fileHeader = {};
    BITMAPINFOHEADER infoHeader = {};
    const DWORD imageBytes = static_cast<DWORD>(g.width * g.height * 4u);
    fileHeader.bfType = 0x4D42;
    fileHeader.bfOffBits = sizeof(fileHeader) + sizeof(infoHeader);
    fileHeader.bfSize = fileHeader.bfOffBits + imageBytes;
    infoHeader.biSize = sizeof(infoHeader);
    infoHeader.biWidth = static_cast<LONG>(g.width);
    infoHeader.biHeight = static_cast<LONG>(g.height);
    infoHeader.biPlanes = 1;
    infoHeader.biBitCount = 32;
    infoHeader.biCompression = BI_RGB;
    infoHeader.biSizeImage = imageBytes;

    bool ok = fwrite(&fileHeader, 1, sizeof(fileHeader), f) == sizeof(fileHeader) &&
              fwrite(&infoHeader, 1, sizeof(infoHeader), f) == sizeof(infoHeader);
    for (UINT y = g.height; ok && y-- > 0; )
        ok = fwrite(p + static_cast<size_t>(y) * row_pitch, 1, g.width * 4u, f) == g.width * 4u;
    fclose(f);
    return ok;
}

'@
    $text = $text.Replace($anchor, $helper + $anchor)
}

if (!$text.Contains('// M3G objective triplet export')) {
    $anchor2 = @'
    char bmp[MAX_PATH] = {};
    const bool bmp_ok = M2bWriteBmp(o, pitch, bmp);
'@
    if (!$text.Contains($anchor2)) { throw 'M3G anchor not found: generated BMP write' }

    $triplet = @'
    // M3G objective triplet export. In native M3B-2B mode this readback is the proven
    // M3B-1 bootstrap pair: A and B are sequential real frames and G is NVIDIA feature-11
    // interpolation between them. Saving is CPU-side only after the existing fence retired.
    if (g_cfg.dlfg_m3b2b_native != 0)
    {
        char m3gA[MAX_PATH] = {};
        char m3gG[MAX_PATH] = {};
        char m3gB[MAX_PATH] = {};
        const bool aOk = M3gWriteBmpNamed(a, pitch, "dlfg-m3g-A-prev-real.bmp", m3gA);
        const bool gOk = M3gWriteBmpNamed(o, pitch, "dlfg-m3g-G-generated.bmp", m3gG);
        const bool bOk = M3gWriteBmpNamed(b, pitch, "dlfg-m3g-B-current-real.bmp", m3gB);
        Log("[feed] M3G: objective triplet saved A=%d G=%d B=%d historyFrame=%llu sourceFrame=%llu paths='%s' '%s' '%s'",
            aOk ? 1 : 0, gOk ? 1 : 0, bOk ? 1 : 0,
            static_cast<unsigned long long>(g.dlfg_history_frame),
            static_cast<unsigned long long>(g.m3b1a_source_frame),
            m3gA, m3gG, m3gB);
    }

    char bmp[MAX_PATH] = {};
    const bool bmp_ok = M2bWriteBmp(o, pitch, bmp);
'@
    $text = $text.Replace($anchor2, $triplet)
}

Write-Normalized $feedCpp $text

Write-Host 'Applied M3G objective A/G/B triplet capture.'
Write-Host '  - no DLSS-G input/transport/pacing changes'
Write-Host '  - exports sequential real A, generated G, sequential real B from existing M3B-1 readbacks'
Write-Host '  - files are written next to the live Feeder addon when the bootstrap readback completes'
Write-Host '  - expected filenames: dlfg-m3g-A-prev-real.bmp, dlfg-m3g-G-generated.bmp, dlfg-m3g-B-current-real.bmp'
