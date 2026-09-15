[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$toolRoot = $PSScriptRoot
$workRoot = Join-Path $toolRoot '_work'
$outputRoot = Join-Path $toolRoot 'out-m3k'
New-Item -ItemType Directory -Force -Path $workRoot, $outputRoot, "$outputRoot/m3k", "$workRoot/obj", "$outputRoot/licenses" | Out-Null

# Invalidate only our exact generated files, even if dependency validation fails.
foreach ($file in @('dlss5-feed.addon64', 'm3k/m3k-nvngx.dll', 'm3k-tests.exe', 'BUILD-VERIFIED.txt')) {
    $artifact = Join-Path $outputRoot $file
    if (Test-Path -LiteralPath $artifact) { Remove-Item -LiteralPath $artifact }
}

function Run([string]$Program, [string[]]$Arguments) {
    & $Program @Arguments
    if ($LASTEXITCODE -ne 0) { throw "$Program failed with exit code $LASTEXITCODE" }
}
function Checkout([string]$Name, [string]$Url, [string]$Commit, [string[]]$Sparse = @()) {
    $path = Join-Path $workRoot $Name
    if (-not (Test-Path -LiteralPath "$path/.git")) {
        Run git @('init', '--quiet', $path)
        Run git @('-C', $path, 'remote', 'add', 'origin', $Url)
        Run git @('-C', $path, 'fetch', '--quiet', '--depth', '1', '--filter=blob:none', 'origin', $Commit)
        if ($Sparse.Count) { Run git (@('-C', $path, 'sparse-checkout', 'set') + $Sparse) }
        Run git @('-C', $path, 'checkout', '--quiet', '--detach', $Commit)
    }
    $actual = & git -C $path rev-parse HEAD
    if ($LASTEXITCODE -ne 0 -or $actual -ne $Commit) { throw "Wrong revision in $path; expected $Commit, got $actual" }
    return $path
}

# All source inputs are immutable. No runtime DLLs, installers, registry writes,
# game paths, or deployment actions are part of this build.
$feeder = Checkout 'feeder' 'https://github.com/jlrouzies-fr/DLSS5-Feeder.git' '3f624855276c4bde55145c712782477639b30e85'
$ngx = Checkout 'ngx-sdk' 'https://github.com/NVIDIA/DLSS.git' '374959484e79a640feaba44c93ac8cfb0a03f5b5' @('include', 'lib/Windows_x86_64/x64')
$vulkan = Checkout 'vulkan-headers' 'https://github.com/KhronosGroup/Vulkan-Headers.git' '2cd90f9d20df57eac214c148f3aed885372ddcfe' @('include')
foreach ($dependency in @($ngx, $vulkan)) {
    $edits = @(& git -C $dependency status --porcelain --untracked-files=no)
    if ($LASTEXITCODE -ne 0 -or $edits.Count) { throw "Modified dependency checkout: $dependency" }
}

$patch = Join-Path $toolRoot 'feeder-m3k.patch'

# The Feeder checkout is generated staging state. Reset only its one patched source
# file so repeated A2 builds are deterministic even after local staging edits were
# injected by a previous build.
Run git @('-C', $feeder, 'checkout', '--', 'src/dlss5-feed.cpp')
Run git @('-C', $feeder, 'apply', '--check', $patch)
Run git @('-C', $feeder, 'apply', $patch)
Run git @('-C', $feeder, 'apply', '--check', '--reverse', $patch)

# Preserve exact-source validation for the primary M3K patch before any A2 staging edits.
$patchText = [IO.File]::ReadAllText($patch)
if ($patchText -notmatch 'index [0-9a-f]{40}\.\.([0-9a-f]{40})') { throw 'Patch must carry full source hashes' }
$expectedSource = $Matches[1]
$actualSource = & git -C $feeder hash-object --path=src/dlss5-feed.cpp src/dlss5-feed.cpp
if ($LASTEXITCODE -ne 0 -or $actualSource -ne $expectedSource) { throw 'Feeder source differs from the exact M3K patch result' }

$feedSource = Join-Path $feeder 'src/dlss5-feed.cpp'
$feedText = [IO.File]::ReadAllText($feedSource)

function Replace-ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
    $count = 0
    $pos = 0
    while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) {
        $count++
        $pos = $i + $Old.Length
    }
    if ($count -ne 1) { throw "${Label}: expected exactly one source match, found $count" }
    return $Text.Replace($Old, $New)
}

# A2-S0.5: two diagnostic call sites. Both points have the final Vulkan image parked
# as copy_dest; SourceProof=0 makes them a no-op.
$oneSubmitOld = @'
                if (n > 1)
                {
                    const UINT wh1 = g_cfg.half_home != 0 ? w / 2 : w;
                    FeedVkCopyBufferToImage(&g.vk, cb, g.vk_home_buf, bb_img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                            wh1, h, g.home_pitch / HomeTexelBytes(g.output_fmt),
                                            g.home_slice * ((n - 1) & 1));
                }
                const resource       res1[1]  = { bb_res };
