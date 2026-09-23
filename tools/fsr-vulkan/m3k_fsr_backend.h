#pragma once

// Minimal FidelityFX FSR 3.1.x Vulkan backend used by the GTA IV reconstruction path.
// This wrapper owns only FidelityFX state. It does NOT own the game's VkDevice,
// command buffers, or the four external images passed to Dispatch().
//
// Lifecycle rule: Shutdown() must be called only after work using the context is no
// longer in flight. The GTA IV integration layer is responsible for applying the
// project's existing deferred-destroy / runtime-churn quarantine before calling it.

#include <cstdint>
#include <cstdlib>
#include <cstring>

#include <FidelityFX/host/ffx_fsr3upscaler.h>
#include <FidelityFX/host/backends/vk/ffx_vk.h>

struct M3kFsrImage
{
    VkImage image = VK_NULL_HANDLE;
    VkFormat format = VK_FORMAT_UNDEFINED;
    uint32_t width = 0;
    uint32_t height = 0;
    bool storage = false;
};

struct M3kFsrDispatchInputs
{
    VkCommandBuffer commandBuffer = VK_NULL_HANDLE;

    M3kFsrImage color;
    M3kFsrImage depth;
    M3kFsrImage motionVectors;
    M3kFsrImage output;

    uint32_t renderWidth = 0;
    uint32_t renderHeight = 0;
    uint32_t outputWidth = 0;
    uint32_t outputHeight = 0;

    float jitterX = 0.0f;
    float jitterY = 0.0f;
    float motionVectorScaleX = 1.0f;
    float motionVectorScaleY = 1.0f;

    float frameTimeMs = 16.6667f;
    float preExposure = 1.0f;

    // AMD FSR RCAS. This is deliberately independent from the NVIDIA/ReShade
    // sharpening control used by the DLSS backend.
    bool enableSharpening = false;
    float sharpness = 0.0f;

    // These are intentionally supplied by the integration layer rather than guessed
    // here. FSR's depth reconstruction needs the game's actual projection convention.
    float cameraNear = 0.1f;
    float cameraFar = 1000.0f;
    float cameraFovAngleVertical = 1.0f;
    float viewSpaceToMetersFactor = 1.0f;

    bool reset = false;
};

class M3kFsrBackend
{
public:
    M3kFsrBackend() = default;
    M3kFsrBackend(const M3kFsrBackend&) = delete;
    M3kFsrBackend& operator=(const M3kFsrBackend&) = delete;

