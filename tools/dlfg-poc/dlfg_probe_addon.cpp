#define WIN32_LEAN_AND_MEAN
#include <windows.h>

#include <reshade.hpp>

#include <vulkan/vulkan.h>

#include <nvsdk_ngx.h>
#include <nvsdk_ngx_vk.h>
#include <nvsdk_ngx_defs_dlssg.h>
#include <nvsdk_ngx_helpers_dlssg.h>
#include <nvsdk_ngx_helpers_dlssg_vk.h>

#include <algorithm>
#include <atomic>
#include <cstdint>
#include <cstdio>
#include <mutex>
#include <set>
#include <string>
#include <vector>

namespace
{
HMODULE g_module = nullptr;
std::atomic<bool> g_probe_started = false;
std::mutex g_log_mutex;

constexpr unsigned long long kRemixReferenceApplicationId = 102100511ull;
constexpr uint32_t kProbeWidth = 2560;
constexpr uint32_t kProbeHeight = 1440;

std::wstring module_directory()
{
    wchar_t path[MAX_PATH] = {};
    GetModuleFileNameW(g_module, path, MAX_PATH);
    std::wstring s(path);
    const size_t slash = s.find_last_of(L"\\/");
    return slash == std::wstring::npos ? L"." : s.substr(0, slash);
}

void log_line(const char *text)
{
    std::lock_guard<std::mutex> lock(g_log_mutex);

    const std::wstring path = module_directory() + L"\\dlfg-probe.log";
    HANDLE file = CreateFileW(path.c_str(), FILE_APPEND_DATA,
        FILE_SHARE_READ | FILE_SHARE_WRITE, nullptr, OPEN_ALWAYS,
        FILE_ATTRIBUTE_NORMAL, nullptr);
    if (file == INVALID_HANDLE_VALUE)
        return;

    SYSTEMTIME st = {};
    GetLocalTime(&st);

    char line[2048] = {};
    const int n = std::snprintf(line, sizeof(line),
        "%02u:%02u:%02u.%03u  %s\r\n",
        st.wHour, st.wMinute, st.wSecond, st.wMilliseconds, text);

    if (n > 0)
    {
        DWORD written = 0;
        WriteFile(file, line, static_cast<DWORD>(n), &written, nullptr);
    }
    CloseHandle(file);
}

void logf(const char *fmt, ...)
{
    char buf[1800] = {};
    va_list ap;
    va_start(ap, fmt);
    std::vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    log_line(buf);
}

const char *ngx_result_hex(NVSDK_NGX_Result result, char (&buf)[32])
{
    std::snprintf(buf, sizeof(buf), "0x%08X", static_cast<unsigned int>(result));
    return buf;
}

bool file_exists(const std::wstring &path)
{
    const DWORD attr = GetFileAttributesW(path.c_str());
    return attr != INVALID_FILE_ATTRIBUTES && (attr & FILE_ATTRIBUTE_DIRECTORY) == 0;
}

struct VulkanLoader
{
    HMODULE module = nullptr;
    PFN_vkGetInstanceProcAddr GetInstanceProcAddr = nullptr;
    PFN_vkGetDeviceProcAddr GetDeviceProcAddr = nullptr;

    PFN_vkCreateInstance CreateInstance = nullptr;
    PFN_vkEnumerateInstanceExtensionProperties EnumerateInstanceExtensionProperties = nullptr;

    PFN_vkDestroyInstance DestroyInstance = nullptr;
    PFN_vkEnumeratePhysicalDevices EnumeratePhysicalDevices = nullptr;
    PFN_vkGetPhysicalDeviceProperties GetPhysicalDeviceProperties = nullptr;
    PFN_vkGetPhysicalDeviceQueueFamilyProperties GetPhysicalDeviceQueueFamilyProperties = nullptr;
    PFN_vkEnumerateDeviceExtensionProperties EnumerateDeviceExtensionProperties = nullptr;
    PFN_vkCreateDevice CreateDevice = nullptr;

