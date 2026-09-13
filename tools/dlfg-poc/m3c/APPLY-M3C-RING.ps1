$ErrorActionPreference = 'Stop'

$m2b = Join-Path $PSScriptRoot '..\m2b'
$ring = Join-Path $m2b 'feeder-src\src\m3b2a-feed.inc'
if (!(Test-Path $ring)) { throw "Missing generated ring include: $ring. Run BUILD-M3B2B.bat first." }

$ringText = ([IO.File]::ReadAllText($ring)).Replace("`r`n", "`n")

if ($ringText.Contains('// M3C publication queue integration marker')) {
    Write-Host 'M3C publication ring patch is already applied.'
    exit 0
}

function Replace-RingExact([string]$old, [string]$new, [string]$name) {
    $old = $old.Replace("`r`n", "`n")
    $new = $new.Replace("`r`n", "`n")
    if (!$script:ringText.Contains($old)) { throw "M3C ring anchor not found: $name" }
    $script:ringText = $script:ringText.Replace($old, $new)
}

$oldGlobals = @'
static M3b2aFeedState g_m3b2a = {};
static SRWLOCK g_m3b2aPublicationLock = SRWLOCK_INIT;
static Dlss5M3b2aPublishedFrame g_m3b2aPublication = {};
'@
$newGlobals = @'
static M3b2aFeedState g_m3b2a = {};
static SRWLOCK g_m3b2aPublicationLock = SRWLOCK_INIT;
static Dlss5M3b2aPublishedFrame g_m3b2aPublication = {};

// M3C publication queue integration marker
static constexpr uint32_t kM3cPublicationCapacity = kM3b2aSlotCount;
struct M3cPublicationQueueState
{
    Dlss5M3b2aPublishedFrame entries[kM3cPublicationCapacity];
    uint32_t head;
    uint32_t count;
    uint64_t published;
    uint64_t fullSkips;
    uint64_t lastSourceFrame;
    uint64_t consecutiveSourceStepOne;
    bool milestoneLogged;
};
static M3cPublicationQueueState g_m3cPublicationQueue = {};

static bool M3cQueueEnabled()
{
    return g_cfg.dlfg_m3c_queue != 0 && g_cfg.dlfg_m3b2b_native != 0;
}
'@
Replace-RingExact $oldGlobals $newGlobals 'globals'

$oldPending = @'
static bool M3b2aPublicationPending()
{
    AcquireSRWLockShared(&g_m3b2aPublicationLock);
    const bool pending = g_m3b2aPublication.ready != 0;
    ReleaseSRWLockShared(&g_m3b2aPublicationLock);
    return pending;
}
'@
$newPending = @'
static bool M3b2aPublicationPending()
{
    AcquireSRWLockShared(&g_m3b2aPublicationLock);
    // Legacy M3B-2A/M3B-2B semantics: one publication blocks the producer.
    // M3C semantics: block only when all three publication entries are occupied.
    const bool pending = M3cQueueEnabled()
        ? (g_m3cPublicationQueue.count >= kM3cPublicationCapacity)
        : (g_m3b2aPublication.ready != 0);
    ReleaseSRWLockShared(&g_m3b2aPublicationLock);
    return pending;
}
'@
Replace-RingExact $oldPending $newPending 'publication-pending'

$oldQuery = @'
extern "C" __declspec(dllexport) BOOL WINAPI DLSS5_QueryM3B2AExternalFrame(Dlss5M3b2aPublishedFrame *out)
{
    if (out == nullptr) return FALSE;
    AcquireSRWLockShared(&g_m3b2aPublicationLock);
    *out = g_m3b2aPublication;
    const BOOL ready = out->abiVersion == 1 && out->structSize == sizeof(*out) && out->ready != 0;
    ReleaseSRWLockShared(&g_m3b2aPublicationLock);
    return ready;
}
'@
$newQuery = @'
extern "C" __declspec(dllexport) BOOL WINAPI DLSS5_QueryM3B2AExternalFrame(Dlss5M3b2aPublishedFrame *out)
{
    if (out == nullptr) return FALSE;
    AcquireSRWLockShared(&g_m3b2aPublicationLock);
    if (M3cQueueEnabled())
    {
        if (g_m3cPublicationQueue.count != 0)
            *out = g_m3cPublicationQueue.entries[g_m3cPublicationQueue.head];
        else
            *out = {};
    }
    else
    {
        *out = g_m3b2aPublication;
    }
    const BOOL ready = out->abiVersion == 1 && out->structSize == sizeof(*out) && out->ready != 0;
    ReleaseSRWLockShared(&g_m3b2aPublicationLock);
    return ready;
}
'@
Replace-RingExact $oldQuery $newQuery 'query ABI'

