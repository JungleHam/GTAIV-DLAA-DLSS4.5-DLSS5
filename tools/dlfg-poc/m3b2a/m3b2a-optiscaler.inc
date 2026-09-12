// M3B-2A: continuous reusable external-image consumer (NO DLSS-G here).
//
// Feeder publishes ordinary post-NR copied frames from a 3-slot external-image ring.
// This consumer waits on Feeder's producer timeline, copies one publication into an
// extra real GTA IV swapchain image, presents inserted then original, and finally
// signals Feeder's consumer-done timeline from a queue operation ordered AFTER both
// presents. That last signal is what makes D3D12 slot reuse safe.

static void M3aResolveDeviceFunctions(VkDevice device);

static constexpr uint32_t kM3b2aConsumerSlots = 3;

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

using PFN_DLSS5_QueryM3B2AExternalFrame = BOOL(WINAPI*)(Dlss5M3b2aPublishedFrame*);
using PFN_DLSS5_ConsumeM3B2AExternalFrame = BOOL(WINAPI*)(uint64_t);

struct M3b2aConsumerSlot
{
    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;
    VkSemaphore acquireReady = VK_NULL_HANDLE;
    VkSemaphore generatedReady = VK_NULL_HANDLE;
    VkSemaphore originalReady = VK_NULL_HANDLE;
};

struct M3b2aConsumerState
{
    VkDevice device = VK_NULL_HANDLE;
    VkSwapchainKHR swapchain = VK_NULL_HANDLE;
    VkExtent2D extent {};
    VkFormat format = VK_FORMAT_UNDEFINED;
    VkImageUsageFlags usage = 0;
    uint32_t imageCount = 0;
    std::vector<VkImage> images;
    VkCommandPool commandPool = VK_NULL_HANDLE;
    M3b2aConsumerSlot slots[kM3b2aConsumerSlots];
    uint32_t queueFamily = UINT32_MAX;
    uint64_t totalInserted = 0;
    uint64_t consecutiveInserted = 0;
    uint64_t acquireMisses = 0;
    uint64_t lastSerial = 0;
    bool milestoneLogged = false;
};

static M3b2aConsumerState _m3b2a;
static std::mutex _m3b2aMutex;
static PFN_DLSS5_QueryM3B2AExternalFrame _m3b2aQuery = nullptr;
static PFN_DLSS5_ConsumeM3B2AExternalFrame _m3b2aConsume = nullptr;

static bool M3b2aEnabled()
{
    return Config::Instance()->GtaivVulkanContinuousExternalPresent.value_or_default();
}

static bool M3b2aPresentOk(VkResult r)
{
    return r == VK_SUCCESS || r == VK_SUBOPTIMAL_KHR;
}

static void M3b2aDestroyResourcesLocked()
{
    if (_m3b2a.device != VK_NULL_HANDLE)
    {
        if (_m3b2a.commandPool != VK_NULL_HANDLE)
            vkDestroyCommandPool(_m3b2a.device, _m3b2a.commandPool, nullptr);
        for (auto &slot : _m3b2a.slots)
        {
            if (slot.acquireReady != VK_NULL_HANDLE) vkDestroySemaphore(_m3b2a.device, slot.acquireReady, nullptr);
            if (slot.generatedReady != VK_NULL_HANDLE) vkDestroySemaphore(_m3b2a.device, slot.generatedReady, nullptr);
            if (slot.originalReady != VK_NULL_HANDLE) vkDestroySemaphore(_m3b2a.device, slot.originalReady, nullptr);
        }
    }
    _m3b2a = {};
}

