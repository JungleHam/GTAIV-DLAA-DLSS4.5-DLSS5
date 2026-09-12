// M3B-2A: continuous reusable external-image transport (NO DLSS-G here).
//
// This layer deliberately keeps the proven M3B-1/M3B-1A one-shot path intact.
// It copies the normal post-NR Feeder output into a three-slot D3D12/Vulkan ring,
// publishes one slot at a time to OptiScaler, and will not reuse a slot until the
// Vulkan consumer has signalled the shared consumer-done timeline back to D3D12.

static void Barrier(ID3D12Resource *res, D3D12_RESOURCE_STATES from, D3D12_RESOURCE_STATES to);
static const char *FormatName(DXGI_FORMAT f);

static constexpr uint32_t kM3b2aSlotCount = 3;

struct Dlss5M3b2aPublishedFrame
{
    uint32_t abiVersion;
    uint32_t structSize;
    uint64_t serial;
    uint32_t ready;
    uint32_t slotIndex;
    VkDevice device;
    VkImage image;
    VkFormat format;
    uint32_t width;
    uint32_t height;
    VkSemaphore producerTimeline;
    uint64_t producerReadyValue;
    VkSemaphore consumerTimeline;
    uint64_t consumerDoneValue;
    VkImageLayout externalRestingLayout;
    uint64_t sourceFrame;
};

struct M3b2aFeedSlot
{
    ID3D12Resource *tex12;
    HANDLE shared;
    VkImage vkImage;
    VkDeviceMemory vkMemory;
    bool vkReleased;
    uint64_t consumerDoneValue;
    uint64_t sourceFrame;
    uint64_t serial;
};

struct M3b2aFeedState
{
    M3b2aFeedSlot slots[kM3b2aSlotCount];
    ID3D12Fence *consumerDoneFence12;
    HANDLE consumerDoneShared;
    VkSemaphore consumerDoneVk;
    uint64_t serial;
    uint32_t nextSlot;
    uint64_t produced;
    uint64_t backpressureSkips;
    uint64_t lastBackpressureLogFrame;
};

static M3b2aFeedState g_m3b2a = {};
static SRWLOCK g_m3b2aPublicationLock = SRWLOCK_INIT;
static Dlss5M3b2aPublishedFrame g_m3b2aPublication = {};

static bool M3b2aEnabled()
{
    return g_cfg.dlfg_m3b2a_stream != 0;
}

static bool M3b2aHasConflictingExperiment()
{
    return g_cfg.dlfg_m3b1a_publish != 0 || g_cfg.dlfg_m3b1_present != 0 ||
           g_cfg.dlfg_m2b_eval != 0 || g_cfg.dlfg_m2c_prearm_create != 0;
}

static bool M3b2aPublicationPending()
{
    AcquireSRWLockShared(&g_m3b2aPublicationLock);
    const bool pending = g_m3b2aPublication.ready != 0;
    ReleaseSRWLockShared(&g_m3b2aPublicationLock);
    return pending;
}

extern "C" __declspec(dllexport) BOOL WINAPI DLSS5_QueryM3B2AExternalFrame(Dlss5M3b2aPublishedFrame *out)
{
    if (out == nullptr) return FALSE;
    AcquireSRWLockShared(&g_m3b2aPublicationLock);
    *out = g_m3b2aPublication;
    const BOOL ready = out->abiVersion == 1 && out->structSize == sizeof(*out) && out->ready != 0;
    ReleaseSRWLockShared(&g_m3b2aPublicationLock);
    return ready;
}

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

static void M3b2aWithdrawPublication()
{
    AcquireSRWLockExclusive(&g_m3b2aPublicationLock);
    g_m3b2aPublication = {};
    ReleaseSRWLockExclusive(&g_m3b2aPublicationLock);
}

static void M3b2aRelease()
{
    M3b2aWithdrawPublication();

    if (g.vk.ok)
    {
        if (g_m3b2a.consumerDoneVk != VK_NULL_HANDLE)
        {
            g.vk.DestroySemaphore(g.vk.dev, g_m3b2a.consumerDoneVk, nullptr);
            g_m3b2a.consumerDoneVk = VK_NULL_HANDLE;
        }
        for (uint32_t i = 0; i < kM3b2aSlotCount; ++i)
        {
            auto &slot = g_m3b2a.slots[i];
            if (slot.vkImage != VK_NULL_HANDLE)
            {
                g.vk.DestroyImage(g.vk.dev, slot.vkImage, nullptr);
                slot.vkImage = VK_NULL_HANDLE;
            }
            if (slot.vkMemory != VK_NULL_HANDLE)
            {
                g.vk.FreeMemory(g.vk.dev, slot.vkMemory, nullptr);
                slot.vkMemory = VK_NULL_HANDLE;
            }
        }
    }

    for (uint32_t i = 0; i < kM3b2aSlotCount; ++i)
    {
        auto &slot = g_m3b2a.slots[i];
        if (slot.shared != nullptr) { CloseHandle(slot.shared); slot.shared = nullptr; }
        if (slot.tex12 != nullptr) { slot.tex12->Release(); slot.tex12 = nullptr; }
    }
    if (g_m3b2a.consumerDoneShared != nullptr)
    {
        CloseHandle(g_m3b2a.consumerDoneShared);
        g_m3b2a.consumerDoneShared = nullptr;
    }
    if (g_m3b2a.consumerDoneFence12 != nullptr)
    {
        g_m3b2a.consumerDoneFence12->Release();
        g_m3b2a.consumerDoneFence12 = nullptr;
    }
    g_m3b2a = {};
}

