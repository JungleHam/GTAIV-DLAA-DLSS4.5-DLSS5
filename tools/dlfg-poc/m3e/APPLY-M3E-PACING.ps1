$ErrorActionPreference = 'Stop'

$root = Split-Path $PSScriptRoot -Parent
$m3a = Join-Path $root 'm3a-os'
$configH = Join-Path $m3a 'OptiScaler\OptiScaler\Config.h'
$configCpp = Join-Path $m3a 'OptiScaler\OptiScaler\Config.cpp'
$ini = Join-Path $m3a 'OptiScaler\OptiScaler.ini'
$optiInc = Join-Path $m3a 'OptiScaler\OptiScaler\hooks\m3b2a-optiscaler.inc'

foreach ($p in @($configH, $configCpp, $ini, $optiInc)) {
    if (!(Test-Path $p)) { throw "Missing $p. Run BUILD-M3D.bat first." }
}

function Read-Normalized([string]$path) {
    return (Get-Content $path -Raw).Replace("`r`n", "`n")
}
function Write-Normalized([string]$path, [string]$text) {
    Set-Content -Path $path -Value $text -NoNewline -Encoding UTF8
}
function Replace-Exact([ref]$textRef, [string]$old, [string]$new, [string]$already, [string]$name) {
    $old = $old.Replace("`r`n", "`n")
    $new = $new.Replace("`r`n", "`n")
    if ($already -and $textRef.Value.Contains($already)) { return }
    if (!$textRef.Value.Contains($old)) { throw "M3E anchor not found: $name" }
    $textRef.Value = $textRef.Value.Replace($old, $new)
}

# -----------------------------------------------------------------------------
# OptiScaler config: default-off pacing switch.
# -----------------------------------------------------------------------------
$text = Read-Normalized $configH
$ref = [ref]$text
Replace-Exact $ref `
'    CustomOptional<bool> GtaivVulkanContinuousExternalPresent { false };' `
'    CustomOptional<bool> GtaivVulkanContinuousExternalPresent { false };
    // M3E: pace generated/original presents at half of the measured real-frame interval.
    CustomOptional<bool> GtaivVulkanHalfIntervalPacing { false };' `
'GtaivVulkanHalfIntervalPacing' `
'Config.h pacing field'
Write-Normalized $configH $ref.Value

$text = Read-Normalized $configCpp
$ref = [ref]$text
Replace-Exact $ref `
'            GtaivVulkanContinuousExternalPresent.set_from_config(readBool("Debug", "GtaivVulkanContinuousExternalPresent"));' `
'            GtaivVulkanContinuousExternalPresent.set_from_config(readBool("Debug", "GtaivVulkanContinuousExternalPresent"));
            GtaivVulkanHalfIntervalPacing.set_from_config(readBool("Debug", "GtaivVulkanHalfIntervalPacing"));' `
'GtaivVulkanHalfIntervalPacing.set_from_config' `
'Config.cpp pacing read'
Replace-Exact $ref `
'        ini.SetValue("Debug", "GtaivVulkanContinuousExternalPresent",
                     GetBoolValue(Instance()->GtaivVulkanContinuousExternalPresent.value_for_config()).c_str());' `
'        ini.SetValue("Debug", "GtaivVulkanContinuousExternalPresent",
                     GetBoolValue(Instance()->GtaivVulkanContinuousExternalPresent.value_for_config()).c_str());
        ini.SetValue("Debug", "GtaivVulkanHalfIntervalPacing",
                     GetBoolValue(Instance()->GtaivVulkanHalfIntervalPacing.value_for_config()).c_str());' `
