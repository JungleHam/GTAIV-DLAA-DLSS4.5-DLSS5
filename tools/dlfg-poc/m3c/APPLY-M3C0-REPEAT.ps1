$ErrorActionPreference = 'Stop'

$repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..')).Path
$feeder = Join-Path $repoRoot 'tools\dlfg-poc\m2b\feeder-src\src\dlss5-feed.cpp'
$opti = Join-Path $repoRoot 'tools\dlfg-poc\m3a-os\OptiScaler\OptiScaler\hooks\Vulkan_Hooks.cpp'

foreach ($p in @($feeder, $opti)) {
    if (-not (Test-Path $p)) { throw "Required local source not found: $p" }
}

function Read-Normalized([string]$path) {
    $text = [IO.File]::ReadAllText($path)
    return @{ Text = $text.Replace("`r`n", "`n"); HadCrLf = $text.Contains("`r`n") }
}

function Write-Normalized([string]$path, [string]$text, [bool]$hadCrLf) {
    if ($hadCrLf) { $text = $text.Replace("`n", "`r`n") }
    [IO.File]::WriteAllText($path, $text, [Text.UTF8Encoding]::new($false))
}

# -----------------------------------------------------------------------------
# Feeder: recycle the already-proven one-shot state only after OptiScaler has
# explicitly acknowledged the frame. The Opti side is changed below so that
# acknowledgment happens only after vkQueueWaitIdle, i.e. after Vulkan has
# copied the external image and returned it to VK_QUEUE_FAMILY_EXTERNAL.
# -----------------------------------------------------------------------------
$f = Read-Normalized $feeder
$ft = $f.Text
$feederMarker = 'M3C-0: safely recycled generated frame state'
if (-not $ft.Contains($feederMarker)) {
    if (-not $ft.Contains('M3B-1: moving gameplay detected; arming on current guide probe')) {
        throw 'Feeder does not contain the M3B-1 loading/MV retry fix. Apply APPLY-M3B1-LOADING-RETRY.ps1 first.'
    }

    $consumeSig = 'extern "C" __declspec(dllexport) BOOL WINAPI DLSS5_ConsumeM3B1AExternalFrame(uint64_t serial)'
    $consumePos = $ft.IndexOf($consumeSig)
    if ($consumePos -lt 0) { throw 'Could not find Feeder external-frame consume export.' }

    $stateDecl = @'
// M3C-0 is deliberately bounded. It reuses the proven M3B-1 image only after
// the Vulkan consumer acknowledges that its queue is idle and ownership is back
// at EXTERNAL. This is a resource-reuse stress milestone, not continuous pacing.
static constexpr LONG kM3c0RepeatTarget = 8;
static volatile LONG g_m3c0Consumed = 0;
static volatile LONG g_m3c0RecycleRequest = 0;
static void M3c0ApplyRecycleRequest();

'@
    $ft = $ft.Insert($consumePos, $stateDecl)

    $matchedNeedle = '    const BOOL matched = g_m3b1a_publication.ready != 0 && g_m3b1a_publication.serial == serial;'
    $matchedPos = $ft.IndexOf($matchedNeedle, $consumePos)
    if ($matchedPos -lt 0) { throw 'Could not find Feeder consume matched predicate.' }
    $matchedEnd = $matchedPos + $matchedNeedle.Length
    $ft = $ft.Insert($matchedEnd, "`n    const BOOL genuine = matched && g.m3b1_genuine_serial == serial;")

    $ackNeedle = '    if (matched) Log("[feed] M3B-1A consumer acknowledged serial=%llu", static_cast<unsigned long long>(serial));'
    $ackPos = $ft.IndexOf($ackNeedle, $matchedEnd)
    if ($ackPos -lt 0) { throw 'Could not find Feeder consumer acknowledgement log.' }
    $ackEnd = $ackPos + $ackNeedle.Length
    $ackExtra = @'

    if (genuine)
    {
        const LONG consumed = InterlockedIncrement(&g_m3c0Consumed);
        Log("[feed] M3C-0: consumer safely retired generated serial=%llu (%ld/%ld)",
            static_cast<unsigned long long>(serial), consumed, kM3c0RepeatTarget);
        if (consumed < kM3c0RepeatTarget)
            InterlockedExchange(&g_m3c0RecycleRequest, 1);
        else
            Log("[feed] M3C-0: producer repeat target reached; leaving M3B-1 state complete");
    }
'@
    $ft = $ft.Insert($ackEnd, $ackExtra)

    $m2cConst = 'static const int kM2cIdle = 0, kM2cPrearmed = 1, kM2cWaitingArmed = 2,'
    $m2cPos = $ft.IndexOf($m2cConst)
    if ($m2cPos -lt 0) { throw 'Could not find M2B/M2C state constants for M3C-0 recycle helper.' }
    $recycleHelper = @'
static void M3c0ApplyRecycleRequest()
{
    if (InterlockedExchange(&g_m3c0RecycleRequest, 0) == 0) return;
    if (g_cfg.dlfg_m3b1_present == 0 || g.dlfg_owner != 2 || g.dlfg_state != kM2bPassed)
    {
        Log("[feed] M3C-0: recycle request ignored: owner=%d state=%d enabled=%d",
            g.dlfg_owner, g.dlfg_state, g_cfg.dlfg_m3b1_present);
        return;
    }

    // The Vulkan side only calls Consume after vkQueueWaitIdle and after recording
    // family -> EXTERNAL release, so this single shared image is safe to write again.
    g.dlfg_state = kM2bIdle;
    g.dlfg_history_frame = 0;
    g.dlfg_readback_fence = 0;
    g.dlfg_last_skip_frame = 0;
    g.m3b1a_copy_queued = false;
    g.m3b1a_published = false;
    g.m3b1a_source_frame = 0;
    g.m3b1_ready_value = 0;
    Log("[feed] M3C-0: safely recycled generated frame state; next sequential A/B pair may arm (%ld/%ld consumed)",
        InterlockedCompareExchange(&g_m3c0Consumed, 0, 0), kM3c0RepeatTarget);
}

'@
    $ft = $ft.Insert($m2cPos, $recycleHelper)

    $recordSig = 'static bool M3b1MaybeRecord(UINT64 frame, bool dlss_reset)'
    $recordPos = $ft.IndexOf($recordSig)
    if ($recordPos -lt 0) { throw 'Could not find M3b1MaybeRecord.' }
    $bracePos = $ft.IndexOf('{', $recordPos)
    if ($bracePos -lt 0) { throw 'Could not find M3b1MaybeRecord opening brace.' }
    $ft = $ft.Insert($bracePos + 1, "`n    M3c0ApplyRecycleRequest();")

    Write-Normalized $feeder $ft $f.HadCrLf
    Write-Host 'Patched Feeder for bounded M3C-0 repeat/recycle.'
} else {
    Write-Host 'Feeder M3C-0 patch already applied.'
}