static bool M3b2aCreateResources(UINT w, UINT h)
{
    if (!M3b2aEnabled()) return true;
    if (M3b2aHasConflictingExperiment())
    {
        Log("[feed] M3B-2A: disabled because another DLFG milestone flag is enabled; use M3B-2A alone");
        return true;
    }
    if (w != 2560 || h != 1440 || g.output_fmt != DXGI_FORMAT_B8G8R8A8_UNORM)
    {
        Log("[feed] M3B-2A: disabled for this build: requires 2560x1440 B8G8R8A8_UNORM output, got %ux%u %s",
            w, h, FormatName(g.output_fmt));
        return true;
    }
    if (!g.vk.ok || g.dev12 == nullptr)
    {
        Log("[feed] M3B-2A: Vulkan/D3D12 interop session unavailable");
        return false;
    }

    HRESULT hr = g.dev12->CreateFence(0, D3D12_FENCE_FLAG_SHARED, __uuidof(ID3D12Fence),
                                      reinterpret_cast<void **>(&g_m3b2a.consumerDoneFence12));
    if (SUCCEEDED(hr))
        hr = g.dev12->CreateSharedHandle(g_m3b2a.consumerDoneFence12, nullptr, GENERIC_ALL, nullptr,
                                         &g_m3b2a.consumerDoneShared);
    if (FAILED(hr))
    {
        Log("[feed] M3B-2A: consumer-done shared fence creation failed 0x%08X", hr);
        M3b2aRelease();
        return false;
    }
    g_m3b2a.consumerDoneVk = FeedVkImportFence(&g.vk, g_m3b2a.consumerDoneShared);
    if (g_m3b2a.consumerDoneVk == VK_NULL_HANDLE)
    {
        Log("[feed] M3B-2A: consumer-done fence Vulkan import failed");
        M3b2aRelease();
        return false;
    }

    D3D12_HEAP_PROPERTIES hp = {};
    hp.Type = D3D12_HEAP_TYPE_DEFAULT;
    D3D12_RESOURCE_DESC rd = {};
    rd.Dimension = D3D12_RESOURCE_DIMENSION_TEXTURE2D;
    rd.Width = w;
    rd.Height = h;
    rd.DepthOrArraySize = 1;
    rd.MipLevels = 1;
    rd.Format = DXGI_FORMAT_B8G8R8A8_UNORM;
    rd.SampleDesc.Count = 1;
    rd.Layout = D3D12_TEXTURE_LAYOUT_UNKNOWN;
    rd.Flags = D3D12_RESOURCE_FLAG_ALLOW_SIMULTANEOUS_ACCESS;
    const D3D12_RESOURCE_ALLOCATION_INFO ai = g.dev12->GetResourceAllocationInfo(0, 1, &rd);

    for (uint32_t i = 0; i < kM3b2aSlotCount; ++i)
    {
        auto &slot = g_m3b2a.slots[i];
        hr = g.dev12->CreateCommittedResource(&hp, D3D12_HEAP_FLAG_SHARED, &rd,
            D3D12_RESOURCE_STATE_COMMON, nullptr, __uuidof(ID3D12Resource),
            reinterpret_cast<void **>(&slot.tex12));
        if (SUCCEEDED(hr))
            hr = g.dev12->CreateSharedHandle(slot.tex12, nullptr, GENERIC_ALL, nullptr, &slot.shared);
        if (FAILED(hr) || !FeedVkImportImage(&g.vk, slot.shared, w, h, VK_FORMAT_B8G8R8A8_UNORM, false,
                                              &slot.vkImage, &slot.vkMemory, ai.SizeInBytes))
        {
            Log("[feed] M3B-2A: slot %u shared image creation/import failed (hr=0x%08X)", i, hr);
            M3b2aRelease();
            return false;
        }
    }

    Log("[feed] M3B-2A: created %u reusable external-image slots + consumer-done timeline=%p",
        kM3b2aSlotCount, reinterpret_cast<void *>(g_m3b2a.consumerDoneVk));
    return true;
}