    bool Init(
        VkDevice device,
        VkPhysicalDevice physicalDevice,
        PFN_vkGetDeviceProcAddr getDeviceProcAddr,
        uint32_t maxRenderWidth,
        uint32_t maxRenderHeight,
        uint32_t maxOutputWidth,
        uint32_t maxOutputHeight,
        bool depthInverted,
        bool depthInfinite,
        FfxFsr3UpscalerMessage messageCallback = nullptr)
    {
        if (ready_)
            return Matches(device, physicalDevice, maxRenderWidth, maxRenderHeight, maxOutputWidth, maxOutputHeight,
                           depthInverted, depthInfinite);

        if (device == VK_NULL_HANDLE || physicalDevice == VK_NULL_HANDLE || getDeviceProcAddr == nullptr ||
            maxRenderWidth == 0 || maxRenderHeight == 0 || maxOutputWidth == 0 || maxOutputHeight == 0)
            return false;

        device_ = device;
        physicalDevice_ = physicalDevice;
        maxRenderWidth_ = maxRenderWidth;
        maxRenderHeight_ = maxRenderHeight;
        maxOutputWidth_ = maxOutputWidth;
        maxOutputHeight_ = maxOutputHeight;
        depthInverted_ = depthInverted;
        depthInfinite_ = depthInfinite;

        scratchSize_ = ffxGetScratchMemorySizeVK(physicalDevice_, FFX_FSR3UPSCALER_CONTEXT_COUNT);
        if (scratchSize_ == 0)
        {
            ClearIdentity();
            return false;
        }

        scratch_ = std::calloc(1, scratchSize_);
        if (scratch_ == nullptr)
        {
            ClearIdentity();
            return false;
        }

        VkDeviceContext vkDeviceContext = {};
        vkDeviceContext.vkDevice = device_;
        vkDeviceContext.vkPhysicalDevice = physicalDevice_;
        vkDeviceContext.vkDeviceProcAddr = getDeviceProcAddr;

        const FfxDevice ffxDevice = ffxGetDeviceVK(&vkDeviceContext);
        if (ffxGetInterfaceVK(&backendInterface_, ffxDevice, scratch_, scratchSize_,
                              FFX_FSR3UPSCALER_CONTEXT_COUNT) != FFX_OK)
        {
            ReleaseScratch();
            ClearIdentity();
            return false;
        }

        FfxFsr3UpscalerContextDescription description = {};
        description.backendInterface = backendInterface_;
        description.maxRenderSize = { maxRenderWidth_, maxRenderHeight_ };
        description.maxUpscaleSize = { maxOutputWidth_, maxOutputHeight_ };
        description.flags = FFX_FSR3UPSCALER_ENABLE_AUTO_EXPOSURE |
                            FFX_FSR3UPSCALER_ENABLE_DEBUG_CHECKING;
        if (depthInverted_)
            description.flags |= FFX_FSR3UPSCALER_ENABLE_DEPTH_INVERTED;
        if (depthInfinite_)
            description.flags |= FFX_FSR3UPSCALER_ENABLE_DEPTH_INFINITE;
        description.fpMessage = messageCallback;

        if (ffxFsr3UpscalerContextCreate(&context_, &description) != FFX_OK)
        {
            ReleaseScratch();
            std::memset(&backendInterface_, 0, sizeof(backendInterface_));
            std::memset(&context_, 0, sizeof(context_));
            ClearIdentity();
            return false;
        }
        contextCreated_ = true;

        FfxFsr3UpscalerSharedResourceDescriptions sharedDescriptions = {};
        if (ffxFsr3UpscalerGetSharedResourceDescriptions(&context_, &sharedDescriptions) != FFX_OK ||
            !CreateSharedResource(sharedDescriptions.dilatedDepth, sharedDilatedDepth_, sharedDilatedDepthCreated_) ||
            !CreateSharedResource(sharedDescriptions.dilatedMotionVectors, sharedDilatedMotionVectors_, sharedDilatedMotionVectorsCreated_) ||
            !CreateSharedResource(sharedDescriptions.reconstructedPrevNearestDepth, sharedReconstructedPrevNearestDepth_,
                                  sharedReconstructedPrevNearestDepthCreated_))
        {
            Shutdown();
            return false;
        }

        ready_ = true;
        return true;
    }

