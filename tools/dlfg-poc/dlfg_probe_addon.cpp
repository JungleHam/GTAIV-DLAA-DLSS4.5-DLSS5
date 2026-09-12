#define WIN32_NO_STATUS
#include <windows.h>
#include <ntstatus.h>
#undef WIN32_NO_STATUS
#include <winternl.h>
#include <d3dkmthk.h>
#include <d3dkmdt.h>

#include <reshade.hpp>
#include <vulkan/vulkan.h>

#include <nvsdk_ngx.h>
#include <nvsdk_ngx_vk.h>
#include <nvsdk_ngx_defs_dlssg.h>
#include <nvsdk_ngx_helpers_dlssg.h>
#include <nvsdk_ngx_helpers_dlssg_vk.h>

#include <atomic>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <mutex>
#include <set>
#include <string>
#include <vector>

namespace
{
HMODULE g_module = nullptr;
std::atomic<bool> g_started = false;
std::mutex g_log_mutex;

constexpr unsigned long long kAppId = 102100511ull;
constexpr uint32_t kWidth = 2560;
constexpr uint32_t kHeight = 1440;

std::wstring module_directory()
{
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(g_module, path, MAX_PATH);
    std::wstring s(path);
    const size_t p = s.find_last_of(L"\\/");
    return p == std::wstring::npos ? L"." : s.substr(0, p);
}

void log_line(const char *text)
{
    std::lock_guard<std::mutex> lock(g_log_mutex);
    const std::wstring path = module_directory() + L"\\dlfg-probe.log";
    HANDLE f = CreateFileW(path.c_str(), FILE_APPEND_DATA, FILE_SHARE_READ | FILE_SHARE_WRITE,
        nullptr, OPEN_ALWAYS, FILE_ATTRIBUTE_NORMAL, nullptr);
    if (f == INVALID_HANDLE_VALUE)
        return;

    SYSTEMTIME st{};
    GetLocalTime(&st);
    char line[4096] = {};
    const int n = std::snprintf(line, sizeof(line), "%02u:%02u:%02u.%03u  %s\r\n",
        st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, text ? text : "");
    if (n > 0)
    {
        DWORD written = 0;
        WriteFile(f, line, static_cast<DWORD>(n), &written, nullptr);
    }
    CloseHandle(f);
}

void logf(const char *fmt, ...)
{
    char buf[3600] = {};
    va_list ap;
    va_start(ap, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    log_line(buf);
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

void log_ngx(const char *what, NVSDK_NGX_Result r)
{
    logf("%s -> 0x%08X (%s)", what, static_cast<unsigned int>(r), ngx_name(r));
}

void NVSDK_CONV ngx_log_callback(const char *message, NVSDK_NGX_Logging_Level level, NVSDK_NGX_Feature feature)
{
    if (!message)
        return;
    char clean[3000] = {};
    size_t j = 0;
    for (size_t i = 0; message[i] != 0 && j + 2 < sizeof(clean); ++i)
    {
        const char c = message[i];
        clean[j++] = (c == '\r' || c == '\n') ? ' ' : c;
    }
    clean[j] = 0;
    logf("[NGX] level=%d feature=%d %s", static_cast<int>(level), static_cast<int>(feature), clean);
}

bool extension_present(const char *name, const std::vector<VkExtensionProperties> &list)
{
    for (const auto &e : list)
        if (std::strcmp(name, e.extensionName) == 0)
            return true;
    return false;
}

std::vector<const char *> dedupe(unsigned int count, const char **names)
{
    std::vector<const char *> out;
    std::set<std::string> seen;
    for (unsigned int i = 0; i < count; ++i)
        if (names[i] && seen.insert(names[i]).second)
            out.push_back(names[i]);
    return out;
}

struct VkFns
{
    HMODULE lib = nullptr;
    PFN_vkGetInstanceProcAddr gipa = nullptr;
    PFN_vkGetDeviceProcAddr gdpa = nullptr;
    PFN_vkCreateInstance CreateInstance = nullptr;
    PFN_vkEnumerateInstanceExtensionProperties EnumInstanceExt = nullptr;
    PFN_vkDestroyInstance DestroyInstance = nullptr;
    PFN_vkEnumeratePhysicalDevices EnumPhysical = nullptr;
    PFN_vkGetPhysicalDeviceProperties GetProps = nullptr;
    PFN_vkGetPhysicalDeviceProperties2 GetProps2 = nullptr;
    PFN_vkGetPhysicalDeviceFeatures GetFeatures = nullptr;
    PFN_vkGetPhysicalDeviceFeatures2 GetFeatures2 = nullptr;
    PFN_vkGetPhysicalDeviceQueueFamilyProperties GetQueues = nullptr;
    PFN_vkEnumerateDeviceExtensionProperties EnumDeviceExt = nullptr;
    PFN_vkCreateDevice CreateDevice = nullptr;
    PFN_vkDestroyDevice DestroyDevice = nullptr;
    PFN_vkGetDeviceQueue GetQueue = nullptr;
    PFN_vkCreateCommandPool CreatePool = nullptr;
    PFN_vkDestroyCommandPool DestroyPool = nullptr;
    PFN_vkAllocateCommandBuffers AllocCmd = nullptr;
    PFN_vkBeginCommandBuffer BeginCmd = nullptr;
    PFN_vkEndCommandBuffer EndCmd = nullptr;
    PFN_vkQueueSubmit QueueSubmit = nullptr;
    PFN_vkQueueWaitIdle QueueWaitIdle = nullptr;

    bool global()
    {
        lib = LoadLibraryW(L"vulkan-1.dll");
        if (!lib) return false;
        gipa = reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(lib, "vkGetInstanceProcAddr"));
        if (!gipa) return false;
        CreateInstance = reinterpret_cast<PFN_vkCreateInstance>(gipa(VK_NULL_HANDLE, "vkCreateInstance"));
        EnumInstanceExt = reinterpret_cast<PFN_vkEnumerateInstanceExtensionProperties>(gipa(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties"));
        return CreateInstance && EnumInstanceExt;
    }

    bool instance(VkInstance i)
    {
        DestroyInstance = reinterpret_cast<PFN_vkDestroyInstance>(gipa(i, "vkDestroyInstance"));
        EnumPhysical = reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(gipa(i, "vkEnumeratePhysicalDevices"));
        GetProps = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(gipa(i, "vkGetPhysicalDeviceProperties"));
        GetProps2 = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties2>(gipa(i, "vkGetPhysicalDeviceProperties2"));
        GetFeatures = reinterpret_cast<PFN_vkGetPhysicalDeviceFeatures>(gipa(i, "vkGetPhysicalDeviceFeatures"));
        GetFeatures2 = reinterpret_cast<PFN_vkGetPhysicalDeviceFeatures2>(gipa(i, "vkGetPhysicalDeviceFeatures2"));
        GetQueues = reinterpret_cast<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(gipa(i, "vkGetPhysicalDeviceQueueFamilyProperties"));
        EnumDeviceExt = reinterpret_cast<PFN_vkEnumerateDeviceExtensionProperties>(gipa(i, "vkEnumerateDeviceExtensionProperties"));
        CreateDevice = reinterpret_cast<PFN_vkCreateDevice>(gipa(i, "vkCreateDevice"));
        gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(gipa(i, "vkGetDeviceProcAddr"));
        return DestroyInstance && EnumPhysical && GetProps && GetProps2 && GetFeatures && GetFeatures2 && GetQueues && EnumDeviceExt && CreateDevice && gdpa;
    }

    bool device(VkDevice d)
    {
        DestroyDevice = reinterpret_cast<PFN_vkDestroyDevice>(gdpa(d, "vkDestroyDevice"));
        GetQueue = reinterpret_cast<PFN_vkGetDeviceQueue>(gdpa(d, "vkGetDeviceQueue"));
        CreatePool = reinterpret_cast<PFN_vkCreateCommandPool>(gdpa(d, "vkCreateCommandPool"));
        DestroyPool = reinterpret_cast<PFN_vkDestroyCommandPool>(gdpa(d, "vkDestroyCommandPool"));
        AllocCmd = reinterpret_cast<PFN_vkAllocateCommandBuffers>(gdpa(d, "vkAllocateCommandBuffers"));
        BeginCmd = reinterpret_cast<PFN_vkBeginCommandBuffer>(gdpa(d, "vkBeginCommandBuffer"));
        EndCmd = reinterpret_cast<PFN_vkEndCommandBuffer>(gdpa(d, "vkEndCommandBuffer"));
        QueueSubmit = reinterpret_cast<PFN_vkQueueSubmit>(gdpa(d, "vkQueueSubmit"));
        QueueWaitIdle = reinterpret_cast<PFN_vkQueueWaitIdle>(gdpa(d, "vkQueueWaitIdle"));
        return DestroyDevice && GetQueue && CreatePool && DestroyPool && AllocCmd && BeginCmd && EndCmd && QueueSubmit && QueueWaitIdle;
    }

    ~VkFns() { if (lib) FreeLibrary(lib); }
};

int hags_status(VkFns &vk, VkPhysicalDevice physical)
{
    VkPhysicalDeviceIDProperties ids{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_ID_PROPERTIES};
    VkPhysicalDeviceProperties2 props2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_PROPERTIES_2};
    props2.pNext = &ids;
    vk.GetProps2(physical, &props2);
    if (!ids.deviceLUIDValid)
        return -1;

    LUID luid{};
    static_assert(sizeof(luid) == VK_LUID_SIZE);
    std::memcpy(&luid, ids.deviceLUID, sizeof(luid));

    D3DKMT_ENUMADAPTERS2 e{};
    if (!NT_SUCCESS(D3DKMTEnumAdapters2(&e)) || e.NumAdapters == 0)
        return -1;
    std::vector<D3DKMT_ADAPTERINFO> adapters(e.NumAdapters);
    e.pAdapters = adapters.data();
    if (!NT_SUCCESS(D3DKMTEnumAdapters2(&e)))
        return -1;

    for (const auto &a : adapters)
    {
        if (a.AdapterLuid.HighPart != luid.HighPart || a.AdapterLuid.LowPart != luid.LowPart)
            continue;
        D3DKMT_WDDM_2_7_CAPS caps{};
        D3DKMT_QUERYADAPTERINFO q{};
        q.hAdapter = a.hAdapter;
        q.Type = KMTQAITYPE_WDDM_2_7_CAPS;
        q.pPrivateDriverData = &caps;
        q.PrivateDriverDataSize = sizeof(caps);
        if (!NT_SUCCESS(D3DKMTQueryAdapterInfo(&q)))
            return -1;
        return caps.HwSchEnabled ? 1 : 0;
    }
    return -1;
}

DWORD WINAPI probe_worker(LPVOID)
{
    Sleep(2500);
    log_line("============================================================");
    log_line("DLFG POC milestone 1.1: diagnostics + private Vulkan feature-create probe");
    log_line("No generated frame is evaluated or presented; the game swapchain is not modified.");

    const std::wstring dir = module_directory();
    const std::wstring dll = dir + L"\\nvngx_dlssg.dll";
    if (GetFileAttributesW(dll.c_str()) == INVALID_FILE_ATTRIBUTES)
    {
        log_line("FAIL: nvngx_dlssg.dll missing next to the add-on");
        return 0;
    }

    unsigned int ric = 0, rdc = 0;
    const char **rie = nullptr, **rde = nullptr;
    NVSDK_NGX_Result nr = NVSDK_NGX_VULKAN_RequiredExtensions(&ric, &rie, &rdc, &rde);
    log_ngx("NVSDK_NGX_VULKAN_RequiredExtensions", nr);
    logf("required Vulkan extensions: instance=%u device=%u", ric, rdc);
    if (NVSDK_NGX_FAILED(nr)) return 0;

    VkFns vk;
    if (!vk.global()) { log_line("FAIL: Vulkan loader unavailable"); return 0; }

    uint32_t iec = 0;
    if (vk.EnumInstanceExt(nullptr, &iec, nullptr) != VK_SUCCESS) return 0;
    std::vector<VkExtensionProperties> ies(iec);
    if (vk.EnumInstanceExt(nullptr, &iec, ies.data()) != VK_SUCCESS) return 0;
    const auto ireq = dedupe(ric, rie);
    for (auto n : ireq)
    {
        logf("instance extension %s: %s", n, extension_present(n, ies) ? "OK" : "MISSING");
        if (!extension_present(n, ies)) return 0;
    }

    VkApplicationInfo ai{VK_STRUCTURE_TYPE_APPLICATION_INFO};
    ai.pApplicationName = "GTAIV DLFG Probe";
    ai.pEngineName = "private-probe";
    ai.apiVersion = VK_API_VERSION_1_2;
    VkInstanceCreateInfo ici{VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO};
    ici.pApplicationInfo = &ai;
    ici.enabledExtensionCount = static_cast<uint32_t>(ireq.size());
    ici.ppEnabledExtensionNames = ireq.empty() ? nullptr : ireq.data();
    VkInstance instance = VK_NULL_HANDLE;
    VkResult vr = vk.CreateInstance(&ici, nullptr, &instance);
    logf("vkCreateInstance -> %d", static_cast<int>(vr));
    if (vr != VK_SUCCESS || !vk.instance(instance)) return 0;

    uint32_t pc = 0;
    vk.EnumPhysical(instance, &pc, nullptr);
    std::vector<VkPhysicalDevice> pds(pc);
    vk.EnumPhysical(instance, &pc, pds.data());
    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties pp{};
    for (auto p : pds)
    {
        VkPhysicalDeviceProperties x{};
        vk.GetProps(p, &x);
        logf("GPU candidate: vendor=%04X device=%04X name=%s", x.vendorID, x.deviceID, x.deviceName);
        if (!physical && x.vendorID == 0x10DE) { physical = p; pp = x; }
    }
    if (!physical) { log_line("FAIL: NVIDIA GPU not found"); vk.DestroyInstance(instance, nullptr); return 0; }
    logf("selected GPU: %s", pp.deviceName);

    const int hags = hags_status(vk, physical);
    logf("Hardware-accelerated GPU scheduling (HAGS): %s", hags == 1 ? "ENABLED" : hags == 0 ? "DISABLED" : "UNKNOWN");

    const wchar_t *paths[] = {dir.c_str(), L"."};
    NVSDK_NGX_FeatureCommonInfo common{};
    common.PathListInfo.Path = paths;
    common.PathListInfo.Length = 2;
    common.LoggingInfo.LoggingCallback = &ngx_log_callback;
    common.LoggingInfo.MinimumLoggingLevel = NVSDK_NGX_LOGGING_LEVEL_VERBOSE;
    common.LoggingInfo.DisableOtherLoggingSinks = false;

    NVSDK_NGX_FeatureDiscoveryInfo di{};
    di.SDKVersion = NVSDK_NGX_Version_API;
    di.FeatureID = NVSDK_NGX_Feature_FrameGeneration;
    di.Identifier.IdentifierType = NVSDK_NGX_Application_Identifier_Type_Application_Id;
    di.Identifier.v.ApplicationId = kAppId;
    di.ApplicationDataPath = dir.c_str();
    di.FeatureInfo = &common;
    NVSDK_NGX_FeatureRequirement req{};
    nr = NVSDK_NGX_VULKAN_GetFeatureRequirements(instance, physical, &di, &req);
    log_ngx("NVSDK_NGX_VULKAN_GetFeatureRequirements(FrameGeneration)", nr);
    logf("FeatureRequirements: supportBits=%u minHW=0x%X minOS=%s", static_cast<unsigned int>(req.FeatureSupported), req.MinHWArchitecture, req.MinOSVersion);

    uint32_t qcount = 0;
    vk.GetQueues(physical, &qcount, nullptr);
    std::vector<VkQueueFamilyProperties> qps(qcount);
    vk.GetQueues(physical, &qcount, qps.data());
    uint32_t qfam = UINT32_MAX;
    for (uint32_t i = 0; i < qcount; ++i)
        if ((qps[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) && qps[i].queueCount) { qfam = i; break; }
    if (qfam == UINT32_MAX) { log_line("FAIL: no graphics queue"); vk.DestroyInstance(instance, nullptr); return 0; }

    uint32_t dec = 0;
    vk.EnumDeviceExt(physical, nullptr, &dec, nullptr);
    std::vector<VkExtensionProperties> des(dec);
    vk.EnumDeviceExt(physical, nullptr, &dec, des.data());
    const auto dreq = dedupe(rdc, rde);
    for (auto n : dreq)
    {
        logf("device extension %s: %s", n, extension_present(n, des) ? "OK" : "MISSING");
        if (!extension_present(n, des)) { vk.DestroyInstance(instance, nullptr); return 0; }
    }

    VkPhysicalDeviceFeatures core{};
    vk.GetFeatures(physical, &core);
    logf("core features: shaderInt64=%u storageImageReadWOFormat=%u storageImageWriteWOFormat=%u",
        core.shaderInt64, core.shaderStorageImageReadWithoutFormat, core.shaderStorageImageWriteWithoutFormat);

    VkPhysicalDeviceBufferDeviceAddressFeaturesEXT bda{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_BUFFER_DEVICE_ADDRESS_FEATURES_EXT};
    VkPhysicalDeviceFeatures2 f2{VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2};
    f2.pNext = &bda;
    vk.GetFeatures2(physical, &f2);
    logf("bufferDeviceAddress EXT feature: address=%u captureReplay=%u multiDevice=%u",
        bda.bufferDeviceAddress, bda.bufferDeviceAddressCaptureReplay, bda.bufferDeviceAddressMultiDevice);

    const float prio = 1.0f;
    VkDeviceQueueCreateInfo qci{VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO};
    qci.queueFamilyIndex = qfam; qci.queueCount = 1; qci.pQueuePriorities = &prio;
    VkDeviceCreateInfo dci{VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO};
    dci.queueCreateInfoCount = 1; dci.pQueueCreateInfos = &qci;
    dci.enabledExtensionCount = static_cast<uint32_t>(dreq.size());
    dci.ppEnabledExtensionNames = dreq.empty() ? nullptr : dreq.data();
    dci.pEnabledFeatures = &core;
    dci.pNext = bda.bufferDeviceAddress ? &bda : nullptr;

    VkDevice device = VK_NULL_HANDLE;
    vr = vk.CreateDevice(physical, &dci, nullptr, &device);
    logf("vkCreateDevice(private, supported core features + BDA) -> %d", static_cast<int>(vr));
    if (vr != VK_SUCCESS || !vk.device(device)) { vk.DestroyInstance(instance, nullptr); return 0; }

    VkQueue queue = VK_NULL_HANDLE;
    vk.GetQueue(device, qfam, 0, &queue);
    NVSDK_NGX_Parameter *params = nullptr;
    NVSDK_NGX_Handle *feature = nullptr;
    VkCommandPool pool = VK_NULL_HANDLE;
    bool ngx_init = false;

    auto cleanup = [&]() {
        if (feature) { log_ngx("NVSDK_NGX_VULKAN_ReleaseFeature", NVSDK_NGX_VULKAN_ReleaseFeature(feature)); feature = nullptr; }
        if (params) { log_ngx("NVSDK_NGX_VULKAN_DestroyParameters", NVSDK_NGX_VULKAN_DestroyParameters(params)); params = nullptr; }
        if (ngx_init) { log_ngx("NVSDK_NGX_VULKAN_Shutdown1", NVSDK_NGX_VULKAN_Shutdown1(device)); ngx_init = false; }
        if (pool) vk.DestroyPool(device, pool, nullptr);
        vk.DestroyDevice(device, nullptr);
        vk.DestroyInstance(instance, nullptr);
        log_line("probe cleanup complete");
    };

    nr = NVSDK_NGX_VULKAN_Init(kAppId, dir.c_str(), instance, physical, device, vk.gipa, vk.gdpa, &common);
    log_ngx("NVSDK_NGX_VULKAN_Init", nr);
    if (NVSDK_NGX_FAILED(nr)) { cleanup(); return 0; }
    ngx_init = true;

    nr = NVSDK_NGX_VULKAN_GetCapabilityParameters(&params);
    log_ngx("NVSDK_NGX_VULKAN_GetCapabilityParameters", nr);
    if (NVSDK_NGX_FAILED(nr) || !params) { cleanup(); return 0; }

    int available = 0, needs_driver = 0, max_frames = 0;
    NVSDK_NGX_Result q1 = params->Get(NVSDK_NGX_Parameter_FrameGeneration_Available, &available);
    NVSDK_NGX_Result q2 = params->Get(NVSDK_NGX_Parameter_FrameGeneration_NeedsUpdatedDriver, &needs_driver);
    NVSDK_NGX_Result q3 = params->Get(NVSDK_NGX_DLSSG_Parameter_MultiFrameCountMax, &max_frames);
    logf("FrameGeneration.Available: 0x%08X value=%d", static_cast<unsigned int>(q1), available);
    logf("FrameGeneration.NeedsUpdatedDriver: 0x%08X value=%d", static_cast<unsigned int>(q2), needs_driver);
    logf("DLSSG.MultiFrameCountMax: 0x%08X value=%d", static_cast<unsigned int>(q3), max_frames);

    VkCommandPoolCreateInfo pci{VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO};
    pci.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT | VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
    pci.queueFamilyIndex = qfam;
    vr = vk.CreatePool(device, &pci, nullptr, &pool);
    logf("vkCreateCommandPool -> %d", static_cast<int>(vr));
    if (vr != VK_SUCCESS) { cleanup(); return 0; }

    VkCommandBufferAllocateInfo cai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};
    cai.commandPool = pool; cai.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; cai.commandBufferCount = 1;
    VkCommandBuffer cmd = VK_NULL_HANDLE;
    vr = vk.AllocCmd(device, &cai, &cmd);
    logf("vkAllocateCommandBuffers -> %d", static_cast<int>(vr));
    if (vr != VK_SUCCESS) { cleanup(); return 0; }
    VkCommandBufferBeginInfo cbi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};
    cbi.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    vr = vk.BeginCmd(cmd, &cbi);
    logf("vkBeginCommandBuffer -> %d", static_cast<int>(vr));
    if (vr != VK_SUCCESS) { cleanup(); return 0; }

    struct FormatTry { VkFormat format; const char *name; } tries[] = {
        {VK_FORMAT_B8G8R8A8_UNORM, "B8G8R8A8_UNORM"},
        {VK_FORMAT_R8G8B8A8_UNORM, "R8G8B8A8_UNORM"},
        {VK_FORMAT_R16G16B16A16_SFLOAT, "R16G16B16A16_SFLOAT"}
    };

    NVSDK_NGX_Result create_result = NVSDK_NGX_Result_Fail;
    const char *created_format = nullptr;
    for (const auto &t : tries)
    {
        NVSDK_NGX_DLSSG_Create_Params cp{};
        cp.Width = kWidth;
        cp.Height = kHeight;
        cp.NativeBackbufferFormat = static_cast<unsigned int>(t.format);
        cp.RenderWidth = kWidth;
        cp.RenderHeight = kHeight;
        cp.DynamicResolutionScaling = false;
        feature = nullptr;
        create_result = NGX_VK_CREATE_DLSSG(cmd, 1, 1, &feature, params, &cp);
        logf("NGX_VK_CREATE_DLSSG(%ux%u %s) -> 0x%08X (%s) feature=%p",
            kWidth, kHeight, t.name, static_cast<unsigned int>(create_result), ngx_name(create_result), feature);
        if (!NVSDK_NGX_FAILED(create_result) && feature)
        {
            created_format = t.name;
            break;
        }
    }

    vr = vk.EndCmd(cmd);
    logf("vkEndCommandBuffer -> %d", static_cast<int>(vr));
    if (!created_format || vr != VK_SUCCESS)
    {
        log_line("MILESTONE 1.1 NOT YET PASSED: capability is visible, but DLFG feature creation still failed.");
        cleanup();
        return 0;
    }

    VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO};
    si.commandBufferCount = 1; si.pCommandBuffers = &cmd;
    vr = vk.QueueSubmit(queue, 1, &si, VK_NULL_HANDLE);
    logf("vkQueueSubmit(feature-create work) -> %d", static_cast<int>(vr));
    if (vr == VK_SUCCESS) vr = vk.QueueWaitIdle(queue);
    logf("vkQueueWaitIdle -> %d", static_cast<int>(vr));

    if (vr == VK_SUCCESS)
    {
        logf("SUCCESS: NVIDIA NGX DLSS Frame Generation feature created using %s.", created_format);
        log_line("MILESTONE 1 PASSED. Next target is an off-screen interpolated frame on the live render device.");
    }

    cleanup();
    return 0;
}

void on_init_effect_runtime(reshade::api::effect_runtime *runtime)
{
    bool expected = false;
    if (!g_started.compare_exchange_strong(expected, true)) return;
    logf("ReShade runtime observed in host; runtime=%p hwnd=%p", runtime, runtime ? runtime->get_hwnd() : nullptr);
    HANDLE t = CreateThread(nullptr, 0, probe_worker, nullptr, 0, nullptr);
    if (t) CloseHandle(t); else { g_started.store(false); logf("FAIL: CreateThread error=%lu", GetLastError()); }
}
}

extern "C" __declspec(dllexport) const char *NAME = "GTA IV DLFG Probe";
extern "C" __declspec(dllexport) const char *DESCRIPTION =
    "Experimental DLFG milestone-1.1 probe with HAGS, feature-requirement, Vulkan-device-feature, NGX callback and format diagnostics.";

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_module = hModule;
        DisableThreadLibraryCalls(hModule);
        if (!reshade::register_addon(hModule)) return FALSE;
        reshade::register_event<reshade::addon_event::init_effect_runtime>(on_init_effect_runtime);
    }
    else if (reason == DLL_PROCESS_DETACH)
        reshade::unregister_addon(hModule);
    return TRUE;
}
