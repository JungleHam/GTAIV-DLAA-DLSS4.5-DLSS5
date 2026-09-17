[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $FeederSource)) { throw "Missing Feeder source: $FeederSource" }
$text = [IO.File]::ReadAllText($FeederSource)
$old = @'
            const UINT active = M3kActiveNrPasses();
            const UINT created = M3kCreatedNrPasses();
            ImGui::Text("Active: %u    Warmed: %u / 5", active, created);
            if (created < requested)
                ImGui::TextColored(ImVec4(1.0f, 0.78f, 0.25f, 1.0f), "Warming pass %u...", created + 1);
'@
$new = @'
            const UINT active = M3kActiveNrPasses();
            ImGui::Text("Active passes: %u", active);
'@
$count = 0; $pos = 0
while (($i = $text.IndexOf($old,$pos,[StringComparison]::Ordinal)) -ge 0) { $count++; $pos = $i + $old.Length }
if ($count -ne 1) { throw "UX/master fixup expected one advanced-status block, found $count" }
$text = $text.Replace($old,$new)
[IO.File]::WriteAllText($FeederSource,$text,[Text.UTF8Encoding]::new($false))
Write-Host 'Public ReShade UX/master fixup applied.'