    bool Dispatch(const M3kFsrDispatchInputs& in)
    {
        if (!ready_ || in.commandBuffer == VK_NULL_HANDLE ||
            in.color.image == VK_NULL_HANDLE || in.depth.image == VK_NULL_HANDLE ||
            in.motionVectors.image == VK_NULL_HANDLE || in.output.image == VK_NULL_HANDLE ||
            in.renderWidth == 0 || in.renderHeight == 0 || in.outputWidth == 0 || in.outputHeight == 0 ||
            in.renderWidth > maxRenderWidth_ || in.renderHeight > maxRenderHeight_ ||
            in.outputWidth > maxOutputWidth_ || in.outputHeight > maxOutputHeight_ ||
            in.preExposure <= 0.0f)
            return false;

        FfxFsr3UpscalerDispatchDescription dispatch = {};
        dispatch.commandList = ffxGetCommandListVK(in.commandBuffer);
        dispatch.color = MakeExternalResource(in.color, L"GTAIV_FSR_Color", false);
        dispatch.depth = MakeExternalResource(in.depth, L"GTAIV_FSR_Depth", false);
        dispatch.motionVectors = MakeExternalResource(in.motionVectors, L"GTAIV_FSR_MotionVectors", false);
        dispatch.output = MakeExternalResource(in.output, L"GTAIV_FSR_Output", true);

        // Auto exposure is enabled at context creation, so no external exposure texture
        // is required for the first proof. Reactive/transparency masks are deliberately
        // absent until the basic temporal reconstruction is validated on hardware.
        dispatch.exposure = {};
        dispatch.reactive = {};
        dispatch.transparencyAndComposition = {};

        dispatch.dilatedDepth = backendInterface_.fpGetResource(
            &backendInterface_, sharedDilatedDepth_);
        dispatch.dilatedMotionVectors = backendInterface_.fpGetResource(
            &backendInterface_, sharedDilatedMotionVectors_);
        dispatch.reconstructedPrevNearestDepth = backendInterface_.fpGetResource(
            &backendInterface_, sharedReconstructedPrevNearestDepth_);

        dispatch.jitterOffset = { in.jitterX, in.jitterY };
        dispatch.motionVectorScale = { in.motionVectorScaleX, in.motionVectorScaleY };
        dispatch.renderSize = { in.renderWidth, in.renderHeight };
        dispatch.upscaleSize = { in.outputWidth, in.outputHeight };

        dispatch.enableSharpening = in.enableSharpening;
        dispatch.sharpness = in.sharpness < 0.0f ? 0.0f : (in.sharpness > 1.0f ? 1.0f : in.sharpness);

        dispatch.frameTimeDelta = in.frameTimeMs > 0.0f ? in.frameTimeMs : 16.6667f;
        dispatch.preExposure = in.preExposure;
        dispatch.reset = in.reset;
        dispatch.cameraNear = in.cameraNear;
        dispatch.cameraFar = in.cameraFar;
        dispatch.cameraFovAngleVertical = in.cameraFovAngleVertical;
        dispatch.viewSpaceToMetersFactor = in.viewSpaceToMetersFactor;
        dispatch.flags = 0;

        return ffxFsr3UpscalerContextDispatch(&context_, &dispatch) == FFX_OK;
    }

    // The caller must ensure GPU work using this backend has retired before Shutdown().
    void Shutdown()
    {
        ready_ = false;

        DestroySharedResource(sharedReconstructedPrevNearestDepth_, sharedReconstructedPrevNearestDepthCreated_);
        DestroySharedResource(sharedDilatedMotionVectors_, sharedDilatedMotionVectorsCreated_);
        DestroySharedResource(sharedDilatedDepth_, sharedDilatedDepthCreated_);

        if (contextCreated_)
        {
            ffxFsr3UpscalerContextDestroy(&context_);
            contextCreated_ = false;
        }

        std::memset(&context_, 0, sizeof(context_));
        std::memset(&backendInterface_, 0, sizeof(backendInterface_));
        ReleaseScratch();
        ClearIdentity();
    }

    bool IsReady() const { return ready_; }

    bool Matches(
        VkDevice device,
        VkPhysicalDevice physicalDevice,
        uint32_t maxRenderWidth,
        uint32_t maxRenderHeight,
        uint32_t maxOutputWidth,
        uint32_t maxOutputHeight,
        bool depthInverted,
        bool depthInfinite) const
    {
        return ready_ &&
               device_ == device && physicalDevice_ == physicalDevice &&
               maxRenderWidth_ == maxRenderWidth && maxRenderHeight_ == maxRenderHeight &&
               maxOutputWidth_ == maxOutputWidth && maxOutputHeight_ == maxOutputHeight &&
               depthInverted_ == depthInverted && depthInfinite_ == depthInfinite;
    }

private:
    static VkImageCreateInfo MakeImageCreateInfo(const M3kFsrImage& image, bool forceStorage)
    {
        VkImageCreateInfo ci = { VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO };
        ci.imageType = VK_IMAGE_TYPE_2D;
        ci.format = image.format;
        ci.extent = { image.width, image.height, 1 };
        ci.mipLevels = 1;
        ci.arrayLayers = 1;
        ci.samples = VK_SAMPLE_COUNT_1_BIT;
        ci.tiling = VK_IMAGE_TILING_OPTIMAL;
        ci.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT |
                   ((image.storage || forceStorage) ? VK_IMAGE_USAGE_STORAGE_BIT : VK_IMAGE_USAGE_SAMPLED_BIT);
        ci.sharingMode = VK_SHARING_MODE_EXCLUSIVE;
        ci.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
        return ci;
    }