    PFN_vkDestroyDevice DestroyDevice = nullptr;
    PFN_vkGetDeviceQueue GetDeviceQueue = nullptr;
    PFN_vkCreateCommandPool CreateCommandPool = nullptr;
    PFN_vkDestroyCommandPool DestroyCommandPool = nullptr;
    PFN_vkAllocateCommandBuffers AllocateCommandBuffers = nullptr;
    PFN_vkBeginCommandBuffer BeginCommandBuffer = nullptr;
    PFN_vkEndCommandBuffer EndCommandBuffer = nullptr;
    PFN_vkQueueSubmit QueueSubmit = nullptr;
    PFN_vkQueueWaitIdle QueueWaitIdle = nullptr;

    bool load_global()
    {
        module = LoadLibraryW(L"vulkan-1.dll");
        if (!module)
        {
            logf("FAIL: LoadLibrary(vulkan-1.dll) error=%lu", GetLastError());
            return false;
        }

        GetInstanceProcAddr = reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(module, "vkGetInstanceProcAddr"));
        if (!GetInstanceProcAddr)
        {
            log_line("FAIL: vkGetInstanceProcAddr export missing");
            return false;
        }

        CreateInstance = reinterpret_cast<PFN_vkCreateInstance>(GetInstanceProcAddr(VK_NULL_HANDLE, "vkCreateInstance"));
        EnumerateInstanceExtensionProperties = reinterpret_cast<PFN_vkEnumerateInstanceExtensionProperties>(GetInstanceProcAddr(VK_NULL_HANDLE, "vkEnumerateInstanceExtensionProperties"));
        return CreateInstance && EnumerateInstanceExtensionProperties;
    }

    bool load_instance(VkInstance instance)
    {
        DestroyInstance = reinterpret_cast<PFN_vkDestroyInstance>(GetInstanceProcAddr(instance, "vkDestroyInstance"));
        EnumeratePhysicalDevices = reinterpret_cast<PFN_vkEnumeratePhysicalDevices>(GetInstanceProcAddr(instance, "vkEnumeratePhysicalDevices"));
        GetPhysicalDeviceProperties = reinterpret_cast<PFN_vkGetPhysicalDeviceProperties>(GetInstanceProcAddr(instance, "vkGetPhysicalDeviceProperties"));
        GetPhysicalDeviceQueueFamilyProperties = reinterpret_cast<PFN_vkGetPhysicalDeviceQueueFamilyProperties>(GetInstanceProcAddr(instance, "vkGetPhysicalDeviceQueueFamilyProperties"));
        EnumerateDeviceExtensionProperties = reinterpret_cast<PFN_vkEnumerateDeviceExtensionProperties>(GetInstanceProcAddr(instance, "vkEnumerateDeviceExtensionProperties"));
        CreateDevice = reinterpret_cast<PFN_vkCreateDevice>(GetInstanceProcAddr(instance, "vkCreateDevice"));
        GetDeviceProcAddr = reinterpret_cast<PFN_vkGetDeviceProcAddr>(GetInstanceProcAddr(instance, "vkGetDeviceProcAddr"));

        return DestroyInstance && EnumeratePhysicalDevices && GetPhysicalDeviceProperties &&
            GetPhysicalDeviceQueueFamilyProperties && EnumerateDeviceExtensionProperties &&
            CreateDevice && GetDeviceProcAddr;
    }