'@
$oneSubmitNew = @'
                if (n > 1)
                {
                    const UINT wh1 = g_cfg.half_home != 0 ? w / 2 : w;
                    FeedVkCopyBufferToImage(&g.vk, cb, g.vk_home_buf, bb_img, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
                                            wh1, h, g.home_pitch / HomeTexelBytes(g.output_fmt),
                                            g.home_slice * ((n - 1) & 1));
                }
                M3kSourceGpuProof(cb, bb_img, w, h);
                const resource       res1[1]  = { bb_res };
'@

$normalOld = @'
                if (g_vk_probe.active)
                {
                    cl->barrier(bb_res, resource_usage::copy_dest, resource_usage::copy_source);
                    FeedVkProbeVk(cb, 3, bb_img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL); // F: actual copy-home target
                    cl->barrier(bb_res, resource_usage::copy_source, resource_usage::copy_dest);
                }
            }
            {
                const resource       res[1]  = { bb_res };
'@
$normalNew = @'
                if (g_vk_probe.active)
                {
                    cl->barrier(bb_res, resource_usage::copy_dest, resource_usage::copy_source);
                    FeedVkProbeVk(cb, 3, bb_img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL); // F: actual copy-home target
                    cl->barrier(bb_res, resource_usage::copy_source, resource_usage::copy_dest);
                }
                M3kSourceGpuProof(cb, bb_img, w, h);
            }
            {
                const resource       res[1]  = { bb_res };
'@

$feedText = Replace-ExactOnce $feedText $oneSubmitOld $oneSubmitNew 'A2-S0.5 one-submit insertion'
$feedText = Replace-ExactOnce $feedText $normalOld $normalNew 'A2-S0.5 normal copy-home insertion'

# A2-S1: deterministic true-source SR staging edits live separately so this build file
# remains a small orchestration layer. They are applied only after the pinned primary
# patch and S0.5 edits validated above.
$a2s1Stage = Join-Path $toolRoot 'a2-s1-stage.ps1'
if (-not (Test-Path -LiteralPath $a2s1Stage)) { throw "Missing A2-S1 staging script: $a2s1Stage" }
. $a2s1Stage
$feedText = Invoke-M3kA2S1Stage -FeedText $feedText

[IO.File]::WriteAllText($feedSource, $feedText, (New-Object Text.UTF8Encoding($false)))

# Refuse unrelated tracked edits in the staging source.
$changed = @(& git -C $feeder diff --name-only)
if ($changed.Count -ne 1 -or $changed[0] -ne 'src/dlss5-feed.cpp') { throw 'Unexpected tracked changes in Feeder staging checkout' }
Run git @('-C', $feeder, 'diff', '--check')

try {
    Run "$toolRoot/compile.bat" @($feeder, $ngx, $vulkan, $outputRoot, "$workRoot/obj")
    Run "$outputRoot/m3k-tests.exe" @("$outputRoot/m3k/m3k-nvngx.dll")
    Copy-Item -LiteralPath "$toolRoot/m3k-nr.ini" -Destination "$outputRoot/m3k-nr.ini"
    Copy-Item -LiteralPath "$toolRoot/README.md", "$toolRoot/NOTICE" -Destination $outputRoot
    Copy-Item -LiteralPath "$toolRoot/licenses/Apache-2.0.txt" -Destination "$outputRoot/licenses"
    Copy-Item -LiteralPath "$feeder/LICENSE" -Destination "$outputRoot/licenses/Feeder-MIT.txt"
    Copy-Item -LiteralPath "$feeder/external/minhook/LICENSE.txt" -Destination "$outputRoot/licenses/MinHook.txt"
    Copy-Item -LiteralPath "$feeder/external/imgui/LICENSE.txt" -Destination "$outputRoot/licenses/ImGui.txt"
    Copy-Item -LiteralPath "$toolRoot/licenses/ReShade-NIGos-MIT.txt" -Destination "$outputRoot/licenses"
    Copy-Item -LiteralPath "$ngx/LICENSE.txt" -Destination "$outputRoot/licenses/NVIDIA-SDK.txt"
    $hashes = Get-FileHash -Algorithm SHA256 -LiteralPath "$outputRoot/dlss5-feed.addon64", "$outputRoot/m3k/m3k-nvngx.dll"
    @('M3K x64 build and CPU-only contract/fallback/shim tests passed.',
      'Not a feature-18 or GTA GPU runtime validation.',
      'Feeder=3f624855276c4bde55145c712782477639b30e85',
      'NGX SDK=374959484e79a640feaba44c93ac8cfb0a03f5b5',
      'Vulkan headers=2cd90f9d20df57eac214c148f3aed885372ddcfe',
      ($hashes | ForEach-Object { "$($_.Hash)  $([IO.Path]::GetFileName($_.Path))" })) | Set-Content -Encoding UTF8 -LiteralPath "$outputRoot/BUILD-VERIFIED.txt"
    Write-Host "M3K BUILD VERIFIED: $outputRoot (manual install only)"
} catch {
    foreach ($file in @('dlss5-feed.addon64', 'm3k/m3k-nvngx.dll', 'BUILD-VERIFIED.txt')) {
        $artifact = Join-Path $outputRoot $file
        if (Test-Path -LiteralPath $artifact) { Remove-Item -LiteralPath $artifact }
    }
    throw
}