    static FfxResource MakeExternalResource(const M3kFsrImage& image, const wchar_t* name, bool forceStorage)
    {
        if (image.image == VK_NULL_HANDLE || image.format == VK_FORMAT_UNDEFINED ||
            image.width == 0 || image.height == 0)
            return {};

        const VkImageCreateInfo ci = MakeImageCreateInfo(image, forceStorage);
        const FfxResourceDescription desc = ffxGetImageResourceDescriptionVK(
            image.image, ci, forceStorage ? FFX_RESOURCE_USAGE_UAV : FFX_RESOURCE_USAGE_READ_ONLY);

        // Feeder-owned images are intentionally kept in VK_IMAGE_LAYOUT_GENERAL.
        // COMMON maps to GENERAL in AMD's Vulkan backend, and unregistering the
        // dynamic resource restores this exact initial state after FSR dispatch.
        return ffxGetResourceVK(reinterpret_cast<void*>(image.image), desc, name, FFX_RESOURCE_STATE_COMMON);
    }

    bool CreateSharedResource(
        const FfxCreateResourceDescription& description,
        FfxResourceInternal& resource,
        bool& created)
    {
        created = false;
        resource = {};
        if (backendInterface_.fpCreateResource == nullptr)
            return false;

        if (backendInterface_.fpCreateResource(&backendInterface_, &description, 0, &resource) != FFX_OK)
            return false;

        created = true;
        return true;
    }

    void DestroySharedResource(FfxResourceInternal& resource, bool& created)
    {
        if (created && backendInterface_.fpDestroyResource != nullptr)
            backendInterface_.fpDestroyResource(&backendInterface_, resource, 0);
        resource = {};
        created = false;
    }

    void ReleaseScratch()
    {
        if (scratch_ != nullptr)
            std::free(scratch_);
        scratch_ = nullptr;
        scratchSize_ = 0;
    }

    void ClearIdentity()
    {
        device_ = VK_NULL_HANDLE;
        physicalDevice_ = VK_NULL_HANDLE;
        maxRenderWidth_ = maxRenderHeight_ = 0;
        maxOutputWidth_ = maxOutputHeight_ = 0;
        depthInverted_ = false;
        depthInfinite_ = false;
    }

    FfxInterface backendInterface_ = {};
    FfxFsr3UpscalerContext context_ = {};

    FfxResourceInternal sharedDilatedDepth_ = {};
    FfxResourceInternal sharedDilatedMotionVectors_ = {};
    FfxResourceInternal sharedReconstructedPrevNearestDepth_ = {};
    bool sharedDilatedDepthCreated_ = false;
    bool sharedDilatedMotionVectorsCreated_ = false;
    bool sharedReconstructedPrevNearestDepthCreated_ = false;

    void* scratch_ = nullptr;
    size_t scratchSize_ = 0;

    VkDevice device_ = VK_NULL_HANDLE;
    VkPhysicalDevice physicalDevice_ = VK_NULL_HANDLE;
    uint32_t maxRenderWidth_ = 0;
    uint32_t maxRenderHeight_ = 0;
    uint32_t maxOutputWidth_ = 0;
    uint32_t maxOutputHeight_ = 0;
    bool depthInverted_ = false;
    bool depthInfinite_ = false;

    bool contextCreated_ = false;
    bool ready_ = false;
};
