$ErrorActionPreference = 'Stop'
$root = Split-Path $PSScriptRoot -Parent
$inc = Join-Path (Join-Path $root 'm2b') 'feeder-src\src\m3b2b-feed.inc'
if (!(Test-Path $inc)) { throw "Missing $inc" }
$text = (Get-Content $inc -Raw).Replace("`r`n", "`n")
$marker = '// M3H v2 input queue call'
if ($text.Contains($marker)) { Write-Host 'M3H v2 already applied.'; exit 0 }
$old = @'
    M2bCopyTextureToReadback(g.m3b1a_tex12, g_m3g_manual.gReadback,
                             D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    g_m3g_manual.fenceValue = g.fence_value + 1; // EndCommands signal for this D3D12 list
'@.Replace("`r`n", "`n")
$new = @'
    M2bCopyTextureToReadback(g.m3b1a_tex12, g_m3g_manual.gReadback,
                             D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    // M3H v2 input queue call
    if (!M3hQueueCurrentInputs())
        Log("[feed] M3H: exact B-frame MV/depth capture could not be queued for frame=%llu",
            static_cast<unsigned long long>(frame));
    else
        Log("[feed] M3H: exact B-frame MV/depth capture QUEUED frame=%llu",
            static_cast<unsigned long long>(frame));
    g_m3g_manual.fenceValue = g.fence_value + 1; // EndCommands signal for this D3D12 list
'@.Replace("`r`n", "`n")
if (!$text.Contains($old)) { throw 'M3H v2 anchor not found' }
$text = $text.Replace($old, $new)
Set-Content -Path $inc -Value $text -NoNewline -Encoding UTF8
Write-Host 'Applied M3H v2 exact-input queue call.'