    bool load_device(VkDevice device)
    {
        DestroyDevice = reinterpret_cast<PFN_vkDestroyDevice>(GetDeviceProcAddr(device, "vkDestroyDevice"));
        GetDeviceQueue = reinterpret_cast<PFN_vkGetDeviceQueue>(GetDeviceProcAddr(device, "vkGetDeviceQueue"));
        CreateCommandPool = reinterpret_cast<PFN_vkCreateCommandPool>(GetDeviceProcAddr(device, "vkCreateCommandPool"));
        DestroyCommandPool = reinterpret_cast<PFN_vkDestroyCommandPool>(GetDeviceProcAddr(device, "vkDestroyCommandPool"));
        AllocateCommandBuffers = reinterpret_cast<PFN_vkAllocateCommandBuffers>(GetDeviceProcAddr(device, "vkAllocateCommandBuffers"));
        BeginCommandBuffer = reinterpret_cast<PFN_vkBeginCommandBuffer>(GetDeviceProcAddr(device, "vkBeginCommandBuffer"));
        EndCommandBuffer = reinterpret_cast<PFN_vkEndCommandBuffer>(GetDeviceProcAddr(device, "vkEndCommandBuffer"));
        QueueSubmit = reinterpret_cast<PFN_vkQueueSubmit>(GetDeviceProcAddr(device, "vkQueueSubmit"));
        QueueWaitIdle = reinterpret_cast<PFN_vkQueueWaitIdle>(GetDeviceProcAddr(device, "vkQueueWaitIdle"));

        return DestroyDevice && GetDeviceQueue && CreateCommandPool && DestroyCommandPool &&
            AllocateCommandBuffers && BeginCommandBuffer && EndCommandBuffer && QueueSubmit && QueueWaitIdle;
    }

    ~VulkanLoader()
    {
        if (module)
            FreeLibrary(module);
    }
};

bool extension_present(const char *name, const std::vector<VkExtensionProperties> &available)
{
    for (const auto &ext : available)
        if (std::strcmp(name, ext.extensionName) == 0)
            return true;
    return false;
}

std::vector<const char *> dedupe_extensions(unsigned int count, const char **extensions)
{
    std::vector<const char *> result;
    std::set<std::string> seen;
    for (unsigned int i = 0; i < count; ++i)
    {
        if (extensions[i] != nullptr && seen.insert(extensions[i]).second)
            result.push_back(extensions[i]);
    }
    return result;
}