$oldConsume = @'
extern "C" __declspec(dllexport) BOOL WINAPI DLSS5_ConsumeM3B2AExternalFrame(uint64_t serial)
{
    AcquireSRWLockExclusive(&g_m3b2aPublicationLock);
    const BOOL matched = g_m3b2aPublication.ready != 0 && g_m3b2aPublication.serial == serial;
    if (matched) g_m3b2aPublication.ready = 0;
    ReleaseSRWLockExclusive(&g_m3b2aPublicationLock);
    if (matched)
        Log("[feed] M3B-2A consumer acknowledged serial=%llu", static_cast<unsigned long long>(serial));
    return matched;
}
'@
$newConsume = @'
extern "C" __declspec(dllexport) BOOL WINAPI DLSS5_ConsumeM3B2AExternalFrame(uint64_t serial)
{
    BOOL matched = FALSE;
    uint32_t depthAfter = 0;
    AcquireSRWLockExclusive(&g_m3b2aPublicationLock);
    if (M3cQueueEnabled())
    {
        if (g_m3cPublicationQueue.count != 0)
        {
            auto &front = g_m3cPublicationQueue.entries[g_m3cPublicationQueue.head];
            matched = front.ready != 0 && front.serial == serial;
            if (matched)
            {
                front = {};
                g_m3cPublicationQueue.head = (g_m3cPublicationQueue.head + 1) % kM3cPublicationCapacity;
                --g_m3cPublicationQueue.count;
            }
        }
        depthAfter = g_m3cPublicationQueue.count;
    }
    else
    {
        matched = g_m3b2aPublication.ready != 0 && g_m3b2aPublication.serial == serial;
        if (matched) g_m3b2aPublication.ready = 0;
    }
    ReleaseSRWLockExclusive(&g_m3b2aPublicationLock);
    if (matched)
    {
        Log("[feed] M3B-2A consumer acknowledged serial=%llu", static_cast<unsigned long long>(serial));
        if (M3cQueueEnabled() && (serial <= 12 || (serial % 60) == 0))
            Log("[feed] M3C: consumer popped serial=%llu queueDepth=%u",
                static_cast<unsigned long long>(serial), depthAfter);
    }
    return matched;
}
'@
Replace-RingExact $oldConsume $newConsume 'consume ABI'

$oldWithdraw = @'
static void M3b2aWithdrawPublication()
{
    AcquireSRWLockExclusive(&g_m3b2aPublicationLock);
    g_m3b2aPublication = {};
    ReleaseSRWLockExclusive(&g_m3b2aPublicationLock);
}
'@
$newWithdraw = @'
static void M3b2aWithdrawPublication()
{
    AcquireSRWLockExclusive(&g_m3b2aPublicationLock);
    g_m3b2aPublication = {};
    g_m3cPublicationQueue = {};
    ReleaseSRWLockExclusive(&g_m3b2aPublicationLock);
}
'@
Replace-RingExact $oldWithdraw $newWithdraw 'withdraw'