# -----------------------------------------------------------------------------
# OptiScaler: allow later serials, and acknowledge each successful frame only
# after the queue is idle. Queue-idle is intentionally conservative here so the
# single external image and three binary semaphores can be reused safely.
# -----------------------------------------------------------------------------
$o = Read-Normalized $opti
$ot = $o.Text
$optiMarker = 'M3C-0: safe recycle after queue idle'
if (-not $ot.Contains($optiMarker)) {
    $globalNeedle = 'static uint64_t _m3b1aLastSerial = 0;'
    $globalPos = $ot.IndexOf($globalNeedle)
    if ($globalPos -lt 0) { throw 'Could not find OptiScaler M3B-1A globals.' }
    $globalEnd = $globalPos + $globalNeedle.Length
    $globals = @'

static constexpr uint32_t kM3c0RepeatTarget = 8;
static uint32_t _m3c0Presented = 0;
static bool _m3c0Abort = false;
'@
    $ot = $ot.Insert($globalEnd, $globals)

    $oldGuard = '    if (!M3b1aEnabled() || originalResult == nullptr || !queueFamilyKnown || _m3b1aAttempted) return false;'
    if (-not $ot.Contains($oldGuard)) { throw 'Could not find OptiScaler one-shot guard.' }
    $ot = $ot.Replace($oldGuard,
        '    if (!M3b1aEnabled() || originalResult == nullptr || !queueFamilyKnown) return false;')

    $oldQuery = '    if (!_m3b1aQuery(&frame) || frame.serial == _m3b1aLastSerial) return false;'
    if (-not $ot.Contains($oldQuery)) { throw 'Could not find OptiScaler publication query guard.' }
    $ot = $ot.Replace($oldQuery, '    if (!_m3b1aQuery(&frame)) return false;')

    $oldLock = @'
    std::lock_guard lock(_m3bMutex);
    _m3b1aAttempted = true;
    _m3b1aLastSerial = frame.serial;
'@
    $newLock = @'
    std::lock_guard lock(_m3bMutex);
    if (_m3c0Abort || frame.serial == _m3b1aLastSerial) return false;
'@
    if (-not $ot.Contains($oldLock)) { throw 'Could not find OptiScaler one-shot attempt block.' }
    $ot = $ot.Replace($oldLock, $newLock)

    $consumeNeedle = '    if (externalResult == VK_SUCCESS) _m3b1aConsume(frame.serial);'
    $consumePos = $ot.IndexOf($consumeNeedle)
    if ($consumePos -lt 0) { throw 'Could not find OptiScaler external-frame Consume call.' }
    $safeRecycle = @'
    VkResult m3c0IdleResult = VK_ERROR_INITIALIZATION_FAILED;
    BOOL m3c0Consumed = FALSE;
    if (externalResult == VK_SUCCESS && *originalResult == VK_SUCCESS)
    {
        // M3C-0: safe recycle after queue idle. This deliberately stalls here;
        // removing this stall requires a resource ring + explicit completion signal.
        m3c0IdleResult = vkQueueWaitIdle(queue);
        LOG_INFO("M3C-0: safe recycle after queue idle -> {} for serial={}",
                 (int) m3c0IdleResult, frame.serial);
        if (m3c0IdleResult == VK_SUCCESS)
        {
            m3c0Consumed = _m3b1aConsume(frame.serial);
            if (m3c0Consumed)
            {
                _m3b1aLastSerial = frame.serial;
                ++_m3c0Presented;
                LOG_INFO("M3C-0: generated frame {}/{} presented and safely recycled; serial={}",
                         _m3c0Presented, kM3c0RepeatTarget, frame.serial);
                if (_m3c0Presented == kM3c0RepeatTarget)
                    LOG_INFO("MILESTONE M3C-0 PASSED: 8 genuine DLSS-G frames generated, presented, and safely recycled through the single-image handoff");
            }
        }
    }
    if (externalResult != VK_SUCCESS || *originalResult != VK_SUCCESS ||
        m3c0IdleResult != VK_SUCCESS || !m3c0Consumed)
    {
        _m3c0Abort = true;
        LOG_ERROR("M3C-0: repeat sequence aborted: external={} original={} idle={} consumed={}",
                  (int) externalResult, (int) *originalResult, (int) m3c0IdleResult, m3c0Consumed != FALSE);
    }
'@
    $ot = $ot.Remove($consumePos, $consumeNeedle.Length).Insert($consumePos, $safeRecycle)

    Write-Normalized $opti $ot $o.HadCrLf
    Write-Host 'Patched OptiScaler for bounded M3C-0 repeated external presents.'
} else {
    Write-Host 'OptiScaler M3C-0 patch already applied.'
}

Write-Host ''
Write-Host 'M3C-0 source staging complete.'
Write-Host 'This is NOT continuous 2x pacing yet. It is an 8-frame safe-reuse stress test.'
