#include <cstdio>
#include "m3k_fsr_backend.h"

int main()
{
    // Reference symbols from BOTH static libraries and compile the exact wrapper that
    // will later be attached to the feeder. This is intentionally not a GPU runtime
    // test; GitHub Actions has no GTA IV render path/device to dispatch against.
    auto *getInterface = &ffxGetInterfaceVK;
    auto *getScratch   = &ffxGetScratchMemorySizeVK;
    auto *createFsr    = &ffxFsr3UpscalerContextCreate;
    auto *dispatchFsr  = &ffxFsr3UpscalerContextDispatch;

    M3kFsrBackend backend;
    M3kFsrDispatchInputs inputs = {};
    (void)inputs;

    if (!getInterface || !getScratch || !createFsr || !dispatchFsr || backend.IsReady())
        return 2;

    std::printf("FidelityFX FSR3 Upscaler %d.%d.%d Vulkan backend wrapper compile/link OK\n",
        FFX_FSR3UPSCALER_VERSION_MAJOR,
        FFX_FSR3UPSCALER_VERSION_MINOR,
        FFX_FSR3UPSCALER_VERSION_PATCH);
    return 0;
}