static void M3b2aCaptureSwapchain(VkDevice device, const VkSwapchainCreateInfoKHR* createInfo,
                                   VkSwapchainKHR swapchain)
{
    if (!M3b2aEnabled() || createInfo == nullptr || swapchain == VK_NULL_HANDLE) return;
    std::lock_guard lock(_m3b2aMutex);

    if (_m3b2a.device != VK_NULL_HANDLE)
    {
        vkDeviceWaitIdle(_m3b2a.device);
        M3b2aDestroyResourcesLocked();
    }

    M3aResolveDeviceFunctions(device);
    if (_m3aGetSwapchainImagesKHR == nullptr)
    {
        LOG_ERROR("M3B-2A: vkGetSwapchainImagesKHR unavailable; stream not armed");
        return;
    }
    uint32_t count = 0;
    VkResult result = _m3aGetSwapchainImagesKHR(device, swapchain, &count, nullptr);
    if (result != VK_SUCCESS || count == 0)
    {
        LOG_ERROR("M3B-2A: swapchain image count query -> {} count={}", (int) result, count);
        return;
    }
    std::vector<VkImage> images(count);
    result = _m3aGetSwapchainImagesKHR(device, swapchain, &count, images.data());
    if (result != VK_SUCCESS)
    {
        LOG_ERROR("M3B-2A: swapchain image query -> {}", (int) result);
        return;
    }
    images.resize(count);

    _m3b2a.device = device;
    _m3b2a.swapchain = swapchain;
    _m3b2a.extent = createInfo->imageExtent;
    _m3b2a.format = createInfo->imageFormat;
    _m3b2a.usage = createInfo->imageUsage;
    _m3b2a.imageCount = count;
    _m3b2a.images = std::move(images);
    LOG_INFO("M3B-2A: captured swapchain sc={:X} images={} extent={}x{} format={} usage=0x{:X}",
             (UINT64) swapchain, count, _m3b2a.extent.width, _m3b2a.extent.height,
             (int) _m3b2a.format, (uint32_t) _m3b2a.usage);
}