DWORD WINAPI probe_worker(LPVOID)
{
    // Let ReShade, Feeder and DFC finish their startup work before opening a second, private Vulkan device.
    Sleep(2500);

    log_line("============================================================");
    log_line("DLFG POC milestone 1: private Vulkan/NGX capability + feature-create probe");
    log_line("This build does NOT present generated frames and does NOT modify the game swapchain.");

    const std::wstring dir = module_directory();
    const std::wstring dlssg_path = dir + L"\\nvngx_dlssg.dll";
    if (!file_exists(dlssg_path))
    {
        log_line("FAIL: nvngx_dlssg.dll is missing next to dlfg-probe.addon64");
        log_line("Run GET-RUNTIME.bat, then launch GTA IV again.");
        return 0;
    }
    log_line("runtime: nvngx_dlssg.dll found next to the add-on");

    unsigned int required_instance_count = 0;
    unsigned int required_device_count = 0;
    const char **required_instance = nullptr;
    const char **required_device = nullptr;

    NVSDK_NGX_Result ngx = NVSDK_NGX_VULKAN_RequiredExtensions(
        &required_instance_count, &required_instance,
        &required_device_count, &required_device);

    char ngx_buf[32] = {};
    logf("NVSDK_NGX_VULKAN_RequiredExtensions -> %s; instance=%u device=%u",
        ngx_result_hex(ngx, ngx_buf), required_instance_count, required_device_count);
    if (NVSDK_NGX_FAILED(ngx))
        return 0;

    VulkanLoader vk;
    if (!vk.load_global())
        return 0;

    uint32_t instance_ext_count = 0;
    if (vk.EnumerateInstanceExtensionProperties(nullptr, &instance_ext_count, nullptr) != VK_SUCCESS)
    {
        log_line("FAIL: vkEnumerateInstanceExtensionProperties(count)");
        return 0;
    }
    std::vector<VkExtensionProperties> instance_exts(instance_ext_count);
    if (vk.EnumerateInstanceExtensionProperties(nullptr, &instance_ext_count, instance_exts.data()) != VK_SUCCESS)
    {
        log_line("FAIL: vkEnumerateInstanceExtensionProperties(list)");
        return 0;
    }

    const std::vector<const char *> instance_extensions = dedupe_extensions(required_instance_count, required_instance);
    for (const char *name : instance_extensions)
    {
        if (!extension_present(name, instance_exts))
        {
            logf("FAIL: required Vulkan instance extension missing: %s", name);
            return 0;
        }
        logf("instance extension OK: %s", name);
    }

    VkApplicationInfo app_info { VK_STRUCTURE_TYPE_APPLICATION_INFO };
    app_info.pApplicationName = "GTAIV DLFG Probe";
    app_info.applicationVersion = 1;
    app_info.pEngineName = "private-probe";
    app_info.engineVersion = 1;
    app_info.apiVersion = VK_API_VERSION_1_2;

    VkInstanceCreateInfo instance_ci { VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO };
    instance_ci.pApplicationInfo = &app_info;
    instance_ci.enabledExtensionCount = static_cast<uint32_t>(instance_extensions.size());
    instance_ci.ppEnabledExtensionNames = instance_extensions.empty() ? nullptr : instance_extensions.data();

    VkInstance instance = VK_NULL_HANDLE;
    VkResult vr = vk.CreateInstance(&instance_ci, nullptr, &instance);
    logf("vkCreateInstance -> %d", static_cast<int>(vr));
    if (vr != VK_SUCCESS)
        return 0;

    if (!vk.load_instance(instance))
    {
        log_line("FAIL: could not load Vulkan instance functions");
        vk.DestroyInstance(instance, nullptr);
        return 0;
    }

    uint32_t gpu_count = 0;
    vr = vk.EnumeratePhysicalDevices(instance, &gpu_count, nullptr);
    if (vr != VK_SUCCESS || gpu_count == 0)
    {
        logf("FAIL: vkEnumeratePhysicalDevices count result=%d count=%u", static_cast<int>(vr), gpu_count);
        vk.DestroyInstance(instance, nullptr);
        return 0;
    }

    std::vector<VkPhysicalDevice> gpus(gpu_count);
    vr = vk.EnumeratePhysicalDevices(instance, &gpu_count, gpus.data());
    if (vr != VK_SUCCESS)
    {
        logf("FAIL: vkEnumeratePhysicalDevices list result=%d", static_cast<int>(vr));
        vk.DestroyInstance(instance, nullptr);
        return 0;
    }

    VkPhysicalDevice physical = VK_NULL_HANDLE;
    VkPhysicalDeviceProperties physical_props {};
    for (VkPhysicalDevice candidate : gpus)
    {
        VkPhysicalDeviceProperties props {};
        vk.GetPhysicalDeviceProperties(candidate, &props);
        logf("GPU candidate: vendor=%04X device=%04X name=%s", props.vendorID, props.deviceID, props.deviceName);
        if (physical == VK_NULL_HANDLE && props.vendorID == 0x10DE)
        {
            physical = candidate;
            physical_props = props;
        }
    }

    if (physical == VK_NULL_HANDLE)
    {
        log_line("FAIL: no NVIDIA Vulkan physical device found");
        vk.DestroyInstance(instance, nullptr);
        return 0;
    }
    logf("selected GPU: %s (vendor=%04X device=%04X)", physical_props.deviceName, physical_props.vendorID, physical_props.deviceID);

    uint32_t queue_count = 0;
    vk.GetPhysicalDeviceQueueFamilyProperties(physical, &queue_count, nullptr);
    std::vector<VkQueueFamilyProperties> queue_props(queue_count);
    vk.GetPhysicalDeviceQueueFamilyProperties(physical, &queue_count, queue_props.data());

    uint32_t graphics_family = UINT32_MAX;
    for (uint32_t i = 0; i < queue_count; ++i)
    {
        if ((queue_props[i].queueFlags & VK_QUEUE_GRAPHICS_BIT) != 0 && queue_props[i].queueCount != 0)
        {
            graphics_family = i;
            break;
        }
    }
    if (graphics_family == UINT32_MAX)
    {
        log_line("FAIL: no Vulkan graphics queue family found");
        vk.DestroyInstance(instance, nullptr);
        return 0;
    }
    logf("graphics queue family=%u", graphics_family);

    uint32_t device_ext_count = 0;
    vr = vk.EnumerateDeviceExtensionProperties(physical, nullptr, &device_ext_count, nullptr);
    if (vr != VK_SUCCESS)
    {
        logf("FAIL: vkEnumerateDeviceExtensionProperties(count) -> %d", static_cast<int>(vr));
        vk.DestroyInstance(instance, nullptr);
        return 0;
    }
    std::vector<VkExtensionProperties> device_exts(device_ext_count);
    vr = vk.EnumerateDeviceExtensionProperties(physical, nullptr, &device_ext_count, device_exts.data());
    if (vr != VK_SUCCESS)
    {
        logf("FAIL: vkEnumerateDeviceExtensionProperties(list) -> %d", static_cast<int>(vr));
        vk.DestroyInstance(instance, nullptr);
        return 0;
    }

    const std::vector<const char *> device_extensions = dedupe_extensions(required_device_count, required_device);
    for (const char *name : device_extensions)
    {
        if (!extension_present(name, device_exts))
        {
            logf("FAIL: required Vulkan device extension missing: %s", name);
            vk.DestroyInstance(instance, nullptr);
            return 0;
        }
        logf("device extension OK: %s", name);
    }

    const float priority = 1.0f;
    VkDeviceQueueCreateInfo queue_ci { VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO };
    queue_ci.queueFamilyIndex = graphics_family;
    queue_ci.queueCount = 1;
    queue_ci.pQueuePriorities = &priority;

    VkDeviceCreateInfo device_ci { VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO };
    device_ci.queueCreateInfoCount = 1;
    device_ci.pQueueCreateInfos = &queue_ci;
    device_ci.enabledExtensionCount = static_cast<uint32_t>(device_extensions.size());
    device_ci.ppEnabledExtensionNames = device_extensions.empty() ? nullptr : device_extensions.data();

    VkDevice device = VK_NULL_HANDLE;
    vr = vk.CreateDevice(physical, &device_ci, nullptr, &device);
    logf("vkCreateDevice(private probe) -> %d", static_cast<int>(vr));
    if (vr != VK_SUCCESS)
    {
        vk.DestroyInstance(instance, nullptr);
        return 0;
    }

    if (!vk.load_device(device))
    {
        log_line("FAIL: could not load Vulkan device functions");
        vk.DestroyDevice(device, nullptr);
        vk.DestroyInstance(instance, nullptr);
        return 0;
    }

    VkQueue queue = VK_NULL_HANDLE;
    vk.GetDeviceQueue(device, graphics_family, 0, &queue);

    bool ngx_initialized = false;
    NVSDK_NGX_Parameter *params = nullptr;
    NVSDK_NGX_Handle *feature = nullptr;
    VkCommandPool command_pool = VK_NULL_HANDLE;

    ngx = NVSDK_NGX_VULKAN_Init(kRemixReferenceApplicationId, dir.c_str(), instance, physical, device);
    logf("NVSDK_NGX_VULKAN_Init(appId=%llu) -> %s", kRemixReferenceApplicationId, ngx_result_hex(ngx, ngx_buf));
    if (NVSDK_NGX_FAILED(ngx))
        goto cleanup;
    ngx_initialized = true;

    ngx = NVSDK_NGX_VULKAN_GetCapabilityParameters(&params);
    logf("NVSDK_NGX_VULKAN_GetCapabilityParameters -> %s params=%p", ngx_result_hex(ngx, ngx_buf), params);
    if (NVSDK_NGX_FAILED(ngx) || params == nullptr)
        goto cleanup;

    {
        int available = 0;
        NVSDK_NGX_Result r = params->Get(NVSDK_NGX_Parameter_FrameGeneration_Available, &available);
        logf("FrameGeneration.Available: query=%s value=%d", ngx_result_hex(r, ngx_buf), available);
        if (NVSDK_NGX_FAILED(r) || available == 0)
        {
            log_line("FAIL: NGX reports Frame Generation unavailable. Check RTX 40/50 support, current driver, and Hardware-accelerated GPU scheduling (HAGS).");
            goto cleanup;
        }
    }

    {
        int needs_driver = 0;
        NVSDK_NGX_Result r = params->Get(NVSDK_NGX_Parameter_FrameGeneration_NeedsUpdatedDriver, &needs_driver);
        logf("FrameGeneration.NeedsUpdatedDriver: query=%s value=%d", ngx_result_hex(r, ngx_buf), needs_driver);
        if (!NVSDK_NGX_FAILED(r) && needs_driver)
        {
            unsigned int major = 0, minor = 0;
            params->Get(NVSDK_NGX_Parameter_FrameGeneration_MinDriverVersionMajor, &major);
            params->Get(NVSDK_NGX_Parameter_FrameGeneration_MinDriverVersionMinor, &minor);
            logf("FAIL: driver update required; NGX minimum reported %u.%u", major, minor);
            goto cleanup;
        }
    }

    {
        int max_interpolated = 0;
        NVSDK_NGX_Result r = params->Get(NVSDK_NGX_DLSSG_Parameter_MultiFrameCountMax, &max_interpolated);
        logf("DLSSG.MultiFrameCountMax: query=%s value=%d", ngx_result_hex(r, ngx_buf), max_interpolated);
    }

    {
        VkCommandPoolCreateInfo pool_ci { VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO };
        pool_ci.flags = VK_COMMAND_POOL_CREATE_TRANSIENT_BIT | VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT;
        pool_ci.queueFamilyIndex = graphics_family;
        vr = vk.CreateCommandPool(device, &pool_ci, nullptr, &command_pool);
        logf("vkCreateCommandPool -> %d", static_cast<int>(vr));
        if (vr != VK_SUCCESS)
            goto cleanup;

        VkCommandBufferAllocateInfo alloc { VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO };
        alloc.commandPool = command_pool;
        alloc.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY;
        alloc.commandBufferCount = 1;
        VkCommandBuffer cmd = VK_NULL_HANDLE;
        vr = vk.AllocateCommandBuffers(device, &alloc, &cmd);
        logf("vkAllocateCommandBuffers -> %d", static_cast<int>(vr));
        if (vr != VK_SUCCESS)
            goto cleanup;

        VkCommandBufferBeginInfo begin { VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO };
        begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
        vr = vk.BeginCommandBuffer(cmd, &begin);
        logf("vkBeginCommandBuffer -> %d", static_cast<int>(vr));
        if (vr != VK_SUCCESS)
            goto cleanup;

        NVSDK_NGX_DLSSG_Create_Params create_params {};
        create_params.Width = kProbeWidth;
        create_params.Height = kProbeHeight;
        create_params.NativeBackbufferFormat = VK_FORMAT_B8G8R8A8_UNORM;

        ngx = NGX_VK_CREATE_DLSSG(cmd, 1, 1, &feature, params, &create_params);
        logf("NGX_VK_CREATE_DLSSG(%ux%u B8G8R8A8_UNORM) -> %s feature=%p",
            kProbeWidth, kProbeHeight, ngx_result_hex(ngx, ngx_buf), feature);

        vr = vk.EndCommandBuffer(cmd);
        logf("vkEndCommandBuffer -> %d", static_cast<int>(vr));
        if (NVSDK_NGX_FAILED(ngx) || feature == nullptr || vr != VK_SUCCESS)
            goto cleanup;

        VkSubmitInfo submit { VK_STRUCTURE_TYPE_SUBMIT_INFO };
        submit.commandBufferCount = 1;
        submit.pCommandBuffers = &cmd;
        vr = vk.QueueSubmit(queue, 1, &submit, VK_NULL_HANDLE);
        logf("vkQueueSubmit(feature-create work) -> %d", static_cast<int>(vr));
        if (vr != VK_SUCCESS)
            goto cleanup;

        vr = vk.QueueWaitIdle(queue);
        logf("vkQueueWaitIdle -> %d", static_cast<int>(vr));
        if (vr != VK_SUCCESS)
            goto cleanup;
    }

    log_line("SUCCESS: NVIDIA NGX DLSS Frame Generation feature was created on the RTX GPU.");
    log_line("MILESTONE 1 PASSED. No generated frame was evaluated or presented by this POC.");

cleanup:
    if (feature != nullptr)
    {
        const NVSDK_NGX_Result r = NVSDK_NGX_VULKAN_ReleaseFeature(feature);
        logf("NVSDK_NGX_VULKAN_ReleaseFeature -> %s", ngx_result_hex(r, ngx_buf));
        feature = nullptr;
    }
    if (params != nullptr)
    {
        const NVSDK_NGX_Result r = NVSDK_NGX_VULKAN_DestroyParameters(params);
        logf("NVSDK_NGX_VULKAN_DestroyParameters -> %s", ngx_result_hex(r, ngx_buf));
        params = nullptr;
    }
    if (ngx_initialized)
    {
        const NVSDK_NGX_Result r = NVSDK_NGX_VULKAN_Shutdown1(device);
        logf("NVSDK_NGX_VULKAN_Shutdown1 -> %s", ngx_result_hex(r, ngx_buf));
    }
    if (command_pool != VK_NULL_HANDLE)
        vk.DestroyCommandPool(device, command_pool, nullptr);
    vk.DestroyDevice(device, nullptr);
    vk.DestroyInstance(instance, nullptr);
    log_line("probe cleanup complete");
    return 0;
}