static void M3b2aPrepareVulkanRelease(VkCommandBuffer cb, uint32_t gfxFamily)
{
    if (!M3b2aEnabled() || M3b2aHasConflictingExperiment()) return;
    for (uint32_t i = 0; i < kM3b2aSlotCount; ++i)
    {
        auto &slot = g_m3b2a.slots[i];
        if (slot.vkImage == VK_NULL_HANDLE || slot.vkReleased) continue;
        FeedVkBarrier(&g.vk, cb, slot.vkImage, VK_IMAGE_LAYOUT_UNDEFINED, VK_IMAGE_LAYOUT_GENERAL);
        FeedVkExternalTransfer(&g.vk, cb, slot.vkImage, gfxFamily, true /* release to D3D12 */);
        slot.vkReleased = true;
        Log("[feed] M3B-2A: slot %u initialized GENERAL and released to D3D12", i);
    }
}

static int M3b2aFindFreeSlot(UINT64 frame)
{
    if (g_m3b2a.consumerDoneFence12 == nullptr) return -1;
    const UINT64 completed = g_m3b2a.consumerDoneFence12->GetCompletedValue();
    if (completed == UINT64_MAX)
    {
        Log("[feed] M3B-2A: consumer-done fence reports device removal");
        return -1;
    }

    for (uint32_t n = 0; n < kM3b2aSlotCount; ++n)
    {
        const uint32_t i = (g_m3b2a.nextSlot + n) % kM3b2aSlotCount;
        auto &slot = g_m3b2a.slots[i];
        if (slot.tex12 == nullptr || !slot.vkReleased) continue;
        if (slot.consumerDoneValue == 0 || completed >= slot.consumerDoneValue)
        {
            g_m3b2a.nextSlot = (i + 1) % kM3b2aSlotCount;
            return static_cast<int>(i);
        }
    }

    ++g_m3b2a.backpressureSkips;
    if (g_m3b2a.lastBackpressureLogFrame == 0 || frame - g_m3b2a.lastBackpressureLogFrame >= 300)
    {
        g_m3b2a.lastBackpressureLogFrame = frame;
        Log("[feed] M3B-2A: backpressure: all %u slots still owned/in-flight (consumerDone=%llu, skips=%llu)",
            kM3b2aSlotCount, static_cast<unsigned long long>(completed),
            static_cast<unsigned long long>(g_m3b2a.backpressureSkips));
    }
    return -1;
}

// Record only the producer copy. Returns the slot index whose bytes will be ordered by
// the existing fence12_out signal, or -1 when no M3B-2A publication should be made.
static int M3b2aRecordCopy(UINT64 frame)
{
    if (!M3b2aEnabled() || M3b2aHasConflictingExperiment() || M3b2aPublicationPending()) return -1;
    const int slotIndex = M3b2aFindFreeSlot(frame);
    if (slotIndex < 0) return -1;

    auto &slot = g_m3b2a.slots[slotIndex];
    if (slot.consumerDoneValue != 0)
    {
        // The CPU completion check above keeps this non-blocking. The queue wait is still
        // important: it establishes the Vulkan -> D3D12 GPU dependency before reuse.
        const HRESULT waitHr = g.queue->Wait(g_m3b2a.consumerDoneFence12, slot.consumerDoneValue);
        if (FAILED(waitHr))
        {
            Log("[feed] M3B-2A: queue Wait(consumerDone=%llu) failed 0x%08X; slot %d withheld",
                static_cast<unsigned long long>(slot.consumerDoneValue), waitHr, slotIndex);
            return -1;
        }
    }

    Barrier(g.tex12[SLOT_OUTPUT], D3D12_RESOURCE_STATE_UNORDERED_ACCESS, D3D12_RESOURCE_STATE_COPY_SOURCE);
    Barrier(slot.tex12, D3D12_RESOURCE_STATE_COMMON, D3D12_RESOURCE_STATE_COPY_DEST);
    g.list->CopyResource(slot.tex12, g.tex12[SLOT_OUTPUT]);
    Barrier(slot.tex12, D3D12_RESOURCE_STATE_COPY_DEST, D3D12_RESOURCE_STATE_COMMON);
    Barrier(g.tex12[SLOT_OUTPUT], D3D12_RESOURCE_STATE_COPY_SOURCE, D3D12_RESOURCE_STATE_UNORDERED_ACCESS);
    slot.sourceFrame = frame;
    Log("[feed] M3B-2A: producer copied sourceFrame=%llu into slot=%d",
        static_cast<unsigned long long>(frame), slotIndex);
    return slotIndex;
}

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