static bool M3b2aCreateResourcesLocked(uint32_t queueFamily)
{
    if (_m3b2a.commandPool != VK_NULL_HANDLE) return _m3b2a.queueFamily == queueFamily;
    if (_m3b2a.device == VK_NULL_HANDLE) return false;

    VkCommandPoolCreateInfo poolInfo { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
    poolInfo.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT | VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    poolInfo.queueFamilyIndex = queueFamily;
    VkResult result = vkCreateCommandPool(_m3b2a.device, &poolInfo, nullptr, &_m3b2a.commandPool);
    if (result != VK_SUCCESS)
    {
        LOG_ERROR("M3B-2A: vkCreateCommandPool -> {}", (int) result);
        return false;
    }

    VkCommandBuffer buffers[kM3b2aConsumerSlots] {};
    VkCommandBufferAllocateInfo allocInfo { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
    allocInfo.commandPool = _m3b2a.commandPool;
    allocInfo.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
    allocInfo.commandBufferCount = kM3b2aConsumerSlots;
    result = vkAllocateCommandBuffers(_m3b2a.device, &allocInfo, buffers);
    if (result != VK_SUCCESS)
    {
        LOG_ERROR("M3B-2A: vkAllocateCommandBuffers -> {}", (int) result);
        M3b2aDestroyResourcesLocked();
        return false;
    }

    VkSemaphoreCreateInfo semInfo { VK_STRUCTURE_TYPE_SEMAPHORE_CREATE_INFO };
    for (uint32_t i = 0; i < kM3b2aConsumerSlots; ++i)
    {
        auto &slot = _m3b2a.slots[i];
        slot.commandBuffer = buffers[i];
        result = vkCreateSemaphore(_m3b2a.device, &semInfo, nullptr, &slot.acquireReady);
        if (result == VK_SUCCESS) result = vkCreateSemaphore(_m3b2a.device, &semInfo, nullptr, &slot.generatedReady);
        if (result == VK_SUCCESS) result = vkCreateSemaphore(_m3b2a.device, &semInfo, nullptr, &slot.originalReady);
        if (result != VK_SUCCESS)
        {
            LOG_ERROR("M3B-2A: slot {} vkCreateSemaphore -> {}", i, (int) result);
            M3b2aDestroyResourcesLocked();
            return false;
        }
    }
    _m3b2a.queueFamily = queueFamily;
    LOG_INFO("M3B-2A: created {} per-slot command/semaphore sets on queue family={}",
             kM3b2aConsumerSlots, queueFamily);
    return true;
}

static bool M3b2aResolveFeederAbi()
{
    if (_m3b2aQuery != nullptr && _m3b2aConsume != nullptr) return true;
    HMODULE feeder = GetModuleHandleW(L"dlss5-feed.addon64");
    if (feeder == nullptr) return false;
    _m3b2aQuery = reinterpret_cast<PFN_DLSS5_QueryM3B2AExternalFrame>(
        GetProcAddress(feeder, "DLSS5_QueryM3B2AExternalFrame"));
    _m3b2aConsume = reinterpret_cast<PFN_DLSS5_ConsumeM3B2AExternalFrame>(
        GetProcAddress(feeder, "DLSS5_ConsumeM3B2AExternalFrame"));
    if (_m3b2aQuery == nullptr || _m3b2aConsume == nullptr)
    {
        _m3b2aQuery = nullptr;
        _m3b2aConsume = nullptr;
        return false;
    }
    LOG_INFO("M3B-2A: resolved Feeder reusable-transport ABI");
    return true;
}

static void M3b2aReleaseAcquiredImage(VkQueue queue, VkSwapchainKHR swapchain, uint32_t imageIndex,
                                      VkSemaphore acquireReady)
{
    VkPresentInfoKHR release { VK_STRUCTURE_TYPE_PRESENT_INFO_KHR };
    release.waitSemaphoreCount = 1;
    release.pWaitSemaphores = &acquireReady;
    release.swapchainCount = 1;
    release.pSwapchains = &swapchain;
    release.pImageIndices = &imageIndex;
    const VkResult r = o_QueuePresentKHR(queue, &release);
    LOG_WARN("M3B-2A: returned acquired image {} after local failure -> {}", imageIndex, (int) r);
}

static VkResult M3b2aRecordAndSubmitCopyLocked(VkQueue queue, uint32_t queueFamily, uint32_t extraIndex,
                                               VkSemaphore gameReady, const Dlss5M3b2aPublishedFrame& frame)
{
    auto &slot = _m3b2a.slots[frame.slotIndex];
    VkResult result = vkResetCommandBuffer(slot.commandBuffer, 0);
    if (result != VK_SUCCESS) return result;
    VkCommandBufferBeginInfo beginInfo { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
    beginInfo.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    result = vkBeginCommandBuffer(slot.commandBuffer, &beginInfo);
    if (result != VK_SUCCESS) return result;

    VkImageMemoryBarrier toTransfer[2] {};
    toTransfer[0].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    toTransfer[0].srcAccessMask = 0;
    toTransfer[0].dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    toTransfer[0].oldLayout = frame.externalRestingLayout;
    toTransfer[0].newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    toTransfer[0].srcQueueFamilyIndex = VK_QUEUE_FAMILY_EXTERNAL;
    toTransfer[0].dstQueueFamilyIndex = queueFamily;
    toTransfer[0].image = frame.image;
    toTransfer[0].subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };

    toTransfer[1].sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
    toTransfer[1].srcAccessMask = 0;
    toTransfer[1].dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    toTransfer[1].oldLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    toTransfer[1].newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    toTransfer[1].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    toTransfer[1].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    toTransfer[1].image = _m3b2a.images[extraIndex];
    toTransfer[1].subresourceRange = { VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1 };

    vkCmdPipelineBarrier(slot.commandBuffer, VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, 0,
                         0, nullptr, 0, nullptr, 2, toTransfer);

    VkImageCopy copy {};
    copy.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copy.srcSubresource.layerCount = 1;
    copy.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
    copy.dstSubresource.layerCount = 1;
    copy.extent = { _m3b2a.extent.width, _m3b2a.extent.height, 1 };
    vkCmdCopyImage(slot.commandBuffer, frame.image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
                   _m3b2a.images[extraIndex], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, 1, &copy);

    VkImageMemoryBarrier restore[2] = { toTransfer[0], toTransfer[1] };
    restore[0].srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
    restore[0].dstAccessMask = 0;
    restore[0].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
    restore[0].newLayout = frame.externalRestingLayout;
    restore[0].srcQueueFamilyIndex = queueFamily;
    restore[0].dstQueueFamilyIndex = VK_QUEUE_FAMILY_EXTERNAL;
    restore[1].srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
    restore[1].dstAccessMask = 0;
    restore[1].oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
    restore[1].newLayout = VK_IMAGE_LAYOUT_PRESENT_SRC_KHR;
    restore[1].srcQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    restore[1].dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
    vkCmdPipelineBarrier(slot.commandBuffer, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_BOTTOM_OF_PIPE_BIT, 0,
                         0, nullptr, 0, nullptr, 2, restore);

    result = vkEndCommandBuffer(slot.commandBuffer);
    if (result != VK_SUCCESS) return result;

    if (_m3aQueueSubmit2 != nullptr)
    {
        const VkSemaphore waits[3] = { gameReady, slot.acquireReady, frame.producerTimeline };
        VkSemaphoreSubmitInfo waitInfo[3] {};
        for (uint32_t i = 0; i < 3; ++i)
        {
            waitInfo[i].sType = VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO;
            waitInfo[i].semaphore = waits[i];
            waitInfo[i].value = i == 2 ? frame.producerReadyValue : 0;
            waitInfo[i].stageMask = VK_PIPELINE_STAGE_2_TRANSFER_BIT;
        }
        const VkSemaphore signals[2] = { slot.generatedReady, slot.originalReady };
        VkSemaphoreSubmitInfo signalInfo[2] {};
        for (uint32_t i = 0; i < 2; ++i)
        {
            signalInfo[i].sType = VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO;
            signalInfo[i].semaphore = signals[i];
            signalInfo[i].stageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
        }
        VkCommandBufferSubmitInfo cmdInfo { VK_STRUCTURE_TYPE_COMMAND_BUFFER_SUBMIT_INFO };
        cmdInfo.commandBuffer = slot.commandBuffer;
        VkSubmitInfo2 submit { VK_STRUCTURE_TYPE_SUBMIT_INFO_2 };
        submit.waitSemaphoreInfoCount = 3;
        submit.pWaitSemaphoreInfos = waitInfo;
        submit.commandBufferInfoCount = 1;
        submit.pCommandBufferInfos = &cmdInfo;
        submit.signalSemaphoreInfoCount = 2;
        submit.pSignalSemaphoreInfos = signalInfo;
        return _m3aQueueSubmit2(queue, 1, &submit, VK_NULL_HANDLE);
    }

    const VkSemaphore waits[3] = { gameReady, slot.acquireReady, frame.producerTimeline };
    const VkPipelineStageFlags stages[3] = {
        VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT
    };
    const uint64_t waitValues[3] = { 0, 0, frame.producerReadyValue };
    const VkSemaphore signals[2] = { slot.generatedReady, slot.originalReady };
    const uint64_t signalValues[2] = { 0, 0 };
    VkTimelineSemaphoreSubmitInfo timeline { VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO };
    timeline.waitSemaphoreValueCount = 3;
    timeline.pWaitSemaphoreValues = waitValues;
    timeline.signalSemaphoreValueCount = 2;
    timeline.pSignalSemaphoreValues = signalValues;
    VkSubmitInfo submit { VK_STRUCTURE_TYPE_SUBMIT_INFO };
    submit.pNext = &timeline;
    submit.waitSemaphoreCount = 3;
    submit.pWaitSemaphores = waits;
    submit.pWaitDstStageMask = stages;
    submit.commandBufferCount = 1;
    submit.pCommandBuffers = &slot.commandBuffer;
    submit.signalSemaphoreCount = 2;
    submit.pSignalSemaphores = signals;
    return _m3aQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE);
}

static VkResult M3b2aSubmitConsumerDoneLocked(VkQueue queue, const Dlss5M3b2aPublishedFrame& frame)
{
    // This signal is intentionally submitted AFTER both vkQueuePresentKHR calls on the
    // same queue. Feeder may recycle the slot only after D3D12 observes this timeline value.
    if (_m3aQueueSubmit2 != nullptr)
    {
        VkSemaphoreSubmitInfo signal { VK_STRUCTURE_TYPE_SEMAPHORE_SUBMIT_INFO };
        signal.semaphore = frame.consumerTimeline;
        signal.value = frame.consumerDoneValue;
        signal.stageMask = VK_PIPELINE_STAGE_2_ALL_COMMANDS_BIT;
        VkSubmitInfo2 submit { VK_STRUCTURE_TYPE_SUBMIT_INFO_2 };
        submit.signalSemaphoreInfoCount = 1;
        submit.pSignalSemaphoreInfos = &signal;
        return _m3aQueueSubmit2(queue, 1, &submit, VK_NULL_HANDLE);
    }

    const uint64_t signalValue = frame.consumerDoneValue;
    VkTimelineSemaphoreSubmitInfo timeline { VK_STRUCTURE_TYPE_TIMELINE_SEMAPHORE_SUBMIT_INFO };
    timeline.signalSemaphoreValueCount = 1;
    timeline.pSignalSemaphoreValues = &signalValue;
    VkSubmitInfo submit { VK_STRUCTURE_TYPE_SUBMIT_INFO };
    submit.pNext = &timeline;
    submit.signalSemaphoreCount = 1;
    submit.pSignalSemaphores = &frame.consumerTimeline;
    return _m3aQueueSubmit(queue, 1, &submit, VK_NULL_HANDLE);
}

// Returns true only after the game's original present has been forwarded. Returning true
// is mandatory after a successful copy submit because that submit consumed gameReady.
static bool M3b2aTryContinuousExternalPresent(VkQueue queue, VkPresentInfoKHR& gamePresent,
                                              bool queueFamilyKnown, uint32_t queueFamily,
                                              VkResult* originalResult)
{
    if (!M3b2aEnabled() || originalResult == nullptr || !queueFamilyKnown) return false;
    if (gamePresent.swapchainCount != 1 || gamePresent.pSwapchains == nullptr ||
        gamePresent.pImageIndices == nullptr || gamePresent.waitSemaphoreCount != 1 ||
        gamePresent.pWaitSemaphores == nullptr || !M3b2aResolveFeederAbi())
        return false;

    Dlss5M3b2aPublishedFrame frame {};
    if (!_m3b2aQuery(&frame)) return false;

    std::lock_guard lock(_m3b2aMutex);
    // Once a copy submit has consumed the game semaphore, a later presentation/marker
    // failure is terminal for that publication. Never retry the same binary semaphores.
    if (frame.serial != 0 && frame.serial == _m3b2a.lastSerial) return false;
    const VkSwapchainKHR swapchain = gamePresent.pSwapchains[0];
    const bool valid = frame.abiVersion == 1 && frame.structSize == sizeof(frame) && frame.ready != 0 &&
                       frame.slotIndex < kM3b2aConsumerSlots && frame.device == _m3b2a.device &&
                       frame.image != VK_NULL_HANDLE && frame.producerTimeline != VK_NULL_HANDLE &&
                       frame.producerReadyValue != 0 && frame.consumerTimeline != VK_NULL_HANDLE &&
                       frame.consumerDoneValue != 0 && frame.format == _m3b2a.format &&
                       frame.width == _m3b2a.extent.width && frame.height == _m3b2a.extent.height &&
                       frame.externalRestingLayout == VK_IMAGE_LAYOUT_GENERAL &&
                       _m3b2a.swapchain == swapchain && _m3b2a.imageCount >= 3 &&
                       (_m3b2a.usage & VK_IMAGE_USAGE_TRANSFER_DST_BIT) != 0 &&
                       _m3aAcquireNextImageKHR != nullptr && _m3aQueueSubmit != nullptr;
    if (!valid)
    {
        LOG_ERROR("M3B-2A: publication/swapchain prerequisites failed serial={} slot={} sc={:X}",
                  frame.serial, frame.slotIndex, (UINT64) swapchain);
        return false;
    }
    if (!M3b2aCreateResourcesLocked(queueFamily))
    {
        LOG_ERROR("M3B-2A: could not create per-slot consumer resources family={}", queueFamily);
        return false;
    }

    auto &slot = _m3b2a.slots[frame.slotIndex];
    uint32_t extraIndex = UINT32_MAX;
    const VkResult acquire = _m3aAcquireNextImageKHR(_m3b2a.device, swapchain, 0, slot.acquireReady,
                                                       VK_NULL_HANDLE, &extraIndex);
    if (!M3b2aPresentOk(acquire))
    {
        ++_m3b2a.acquireMisses;
        _m3b2a.consecutiveInserted = 0;
        if (_m3b2a.acquireMisses <= 8 || (_m3b2a.acquireMisses % 300) == 0)
            LOG_WARN("M3B-2A: no extra image immediately available for serial={} acquire={} misses={}",
                     frame.serial, (int) acquire, _m3b2a.acquireMisses);
        return false; // game semaphore untouched; ordinary present proceeds.
    }
    if (extraIndex >= _m3b2a.images.size())
    {
        LOG_ERROR("M3B-2A: invalid acquired image index={}", extraIndex);
        return false; // impossible driver contract violation; do not submit an invalid index.
    }
    if (extraIndex == gamePresent.pImageIndices[0])
    {
        LOG_ERROR("M3B-2A: acquired image unexpectedly equals original index={}", extraIndex);
        M3b2aReleaseAcquiredImage(queue, swapchain, extraIndex, slot.acquireReady);
        return false;
    }

    const VkResult submit = M3b2aRecordAndSubmitCopyLocked(queue, queueFamily, extraIndex,
                                                            gamePresent.pWaitSemaphores[0], frame);
    if (submit != VK_SUCCESS)
    {
        LOG_ERROR("M3B-2A: copy submit failed serial={} slot={} result={}", frame.serial, frame.slotIndex, (int) submit);
        M3b2aReleaseAcquiredImage(queue, swapchain, extraIndex, slot.acquireReady);
        return false; // unsuccessful submit did not consume gameReady.
    }

    VkPresentInfoKHR inserted { VK_STRUCTURE_TYPE_PRESENT_INFO_KHR };
    inserted.waitSemaphoreCount = 1;
    inserted.pWaitSemaphores = &slot.generatedReady;
    inserted.swapchainCount = 1;
    inserted.pSwapchains = &swapchain;
    inserted.pImageIndices = &extraIndex;
    const VkResult insertedResult = o_QueuePresentKHR(queue, &inserted);

    // gameReady was consumed by the copy submit; never wait it twice.
    gamePresent.pWaitSemaphores = &slot.originalReady;
    *originalResult = o_QueuePresentKHR(queue, &gamePresent);

    if (!M3b2aPresentOk(insertedResult) || !M3b2aPresentOk(*originalResult))
    {
        _m3b2a.lastSerial = frame.serial;
        _m3b2a.consecutiveInserted = 0;
        LOG_ERROR("M3B-2A: present failure serial={} inserted={} original={}; consumer-done withheld for safety",
                  frame.serial, (int) insertedResult, (int) *originalResult);
        return true;
    }

    const VkResult doneSubmit = M3b2aSubmitConsumerDoneLocked(queue, frame);
    if (doneSubmit != VK_SUCCESS)
    {
        _m3b2a.lastSerial = frame.serial;
        _m3b2a.consecutiveInserted = 0;
        LOG_ERROR("M3B-2A: post-present consumer-done submit failed serial={} value={} result={}; slot reuse withheld",
                  frame.serial, frame.consumerDoneValue, (int) doneSubmit);
        return true;
    }

    // The done marker is now queue-ordered. Mark this serial terminal before the CPU
    // acknowledgement so an unexpected ABI failure cannot cause a duplicate timeline signal.
    _m3b2a.lastSerial = frame.serial;
    if (!_m3b2aConsume(frame.serial))
    {
        _m3b2a.consecutiveInserted = 0;
        LOG_ERROR("M3B-2A: Feeder rejected consume acknowledgement serial={}; slot reuse withheld", frame.serial);
        return true;
    }

    ++_m3b2a.totalInserted;
    ++_m3b2a.consecutiveInserted;
    if (_m3b2a.totalInserted <= 12 || (_m3b2a.totalInserted % 60) == 0)
        LOG_INFO("M3B-2A: inserted serial={} slot={} sourceFrame={} producerReady={} consumerDone={} total={} consecutive={}",
                 frame.serial, frame.slotIndex, frame.sourceFrame, frame.producerReadyValue, frame.consumerDoneValue,
                 _m3b2a.totalInserted, _m3b2a.consecutiveInserted);

    if (!_m3b2a.milestoneLogged && _m3b2a.consecutiveInserted >= 300)
    {
        _m3b2a.milestoneLogged = true;
        LOG_INFO("MILESTONE M3B-2A PASSED: 300 consecutive reusable external-image insertions completed with GPU-confirmed consumer return");
    }
    return true;
}
