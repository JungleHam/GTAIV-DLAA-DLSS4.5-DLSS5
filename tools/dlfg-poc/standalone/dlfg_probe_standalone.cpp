#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <vulkan/vulkan.h>
#include <nvsdk_ngx.h>
#include <nvsdk_ngx_vk.h>
#include <nvsdk_ngx_defs_dlssg.h>
#include <nvsdk_ngx_helpers_dlssg_vk.h>

#include <cstdint>
#include <cstdio>
#include <cstring>
#include <set>
#include <string>
#include <vector>

namespace
{
constexpr unsigned long long kRemixApplicationId = 102100511ull;
constexpr uint32_t kWidth = 2560;
constexpr uint32_t kHeight = 1440;

std::wstring exe_directory()
{
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring s(path);
    const size_t slash = s.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"." : s.substr(0, slash);
}

std::wstring exe_name()
{
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(nullptr, path, MAX_PATH);
    std::wstring s(path);
    const size_t slash = s.find_last_of(L"\\/");
    return slash == std::wstring::npos ? s : s.substr(slash + 1);
}

FILE *open_log()
{
    const std::wstring path = exe_directory() + L"\\dlfg-standalone.log";
    FILE *f = nullptr;
    _wfopen_s(&f, path.c_str(), L"w, ccs=UTF-8");
    return f;
}

void logf(FILE *f, const char *fmt, ...)
{
    if (!f)
        return;
    va_list ap;
    va_start(ap, fmt);
    std::vfprintf(f, fmt, ap);
    va_end(ap);
    std::fputc('\n', f);
    std::fflush(f);
}

const char *ngx_name(NVSDK_NGX_Result r)
{
    switch (r)
    {
    case NVSDK_NGX_Result_Success: return "Success";
    case NVSDK_NGX_Result_FAIL_FeatureNotSupported: return "FAIL_FeatureNotSupported";
    case NVSDK_NGX_Result_FAIL_PlatformError: return "FAIL_PlatformError";
    case NVSDK_NGX_Result_FAIL_FeatureAlreadyExists: return "FAIL_FeatureAlreadyExists";
    case NVSDK_NGX_Result_FAIL_FeatureNotFound: return "FAIL_FeatureNotFound";
    case NVSDK_NGX_Result_FAIL_InvalidParameter: return "FAIL_InvalidParameter";
    case NVSDK_NGX_Result_FAIL_ScratchBufferTooSmall: return "FAIL_ScratchBufferTooSmall";
    case NVSDK_NGX_Result_FAIL_NotInitialized: return "FAIL_NotInitialized";
    case NVSDK_NGX_Result_FAIL_UnsupportedInputFormat: return "FAIL_UnsupportedInputFormat";
    case NVSDK_NGX_Result_FAIL_RWFlagMissing: return "FAIL_RWFlagMissing";
    case NVSDK_NGX_Result_FAIL_MissingInput: return "FAIL_MissingInput";
    case NVSDK_NGX_Result_FAIL_UnableToInitializeFeature: return "FAIL_UnableToInitializeFeature";
    case NVSDK_NGX_Result_FAIL_OutOfDate: return "FAIL_OutOfDate";
    case NVSDK_NGX_Result_FAIL_OutOfGPUMemory: return "FAIL_OutOfGPUMemory";
    case NVSDK_NGX_Result_FAIL_UnsupportedFormat: return "FAIL_UnsupportedFormat";
    case NVSDK_NGX_Result_FAIL_UnableToWriteToAppDataPath: return "FAIL_UnableToWriteToAppDataPath";
    case NVSDK_NGX_Result_FAIL_UnsupportedParameter: return "FAIL_UnsupportedParameter";
    case NVSDK_NGX_Result_FAIL_Denied: return "FAIL_Denied";
    case NVSDK_NGX_Result_FAIL_NotImplemented: return "FAIL_NotImplemented";
    default: return "unknown";
    }
}

bool file_exists(const std::wstring &path)
{
    const DWORD a = GetFileAttributesW(path.c_str());
    return a != INVALID_FILE_ATTRIBUTES && (a & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

bool extension_present(const char *name, const std::vector<VkExtensionProperties> &list)
{
    for (const auto &e : list)
        if (std::strcmp(name, e.extensionName) == 0)
            return true;
    return false;
}

std::vector<const char *> dedupe(unsigned int count, const char **src)
{
    std::vector<const char *> out;
    std::set<std::string> seen;
    for (unsigned int i = 0; i < count; ++i)
        if (src && src[i] && seen.insert(src[i]).second)
            out.push_back(src[i]);
    return out;
}

struct VkFns
{
    HMODULE mod = nullptr;
    PFN_vkGetInstanceProcAddr gipa = nullptr;
    PFN_vkGetDeviceProcAddr gdpa = nullptr;
    PFN_vkCreateInstance createInstance = nullptr;
    PFN_vkEnumerateInstanceExtensionProperties enumInstanceExt = nullptr;
    PFN_vkDestroyInstance destroyInstance = nullptr;
    PFN_vkEnumeratePhysicalDevices enumPhysical = nullptr;
    PFN_vkGetPhysicalDeviceProperties getPhysicalProps = nullptr;
    PFN_vkGetPhysicalDeviceQueueFamilyProperties getQueueProps = nullptr;
    PFN_vkEnumerateDeviceExtensionProperties enumDeviceExt = nullptr;
    PFN_vkGetPhysicalDeviceFeatures2 getFeatures2 = nullptr;
    PFN_vkCreateDevice createDevice = nullptr;
    PFN_vkDestroyDevice destroyDevice = nullptr;
    PFN_vkGetDeviceQueue getQueue = nullptr;
    PFN_vkCreateCommandPool createCommandPool = nullptr;
    PFN_vkDestroyCommandPool destroyCommandPool = nullptr;
    PFN_vkAllocateCommandBuffers allocCommandBuffers = nullptr;
    PFN_vkBeginCommandBuffer beginCommandBuffer = nullptr;
    PFN_vkEndCommandBuffer endCommandBuffer = nullptr;
    PFN_vkQueueSubmit queueSubmit = nullptr;
    PFN_vkQueueWaitIdle queueWaitIdle = nullptr;

    bool load_global()
    {
        mod = LoadLibraryW(L"vulkan-1.dll");
        if (!mod) return false;
        gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(mod, "vkGetInstanceProcAddr"));
        if (!gipa) return false;
        createInstance = reinterpret_cast<PFN_vkCreateInstance>(gipa(VK_NULL_HANDLE, "vkCreateInstance"));
        enumInstanceExt = reinterpret_cast<PFN_vkEnumerateInstanceExtensionProperties>(gipa(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties"));
        return createInstance && enumInstanceExt;
    }

    bool load_instance(VkInstance instance)
    {
        destroyInstance = reinterpret_cast<PFN_vkDestroyInstance>(gipa(instance, "vkDestroyInstance"));
        enumPhysical = reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(gipa(instance, "vkEnumeratePhysicalDevices"));
        getPhysicalProps = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(gipa(instance, "vkGetPhysicalDeviceProperties"));
        getQueueProps = reinterpret_cast<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(gipa(instance, "vkGetPhysicalDeviceQueueFamilyProperties"));
        enumDeviceExt = reinterpret_cast<PFN_vkEnumerateDeviceExtensionProperties>(gipa(instance, "vkEnumerateDeviceExtensionProperties"));
        getFeatures2 = reinterpret_cast<PFN_vkGetPhysicalDeviceFeatures2>(gipa(instance, "vkGetPhysicalDeviceFeatures2"));
        createDevice = reinterpret_cast<PFN_vkCreateDevice>(gipa(instance, "vkCreateDevice"));
        gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(gipa(instance, "vkGetDeviceProcAddr"));
        return destroyInstance && enumPhysical && getPhysicalProps && getQueueProps && enumDeviceExt && createDevice && gdpa;
    }

    bool load_device(VkDevice device)
    {
        destroyDevice = reinterpret_cast<PFN_vkDestroyDevice>(gdpa(device, "vkDestroyDevice"));
        getQueue = reinterpret_cast<PFN_vkGetDeviceQueue>(gdpa(device, "vkGetDeviceQueue"));
        createCommandPool = reinterpret_cast<PFN_vkCreateCommandPool>(gdpa(device, "vkCreateCommandPool"));
        destroyCommandPool = reinterpret_cast<PFN_vkDestroyCommandPool>(gdpa(device, "vkDestroyCommandPool"));
        allocCommandBuffers = reinterpret_cast<PFN_vkAllocateCommandBuffers>(gdpa(device, "vkAllocateCommandBuffers"));
        beginCommandBuffer = reinterpret_cast<PFN_vkBeginCommandBuffer>(gdpa(device, "vkBeginCommandBuffer"));
        endCommandBuffer = reinterpret_cast<PFN_vkEndCommandBuffer>(gdpa(device, "vkEndCommandBuffer"));
        queueSubmit = reinterpret_cast<PFN_vkQueueSubmit>(gdpa(device, "vkQueueSubmit"));
        queueWaitIdle = reinterpret_cast<PFN_vkQueueWaitIdle>(gdpa(device, "vkQueueWaitIdle"));
        return destroyDevice && getQueue && createCommandPool && destroyCommandPool && allocCommandBuffers && beginCommandBuffer && endCommandBuffer && queueSubmit && queueWaitIdle;
    }

    ~VkFns() { if (mod) FreeLibrary(mod); }
};
}

int wmain()
{
    FILE *log = open_log();
    if (!log)
        return 2;

    const std::wstring dir = exe_directory();
    const std::wstring runtime = dir + L"\\nvngx_dlssg.dll";

    logf(log, "============================================================");
    logf(log, "DLFG milestone 1.2 STANDALONE probe");
    logf(log, "This process is isolated from GTA IV and NvRemixBridge's real render process.");
    logf(log, "exe name: %ls", exe_name().c_str());
    logf(log, "app id: %llu", kRemixApplicationId);

    if (!file_exists(runtime))
    {
        logf(log, "FAIL: nvngx_dlssg.dll is missing next to this EXE.");
        fclose(log);
        return 3;
    }
    logf(log, "runtime present: %ls", runtime.c_str());

    unsigned int instance_count = 0, device_count = 0;
    const char **instance_req = nullptr, **device_req = nullptr;
    NVSDK_NGX_Result nr = NVSDK_NGX_VULKAN_RequiredExtensions(&instance_count, &instance_req, &device_count, &device_req);
    logf(log, "NVSDK_NGX_VULKAN_RequiredExtensions -> 0x%08X (%s), instance=%u device=%u", (unsigned)nr, ngx_name(nr), instance_count, device_count);
    if (NVSDK_NGX_FAILED(nr)) { fclose(log); return 4; }

    VkFns vk;
    if (!vk.load_global()) { logf(log, "FAIL: could not load Vulkan loader"); fclose(log); return 5; }

    uint32_t iec = 0;
    if (vk.enumInstanceExt(nullptr, &iec, nullptr) != VK_SUCCESS) { fclose(log); return 6; }
    std::vector<VkExtensionProperties> ie(iec);
    if (vk.enumInstanceExt(nullptr, &iec, ie.data()) != VK_SUCCESS) { fclose(log); return 7; }
    auto instance_exts = dedupe(instance_count, instance_req);
    for (const char *e : instance_exts)
    {
        logf(log, "instance ext %s: %s", e, extension_present(e, ie) ? "OK" : "MISSING");
        if (!extension_present(e, ie)) { fclose(log); return 8; }
    }

    VkApplicationInfo ai{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    ai.pApplicationName = "NvRemixBridge";
    ai.applicationVersion = 1;
    ai.pEngineName = "RTX Remix DLFG standalone probe";
    ai.engineVersion = 1;
    ai.apiVersion = VK_API_VERSION_1_3;

    VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &ai;
    ici.enabledExtensionCount = (uint32_t)instance_exts.size();
    ici.ppEnabledExtensionNames = instance_exts.empty() ? nullptr : instance_exts.data();

    VkInstance instance = VK_NULL_HANDLE;
    VkResult vr = vk.createInstance(&ici, nullptr, &instance);
    logf(log, "vkCreateInstance -> %d", (int)vr);
    if (vr != VK_SUCCESS) { fclose(log); return 9; }
    if (!vk.load_instance(instance)) { logf(log, "FAIL: instance functions"); vk.destroyInstance(instance, nullptr); fclose(log); return 10; }

    uint32_t gpu_count = 0;
    vr = vk.enumPhysical(instance, &gpu_count, nullptr);
    if (vr != VK_SUCCESS || !gpu_count) { logf(log, "FAIL: no Vulkan GPUs"); vk.destroyInstance(instance, nullptr); fclose(log); return 11; }
    std::vector<VkPhysicalDevice> gpus(gpu_count);
    vk.enumPhysical(instance, &gpu_count, gpus.data());

    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties props{};
    for (auto g : gpus)
    {
        VkPhysicalDeviceProperties p{};
        vk.getPhysicalProps(g, &p);
        logf(log, "GPU: vendor=%04X device=%04X name=%s", p.vendorID, p.deviceID, p.deviceName);
        if (!physical && p.vendorID == 0x10DE) { physical = g; props = p; }
    }
    if (!physical) { logf(log, "FAIL: no NVIDIA GPU"); vk.destroyInstance(instance, nullptr); fclose(log); return 12; }
    logf(log, "selected GPU: %s", props.deviceName);

    NVSDK_NGX_FeatureCommonInfo common{};
    const wchar_t *paths[] = { dir.c_str(), L"." };
    common.PathListInfo.Path = paths;
    common.PathListInfo.Length = 2;

    NVSDK_NGX_FeatureDiscoveryInfo discovery{};
    discovery.SDKVersion = NVSDK_NGX_Version_API;
    discovery.FeatureID = NVSDK_NGX_Feature_FrameGeneration;
    discovery.Identifier.IdentifierType = NVSDK_NGX_Application_Identifier_Type_Application_Id;
    discovery.Identifier.v.ApplicationId = kRemixApplicationId;
    discovery.ApplicationDataPath = dir.c_str();
    discovery.FeatureInfo = &common;
    NVSDK_NGX_FeatureRequirement req{};
    nr = NVSDK_NGX_VULKAN_GetFeatureRequirements(instance, physical, &discovery, &req);
    logf(log, "GetFeatureRequirements(FG) -> 0x%08X (%s), supportBits=%u minHW=0x%X minOS=%s", (unsigned)nr, ngx_name(nr), (unsigned)req.FeatureSupported, req.MinHWArchitecture, req.MinOSVersion);

    uint32_t qcount = 0;
    vk.getQueueProps(physical, &qcount, nullptr);
    std::vector<VkQueueFamilyProperties> qprops(qcount);
    vk.getQueueProps(physical, &qcount, qprops.data());
    uint32_t qfamily = UINT32_MAX;
    for (uint32_t i = 0; i < qcount; ++i)
        if ((qprops[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && qprops[i].queueCount) { qfamily = i; break; }
    if (qfamily == UINT32_MAX) { logf(log, "FAIL: no graphics queue"); vk.destroyInstance(instance, nullptr); fclose(log); return 13; }

    uint32_t dec = 0;
    vk.enumDeviceExt(physical, nullptr, &dec, nullptr);
    std::vector<VkExtensionProperties> de(dec);
    vk.enumDeviceExt(physical, nullptr, &dec, de.data());
    auto device_exts = dedupe(device_count, device_req);
    for (const char *e : device_exts)
    {
        logf(log, "device ext %s: %s", e, extension_present(e, de) ? "OK" : "MISSING");
        if (!extension_present(e, de)) { vk.destroyInstance(instance, nullptr); fclose(log); return 14; }
    }

    VkPhysicalDeviceBufferDeviceAddressFeatures bda{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES};
    VkPhysicalDeviceFeatures2 f2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
    f2.pNext = &bda;
    if (vk.getFeatures2) vk.getFeatures2(physical, &f2);
    logf(log, "features: shaderInt64=%u storageReadNoFormat=%u storageWriteNoFormat=%u bufferDeviceAddress=%u", f2.features.shaderInt64, f2.features.shaderStorageImageReadWithoutFormat, f2.features.shaderStorageImageWriteWithoutFormat, bda.bufferDeviceAddress);

    float priority = 1.0f;
    VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = qfamily;
    qci.queueCount = 1;
    qci.pQueuePriorities = &priority;

    VkPhysicalDeviceBufferDeviceAddressFeatures bda_enable{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES};
    bda_enable.bufferDeviceAddress = bda.bufferDeviceAddress;

    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.pNext = bda.bufferDeviceAddress ? &bda_enable : nullptr;
    dci.queueCreateInfoCount = 1;
    dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = (uint32_t)device_exts.size();
    dci.ppEnabledExtensionNames = device_exts.empty() ? nullptr : device_exts.data();
    dci.pEnabledFeatures = &f2.features;

    VkDevice device = VK_NULL_HANDLE;
    vr = vk.createDevice(physical, &dci, nullptr, &device);
    logf(log, "vkCreateDevice -> %d", (int)vr);
    if (vr != VK_SUCCESS) { vk.destroyInstance(instance, nullptr); fclose(log); return 15; }
    if (!vk.load_device(device)) { logf(log, "FAIL: device functions"); vk.destroyDevice(device, nullptr); vk.destroyInstance(instance, nullptr); fclose(log); return 16; }

    VkQueue queue = VK_NULL_HANDLE;
    vk.getQueue(device, qfamily, 0, &queue);

    nr = NVSDK_NGX_VULKAN_Init(kRemixApplicationId, dir.c_str(), instance, physical, device);
    logf(log, "NVSDK_NGX_VULKAN_Init -> 0x%08X (%s)", (unsigned)nr, ngx_name(nr));
    if (NVSDK_NGX_FAILED(nr)) { vk.destroyDevice(device, nullptr); vk.destroyInstance(instance, nullptr); fclose(log); return 17; }

    NVSDK_NGX_Parameter *params = nullptr;
    nr = NVSDK_NGX_VULKAN_GetCapabilityParameters(&params);
    logf(log, "GetCapabilityParameters -> 0x%08X (%s) params=%p", (unsigned)nr, ngx_name(nr), params);
    if (NVSDK_NGX_FAILED(nr) || !params) { NVSDK_NGX_VULKAN_Shutdown1(device); vk.destroyDevice(device, nullptr); vk.destroyInstance(instance, nullptr); fclose(log); return 18; }

    int available = 0, needs_driver = 0;
    unsigned int max_frames = 0;
    NVSDK_NGX_Result qr = params->Get(NVSDK_NGX_Parameter_FrameGeneration_Available, &available);
    logf(log, "FrameGeneration.Available -> 0x%08X (%s) value=%d", (unsigned)qr, ngx_name(qr), available);
    qr = params->Get(NVSDK_NGX_Parameter_FrameGeneration_NeedsUpdatedDriver, &needs_driver);
    logf(log, "FrameGeneration.NeedsUpdatedDriver -> 0x%08X (%s) value=%d", (unsigned)qr, ngx_name(qr), needs_driver);
    qr = params->Get(NVSDK_NGX_DLSSG_Parameter_MultiFrameCountMax, &max_frames);
    logf(log, "DLSSG.MultiFrameCountMax -> 0x%08X (%s) value=%u", (unsigned)qr, ngx_name(qr), max_frames);

    VkCommandPool pool = VK_NULL_HANDLE;
    VkCommandPoolCreateInfo pci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pci.queueFamilyIndex = qfamily;
    pci.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT | VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    vr = vk.createCommandPool(device, &pci, nullptr, &pool);
    logf(log, "vkCreateCommandPool -> %d", (int)vr);

    NVSDK_NGX_Handle *feature = nullptr;
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    if (vr == VK_SUCCESS)
    {
        VkCommandBufferAllocateInfo cai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
        cai.commandPool = pool;
        cai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        cai.commandBufferCount = 1;
        vr = vk.allocCommandBuffers(device, &cai, &cmd);
        logf(log, "vkAllocateCommandBuffers -> %d", (int)vr);
    }
    if (vr == VK_SUCCESS)
    {
        VkCommandBufferBeginInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
        cbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        vr = vk.beginCommandBuffer(cmd, &cbi);
        logf(log, "vkBeginCommandBuffer -> %d", (int)vr);
    }

    const VkFormat formats[] = { VK_FORMAT_B8G8R8A8_UNORM, VK_FORMAT_R8G8B8A8_UNORM, VK_FORMAT_R16G16B16A16_SFLOAT };
    const char *names[] = { "B8G8R8A8_UNORM", "R8G8B8A8_UNORM", "R16G16B16A16_SFLOAT" };
    if (vr == VK_SUCCESS)
    {
        for (int i = 0; i < 3 && !feature; ++i)
        {
            NVSDK_NGX_DLSSG_Create_Params cp{};
            cp.Width = kWidth;
            cp.Height = kHeight;
            cp.NativeBackbufferFormat = (unsigned int)formats[i];
            cp.RenderWidth = kWidth;
            cp.RenderHeight = kHeight;
            cp.DynamicResolutionScaling = false;
            nr = NGX_VK_CREATE_DLSSG(cmd, 1, 1, &feature, params, &cp);
            logf(log, "NGX_VK_CREATE_DLSSG(%ux%u %s) -> 0x%08X (%s) feature=%p", kWidth, kHeight, names[i], (unsigned)nr, ngx_name(nr), feature);
        }
        vr = vk.endCommandBuffer(cmd);
        logf(log, "vkEndCommandBuffer -> %d", (int)vr);
    }

    if (feature && vr == VK_SUCCESS)
    {
        VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO};
        si.commandBufferCount = 1;
        si.pCommandBuffers = &cmd;
        vr = vk.queueSubmit(queue, 1, &si, VK_NULL_HANDLE);
        logf(log, "vkQueueSubmit -> %d", (int)vr);
        if (vr == VK_SUCCESS)
        {
            vr = vk.queueWaitIdle(queue);
            logf(log, "vkQueueWaitIdle -> %d", (int)vr);
        }
        logf(log, "MILESTONE 1.2 %s", vr == VK_SUCCESS ? "PASSED: DLFG feature created in isolated process." : "FAILED during submitted feature-create work.");
    }
    else
    {
        logf(log, "MILESTONE 1.2 NOT PASSED: capability is visible but feature creation failed.");
    }

    if (feature)
    {
        nr = NVSDK_NGX_VULKAN_ReleaseFeature(feature);
        logf(log, "ReleaseFeature -> 0x%08X (%s)", (unsigned)nr, ngx_name(nr));
    }
    if (params)
    {
        nr = NVSDK_NGX_VULKAN_DestroyParameters(params);
        logf(log, "DestroyParameters -> 0x%08X (%s)", (unsigned)nr, ngx_name(nr));
    }
    nr = NVSDK_NGX_VULKAN_Shutdown1(device);
    logf(log, "NVSDK_NGX_VULKAN_Shutdown1 -> 0x%08X (%s)", (unsigned)nr, ngx_name(nr));

    if (pool) vk.destroyCommandPool(device, pool, nullptr);
    vk.destroyDevice(device, nullptr);
    vk.destroyInstance(instance, nullptr);
    logf(log, "cleanup complete");
    fclose(log);
    return feature ? 0 : 1;
}
