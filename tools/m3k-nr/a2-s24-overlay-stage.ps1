[CmdletBinding()]
param([Parameter(Mandatory=$true)][string]$FeederSource)
$ErrorActionPreference = 'Stop'

if (-not (Test-Path -LiteralPath $FeederSource)) { throw "Missing Feeder source: $FeederSource" }
$feed = [IO.File]::ReadAllText($FeederSource)

$anchor = '        ImGui::Text("Active: %u    Warmed: %u / 5", active, created);'
$count = ([regex]::Matches($feed, [regex]::Escape($anchor))).Count
if ($count -ne 1) { throw "A2-S2.4 overlay anchor expected once, found $count" }

$insert = @'
        ImGui::Text("Active: %u    Warmed: %u / 5", active, created);

        ImGui::Spacing();
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
'@

$feed = $feed.Replace($anchor, $insert)
[IO.File]::WriteAllText($FeederSource, $feed, (New-Object Text.UTF8Encoding($false)))

foreach ($marker in @('DLSS reconstruction (live)', 'DLAA only (presenter)', 'Ultra Performance', 'M3kRequestSrProfileLive')) {
    if ($feed.IndexOf($marker, [StringComparison]::Ordinal) -lt 0) { throw "A2-S2.4 overlay marker missing: $marker" }
}
Write-Host 'A2-S2.4 ReShade reconstruction selector inserted.'