'Instance()->GtaivVulkanHalfIntervalPacing.value_for_config' `
'Config.cpp pacing save'
Write-Normalized $configCpp $ref.Value

$text = Read-Normalized $ini
$ref = [ref]$text
Replace-Exact $ref `
'GtaivVulkanContinuousExternalPresent=false' `
'GtaivVulkanContinuousExternalPresent=false
; GTA IV M3E: evenly space generated/original presents. Default false.
GtaivVulkanHalfIntervalPacing=false' `
'GtaivVulkanHalfIntervalPacing=' `
'OptiScaler.ini pacing key'
Write-Normalized $ini $ref.Value

# -----------------------------------------------------------------------------
# Consumer pacing. M3D already makes frame identity/order correct. M3E changes only
# the temporal spacing between the inserted generated present and the original real present.
# -----------------------------------------------------------------------------
$text = Read-Normalized $optiInc
$ref = [ref]$text

Replace-Exact $ref `
'    uint64_t lastSerial = 0;
    bool milestoneLogged = false;
};' `
'    uint64_t lastSerial = 0;
    bool milestoneLogged = false;

    // M3E: learn the pre-pacing real-present period, freeze it, then target its midpoint.
    LARGE_INTEGER m3eLastArrival {};
    double m3eBaselineMs = 0.0;
    uint32_t m3eBaselineSamples = 0;
    bool m3eBaselineLocked = false;
    uint64_t m3ePacedPairs = 0;
};' `
'm3eBaselineSamples' `
'M3E consumer state'

$helperOld = @'
static bool M3b2aPresentOk(VkResult r)
{
    return r == VK_SUCCESS || r == VK_SUBOPTIMAL_KHR;
}
'@
$helperNew = @'
static bool M3b2aPresentOk(VkResult r)
{
    return r == VK_SUCCESS || r == VK_SUBOPTIMAL_KHR;
}

// M3E display-pacing integration marker.
static bool M3ePacingEnabled()
{
    return Config::Instance()->GtaivVulkanHalfIntervalPacing.value_or_default();
}

static double M3eQpcDeltaMs(const LARGE_INTEGER& a, const LARGE_INTEGER& b)
{
    static LARGE_INTEGER freq = []() { LARGE_INTEGER f {}; QueryPerformanceFrequency(&f); return f; }();
    return freq.QuadPart > 0
        ? (static_cast<double>(b.QuadPart - a.QuadPart) * 1000.0 / static_cast<double>(freq.QuadPart))
        : 0.0;
}

static LONGLONG M3eMsToQpc(double ms)
{
    static LARGE_INTEGER freq = []() { LARGE_INTEGER f {}; QueryPerformanceFrequency(&f); return f; }();
    return freq.QuadPart > 0 ? static_cast<LONGLONG>(ms * static_cast<double>(freq.QuadPart) / 1000.0) : 0;
}

static void M3eWaitUntilQpc(LONGLONG target)
{
    LARGE_INTEGER now {};
    for (;;)
    {
        QueryPerformanceCounter(&now);
        if (now.QuadPart >= target) break;
        static LARGE_INTEGER freq = []() { LARGE_INTEGER f {}; QueryPerformanceFrequency(&f); return f; }();
        const double remainMs = freq.QuadPart > 0
            ? (static_cast<double>(target - now.QuadPart) * 1000.0 / static_cast<double>(freq.QuadPart))
            : 0.0;
        if (remainMs > 2.0)
        {
            DWORD sleepMs = static_cast<DWORD>(remainMs - 1.0);
            if (sleepMs == 0) sleepMs = 1;
            Sleep(sleepMs);
        }
        else
        {
            SwitchToThread();
        }
    }
}

static void M3eObserveRealPresentArrivalLocked()
{
    LARGE_INTEGER now {};
    QueryPerformanceCounter(&now);
    if (_m3b2a.m3eLastArrival.QuadPart != 0 && !_m3b2a.m3eBaselineLocked)
    {
        const double dt = M3eQpcDeltaMs(_m3b2a.m3eLastArrival, now);
        // GTA IV's valid gameplay cadence is expected inside this broad range. Ignore load/menu stalls.
        if (dt >= 4.0 && dt <= 40.0)
        {
            if (_m3b2a.m3eBaselineSamples == 0) _m3b2a.m3eBaselineMs = dt;
            else _m3b2a.m3eBaselineMs = _m3b2a.m3eBaselineMs * 0.90 + dt * 0.10;
            ++_m3b2a.m3eBaselineSamples;
            if (_m3b2a.m3eBaselineSamples >= 120)
            {
                _m3b2a.m3eBaselineLocked = true;
                LOG_INFO("M3E: locked pre-pacing real-frame interval at {:.3f} ms after {} samples; midpoint target {:.3f} ms",
                         _m3b2a.m3eBaselineMs, _m3b2a.m3eBaselineSamples, _m3b2a.m3eBaselineMs * 0.5);
            }
        }
    }
    _m3b2a.m3eLastArrival = now;
}
'@
Replace-Exact $ref $helperOld $helperNew '// M3E display-pacing integration marker.' 'M3E pacing helpers'

Replace-Exact $ref `
'    std::lock_guard lock(_m3b2aMutex);
    // Once a copy submit has consumed the game semaphore, a later presentation/marker' `
'    std::lock_guard lock(_m3b2aMutex);
    if (M3ePacingEnabled()) M3eObserveRealPresentArrivalLocked();
    // Once a copy submit has consumed the game semaphore, a later presentation/marker' `