$oldPublish = @'
static uint64_t M3b2aPublish(uint32_t slotIndex, UINT64 sourceFrame, UINT64 producerReadyValue)
{
    if (slotIndex >= kM3b2aSlotCount) return 0;
    auto &slot = g_m3b2a.slots[slotIndex];
    const uint64_t serial = ++g_m3b2a.serial;

    Dlss5M3b2aPublishedFrame p = {};
    p.abiVersion = 1;
    p.structSize = sizeof(p);
    p.serial = serial;
    p.ready = 1;
    p.slotIndex = slotIndex;
    p.device = g.vk.dev;
    p.image = slot.vkImage;
    p.format = VK_FORMAT_B8G8R8A8_UNORM;
    p.width = g.width;
    p.height = g.height;
    p.producerTimeline = g.vk_sem_out;
    p.producerReadyValue = producerReadyValue;
    p.consumerTimeline = g_m3b2a.consumerDoneVk;
    p.consumerDoneValue = serial;
    p.externalRestingLayout = VK_IMAGE_LAYOUT_GENERAL;
    p.sourceFrame = sourceFrame;

    slot.consumerDoneValue = serial;
    slot.serial = serial;
    AcquireSRWLockExclusive(&g_m3b2aPublicationLock);
    g_m3b2aPublication = p;
    ReleaseSRWLockExclusive(&g_m3b2aPublicationLock);
    ++g_m3b2a.produced;

    Log("[feed] M3B-2A: published serial=%llu slot=%u sourceFrame=%llu producerReady=%llu consumerDone=%llu",
        static_cast<unsigned long long>(serial), slotIndex,
        static_cast<unsigned long long>(sourceFrame),
        static_cast<unsigned long long>(producerReadyValue),
        static_cast<unsigned long long>(p.consumerDoneValue));
    return serial;
}
'@
$newPublish = @'
static uint64_t M3b2aPublish(uint32_t slotIndex, UINT64 sourceFrame, UINT64 producerReadyValue)
{
    if (slotIndex >= kM3b2aSlotCount) return 0;
    auto &slot = g_m3b2a.slots[slotIndex];
    uint64_t serial = 0;
    uint32_t queueDepth = 0;
    uint64_t sourceStepRun = 0;
    bool m3cMilestoneNow = false;

    AcquireSRWLockExclusive(&g_m3b2aPublicationLock);
    if (M3cQueueEnabled() && g_m3cPublicationQueue.count >= kM3cPublicationCapacity)
    {
        ++g_m3cPublicationQueue.fullSkips;
        const uint64_t skips = g_m3cPublicationQueue.fullSkips;
        ReleaseSRWLockExclusive(&g_m3b2aPublicationLock);
        if (skips <= 8 || (skips % 300) == 0)
            Log("[feed] M3C: publication FIFO full; generated frame %llu not queued (skips=%llu)",
                static_cast<unsigned long long>(sourceFrame), static_cast<unsigned long long>(skips));
        return 0;
    }

    serial = ++g_m3b2a.serial;
    Dlss5M3b2aPublishedFrame p = {};
    p.abiVersion = 1;
    p.structSize = sizeof(p);
    p.serial = serial;
    p.ready = 1;
    p.slotIndex = slotIndex;
    p.device = g.vk.dev;
    p.image = slot.vkImage;
    p.format = VK_FORMAT_B8G8R8A8_UNORM;
    p.width = g.width;
    p.height = g.height;
    p.producerTimeline = g.vk_sem_out;
    p.producerReadyValue = producerReadyValue;
    p.consumerTimeline = g_m3b2a.consumerDoneVk;
    p.consumerDoneValue = serial;
    p.externalRestingLayout = VK_IMAGE_LAYOUT_GENERAL;
    p.sourceFrame = sourceFrame;

    slot.consumerDoneValue = serial;
    slot.serial = serial;

    if (M3cQueueEnabled())
    {
        const uint32_t tail = (g_m3cPublicationQueue.head + g_m3cPublicationQueue.count) % kM3cPublicationCapacity;
        g_m3cPublicationQueue.entries[tail] = p;
        ++g_m3cPublicationQueue.count;
        ++g_m3cPublicationQueue.published;
        queueDepth = g_m3cPublicationQueue.count;

        if (g_m3cPublicationQueue.lastSourceFrame != 0 &&
            sourceFrame == g_m3cPublicationQueue.lastSourceFrame + 1)
            ++g_m3cPublicationQueue.consecutiveSourceStepOne;
        else
            g_m3cPublicationQueue.consecutiveSourceStepOne = 1;
        g_m3cPublicationQueue.lastSourceFrame = sourceFrame;
        sourceStepRun = g_m3cPublicationQueue.consecutiveSourceStepOne;
        if (!g_m3cPublicationQueue.milestoneLogged && sourceStepRun >= 300)
        {
            g_m3cPublicationQueue.milestoneLogged = true;
            m3cMilestoneNow = true;
        }
    }
    else
    {
        g_m3b2aPublication = p;
    }
    ReleaseSRWLockExclusive(&g_m3b2aPublicationLock);
    ++g_m3b2a.produced;

    Log("[feed] M3B-2A: published serial=%llu slot=%u sourceFrame=%llu producerReady=%llu consumerDone=%llu",
        static_cast<unsigned long long>(serial), slotIndex,
        static_cast<unsigned long long>(sourceFrame),
        static_cast<unsigned long long>(producerReadyValue),
        static_cast<unsigned long long>(serial));
    if (M3cQueueEnabled() && (serial <= 12 || (serial % 60) == 0))
        Log("[feed] M3C: queued serial=%llu queueDepth=%u sourceFrame=%llu consecutiveSourceStep1=%llu",
            static_cast<unsigned long long>(serial), queueDepth,
            static_cast<unsigned long long>(sourceFrame), static_cast<unsigned long long>(sourceStepRun));
    if (m3cMilestoneNow)
        Log("[feed] MILESTONE M3C PRODUCER PASSED: 300 consecutive native publications with sourceFrame delta=1 through the three-entry FIFO");
    return serial;
}
'@
Replace-RingExact $oldPublish $newPublish 'publish'

[IO.File]::WriteAllText($ring, $ringText, [Text.UTF8Encoding]::new($false))
Write-Host 'Applied M3C publication FIFO ring patch (newline-safe).'
