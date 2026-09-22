#include <cstdio>
#include <FidelityFX/host/ffx_fsr3upscaler.h>
#include <FidelityFX/host/backends/vk/ffx_vk.h>

int main()
{
    // Reference symbols from BOTH static libraries. This is intentionally not a
    // runtime/device test; it proves the GTA IV feeder toolchain can consume the
    // pinned FidelityFX Vulkan SDK headers and link its backend/upscaler libraries.
    auto *getInterface = &ffxGetInterfaceVK;
    auto *getScratch   = &ffxGetScratchMemorySizeVK;
    auto *createFsr    = &ffxFsr3UpscalerContextCreate;
    auto *dispatchFsr  = &ffxFsr3UpscalerContextDispatch;

    if (!getInterface || !getScratch || !createFsr || !dispatchFsr)
        return 2;

    std::printf("FidelityFX FSR3 Upscaler %d.%d.%d Vulkan consumer link OK\n",
        FFX_FSR3UPSCALER_VERSION_MAJOR,
        FFX_FSR3UPSCALER_VERSION_MINOR,
        FFX_FSR3UPSCALER_VERSION_PATCH);
    return 0;
}
