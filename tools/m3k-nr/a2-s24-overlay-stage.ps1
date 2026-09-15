[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$FeederSource)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $FeederSource)) { throw "Missing Feeder source: $FeederSource" }
$feed = [IO.File]::ReadAllText($FeederSource)

$needle = 'if (ImGui::CollapsingHeader("M3K Neural Rendering"))'
$count = ([regex]::Matches($feed, [regex]::Escape($needle))).Count
if ($count -ne 1) { throw "A2-S2.4 M3K panel header expected once, found $count" }

$start = $feed.IndexOf($needle, [StringComparison]::Ordinal)
$brace = $feed.IndexOf('{', $start + $needle.Length)
if ($start -lt 0 -or $brace -lt 0) { throw 'A2-S2.4 could not locate M3K panel opening brace' }

$insert = @'

        ImGui::TextUnformatted("DLSS reconstruction (live)");
        int srProfile = static_cast<int>(M3kRequestedSrProfile());
        const char *srItems = "DLAA only (presenter)\0Ultra Quality\0Quality\0Balanced\0Performance\0Ultra Performance\0\0";
        if (ImGui::Combo("Mode##M3KSRProfile", &srProfile, srItems))
            M3kRequestSrProfileLive(static_cast<UINT>(srProfile));
        ImGui::Text("Applied: %s", M3kSrProfileName(M3kAppliedSrProfile()));
        if (M3kRequestedSrProfile() == 0)
            ImGui::TextWrapped("DLAA-only is a presenter-space A/B baseline. GTA's true S1B render remains 1600x900; it is not native-rendered 1440p DLAA.");
        else
            ImGui::TextWrapped("SR profiles keep the true DXVK source resolution fixed and change NVIDIA's DLSS perf-quality profile. Unsupported profiles at this input size are rejected safely.");
        ImGui::Separator();
'@

$feed = $feed.Insert($brace + 1, $insert)
[IO.File]::WriteAllText($FeederSource, $feed, (New-Object Text.UTF8Encoding($false)))

foreach ($marker in @('DLSS reconstruction (live)', 'DLAA only (presenter)', 'Ultra Performance', 'M3kRequestSrProfileLive')) {
    if ($feed.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) { throw "A2-S2.4 overlay marker missing: $marker" }
}
Write-Host 'A2-S2.4 ReShade reconstruction selector inserted at M3K panel header.'