'M3eObserveRealPresentArrivalLocked();' `
'M3E arrival observation'

$presentOld = @'
    VkResult insertedResult = VK_ERROR_UNKNOWN;
    {
        M3dInjectedPresentScope m3dInsertedScope;
        insertedResult = o_QueuePresentKHR(queue, &inserted);
    }

    // gameReady was consumed by the copy submit; never wait it twice.
    gamePresent.pWaitSemaphores = &slot.originalReady;
    *originalResult = o_QueuePresentKHR(queue, &gamePresent);
'@
$presentNew = @'
    LARGE_INTEGER m3eInsertedStart {}, m3eInsertedEnd {}, m3eOriginalStart {}, m3eOriginalEnd {};
    QueryPerformanceCounter(&m3eInsertedStart);
    VkResult insertedResult = VK_ERROR_UNKNOWN;
    {
        M3dInjectedPresentScope m3dInsertedScope;
        insertedResult = o_QueuePresentKHR(queue, &inserted);
    }
    QueryPerformanceCounter(&m3eInsertedEnd);

    // M3E: the old path submitted generated and real presents back-to-back. That gives
    // correct frame order but no midpoint cadence. Once a clean 120-frame baseline is
    // learned, hold the original real present until half of that period has elapsed from
    // the generated-present submission. Time already spent inside vkQueuePresentKHR counts.
    double m3eTargetMs = 0.0;
    double m3eInsertedCallMs = M3eQpcDeltaMs(m3eInsertedStart, m3eInsertedEnd);
    double m3eWaitAppliedMs = 0.0;
    if (M3ePacingEnabled() && _m3b2a.m3eBaselineLocked && M3b2aPresentOk(insertedResult))
    {
        m3eTargetMs = _m3b2a.m3eBaselineMs * 0.5;
        if (m3eTargetMs < 2.0) m3eTargetMs = 2.0;
        if (m3eTargetMs > 20.0) m3eTargetMs = 20.0;
        const LONGLONG targetQpc = m3eInsertedStart.QuadPart + M3eMsToQpc(m3eTargetMs);
        LARGE_INTEGER beforeWait {};
        QueryPerformanceCounter(&beforeWait);
        if (beforeWait.QuadPart < targetQpc)
        {
            M3eWaitUntilQpc(targetQpc);
            LARGE_INTEGER afterWait {};
            QueryPerformanceCounter(&afterWait);
            m3eWaitAppliedMs = M3eQpcDeltaMs(beforeWait, afterWait);
        }
    }

    // gameReady was consumed by the copy submit; never wait it twice.
    gamePresent.pWaitSemaphores = &slot.originalReady;
    QueryPerformanceCounter(&m3eOriginalStart);
    *originalResult = o_QueuePresentKHR(queue, &gamePresent);
    QueryPerformanceCounter(&m3eOriginalEnd);

    if (M3ePacingEnabled() && _m3b2a.m3eBaselineLocked)
    {
        ++_m3b2a.m3ePacedPairs;
        if (_m3b2a.m3ePacedPairs <= 8 || (_m3b2a.m3ePacedPairs % 120) == 0)
        {
            const double submitGapMs = M3eQpcDeltaMs(m3eInsertedStart, m3eOriginalStart);
            const double originalCallMs = M3eQpcDeltaMs(m3eOriginalStart, m3eOriginalEnd);
            LOG_INFO("M3E: paced pair={} serial={} sourceFrame={} baseline={:.3f}ms target={:.3f}ms submitGap={:.3f}ms insertedCall={:.3f}ms wait={:.3f}ms originalCall={:.3f}ms",
                     _m3b2a.m3ePacedPairs, frame.serial, frame.sourceFrame, _m3b2a.m3eBaselineMs,
                     m3eTargetMs, submitGapMs, m3eInsertedCallMs, m3eWaitAppliedMs, originalCallMs);
        }
    }
'@
Replace-Exact $ref $presentOld $presentNew '// M3E: the old path submitted generated and real presents back-to-back.' 'M3E inter-present pacing'

Write-Normalized $optiInc $ref.Value

Write-Host 'Applied M3E half-interval display pacing.'
Write-Host '  - default OFF: GtaivVulkanHalfIntervalPacing=false'
Write-Host '  - learns 120 genuine real-present intervals before pacing'
Write-Host '  - freezes the baseline, then spaces original present at its half-interval midpoint'
Write-Host '  - time spent inside generated vkQueuePresentKHR counts toward the target'
Write-Host '  - M3D present-origin gate + M3C FIFO + M3B-2B native DLSS-G remain unchanged'