void on_init_effect_runtime(reshade::api::effect_runtime *runtime)
{
    bool expected = false;
    if (!g_probe_started.compare_exchange_strong(expected, true))
        return;

    logf("ReShade runtime observed in host; runtime=%p hwnd=%p", runtime, runtime ? runtime->get_hwnd() : nullptr);

    HANDLE thread = CreateThread(nullptr, 0, probe_worker, nullptr, 0, nullptr);
    if (!thread)
    {
        g_probe_started.store(false);
        logf("FAIL: CreateThread error=%lu", GetLastError());
        return;
    }
    CloseHandle(thread);
}
} // namespace

extern "C" __declspec(dllexport) const char *NAME = "GTA IV DLFG Probe";
extern "C" __declspec(dllexport) const char *DESCRIPTION =
    "Experimental milestone-1 probe: creates a private Vulkan device, checks NVIDIA NGX DLSS Frame Generation support, and attempts to create a DLFG feature without presenting generated frames.";

BOOL APIENTRY DllMain(HMODULE hModule, DWORD reason, LPVOID)
{
    if (reason == DLL_PROCESS_ATTACH)
    {
        g_module = hModule;
        DisableThreadLibraryCalls(hModule);
        if (!reshade::register_addon(hModule))
            return FALSE;
        reshade::register_event<reshade::addon_event::init_effect_runtime>(on_init_effect_runtime);
    }
    else if (reason == DLL_PROCESS_DETACH)
    {
        reshade::unregister_addon(hModule);
    }
    return TRUE;
}
