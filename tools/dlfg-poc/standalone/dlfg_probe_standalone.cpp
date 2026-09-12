#define WIN32_LEAN_AND_MEAN
#define NOMINMAX
#include <windows.h>

#include <vulkan/vulkan.h>
#include <nvsdk_ngx.h>
#include <nvsdk_ngx_vk.h>
#include <nvsdk_ngx_defs_dlssg.h>
#include <nvsdk_ngx_helpers_vk.h>
#include <nvsdk_ngx_helpers_dlssg_vk.h>

#include <algorithm>
#include <cmath>
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
constexpr uint32_t kRectW = 160, kRectH = 160, kRectY = 640, kRectAX = 820, kRectBX = 900;

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
    // `vfprintf` requires a narrow-oriented stream; ccs=UTF-8 is Unicode-oriented.
    _wfopen_s(&f, path.c_str(), L"wb");
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
    PFN_vkGetPhysicalDeviceMemoryProperties getMemoryProps = nullptr;
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
    PFN_vkCreateImage createImage = nullptr; PFN_vkDestroyImage destroyImage = nullptr;
    PFN_vkGetImageMemoryRequirements getImageMemReq = nullptr; PFN_vkBindImageMemory bindImageMem = nullptr;
    PFN_vkCreateImageView createImageView = nullptr; PFN_vkDestroyImageView destroyImageView = nullptr;
    PFN_vkCreateBuffer createBuffer = nullptr; PFN_vkDestroyBuffer destroyBuffer = nullptr;
    PFN_vkGetBufferMemoryRequirements getBufferMemReq = nullptr; PFN_vkBindBufferMemory bindBufferMem = nullptr;
    PFN_vkAllocateMemory allocMemory = nullptr; PFN_vkFreeMemory freeMemory = nullptr;
    PFN_vkMapMemory mapMemory = nullptr; PFN_vkUnmapMemory unmapMemory = nullptr;
    PFN_vkCmdPipelineBarrier cmdBarrier = nullptr; PFN_vkCmdCopyBufferToImage cmdCopyB2I = nullptr; PFN_vkCmdCopyImageToBuffer cmdCopyI2B = nullptr;

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
        getMemoryProps = reinterpret_cast<PFN_vkGetPhysicalDeviceMemoryProperties>(gipa(instance, "vkGetPhysicalDeviceMemoryProperties"));
        createDevice = reinterpret_cast<PFN_vkCreateDevice>(gipa(instance, "vkCreateDevice"));
        gdpa = reinterpret_cast<PFN_vkGetDeviceProcAddr>(gipa(instance, "vkGetDeviceProcAddr"));
        return destroyInstance && enumPhysical && getPhysicalProps && getQueueProps && enumDeviceExt && getMemoryProps && createDevice && gdpa;
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
        createImage = reinterpret_cast<PFN_vkCreateImage>(gdpa(device, "vkCreateImage")); destroyImage = reinterpret_cast<PFN_vkDestroyImage>(gdpa(device, "vkDestroyImage")); getImageMemReq = reinterpret_cast<PFN_vkGetImageMemoryRequirements>(gdpa(device, "vkGetImageMemoryRequirements")); bindImageMem = reinterpret_cast<PFN_vkBindImageMemory>(gdpa(device, "vkBindImageMemory")); createImageView = reinterpret_cast<PFN_vkCreateImageView>(gdpa(device, "vkCreateImageView")); destroyImageView = reinterpret_cast<PFN_vkDestroyImageView>(gdpa(device, "vkDestroyImageView")); createBuffer = reinterpret_cast<PFN_vkCreateBuffer>(gdpa(device, "vkCreateBuffer")); destroyBuffer = reinterpret_cast<PFN_vkDestroyBuffer>(gdpa(device, "vkDestroyBuffer")); getBufferMemReq = reinterpret_cast<PFN_vkGetBufferMemoryRequirements>(gdpa(device, "vkGetBufferMemoryRequirements")); bindBufferMem = reinterpret_cast<PFN_vkBindBufferMemory>(gdpa(device, "vkBindBufferMemory")); allocMemory = reinterpret_cast<PFN_vkAllocateMemory>(gdpa(device, "vkAllocateMemory")); freeMemory = reinterpret_cast<PFN_vkFreeMemory>(gdpa(device, "vkFreeMemory")); mapMemory = reinterpret_cast<PFN_vkMapMemory>(gdpa(device, "vkMapMemory")); unmapMemory = reinterpret_cast<PFN_vkUnmapMemory>(gdpa(device, "vkUnmapMemory")); cmdBarrier = reinterpret_cast<PFN_vkCmdPipelineBarrier>(gdpa(device, "vkCmdPipelineBarrier")); cmdCopyB2I = reinterpret_cast<PFN_vkCmdCopyBufferToImage>(gdpa(device, "vkCmdCopyBufferToImage")); cmdCopyI2B = reinterpret_cast<PFN_vkCmdCopyImageToBuffer>(gdpa(device, "vkCmdCopyImageToBuffer"));
        return destroyDevice && getQueue && createCommandPool && destroyCommandPool && allocCommandBuffers && beginCommandBuffer && endCommandBuffer && queueSubmit && queueWaitIdle && createImage && destroyImage && getImageMemReq && bindImageMem && createImageView && destroyImageView && createBuffer && destroyBuffer && getBufferMemReq && bindBufferMem && allocMemory && freeMemory && mapMemory && unmapMemory && cmdBarrier && cmdCopyB2I && cmdCopyI2B;
    }

    ~VkFns() { if (mod) FreeLibrary(mod); }
};

struct Image { VkImage image{}; VkImageView view{}; VkDeviceMemory memory{}; VkFormat format{}; VkImageLayout layout=VK_IMAGE_LAYOUT_UNDEFINED; };
struct Buffer { VkBuffer buffer{}; VkDeviceMemory memory{}; VkDeviceSize size{}; };
uint32_t memory_type(VkFns &vk, VkPhysicalDevice p, uint32_t bits, VkMemoryPropertyFlags flags) { VkPhysicalDeviceMemoryProperties m{}; vk.getMemoryProps(p,&m); for(uint32_t i=0;i<m.memoryTypeCount;i++) if((bits&(1u<<i))&&((m.memoryTypes[i].propertyFlags&flags)==flags)) return i; return UINT32_MAX; }
bool image(VkFns &vk,VkPhysicalDevice p,VkDevice d,VkFormat fmt,Image &o,FILE *l,const char *n) { VkImageCreateInfo c{VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO}; c.imageType=VK_IMAGE_TYPE_2D;c.format=fmt;c.extent={kWidth,kHeight,1};c.mipLevels=c.arrayLayers=1;c.samples=VK_SAMPLE_COUNT_1_BIT;c.tiling=VK_IMAGE_TILING_OPTIMAL;c.usage=VK_IMAGE_USAGE_TRANSFER_DST_BIT|VK_IMAGE_USAGE_TRANSFER_SRC_BIT|VK_IMAGE_USAGE_SAMPLED_BIT|VK_IMAGE_USAGE_STORAGE_BIT;c.initialLayout=VK_IMAGE_LAYOUT_UNDEFINED; VkResult r=vk.createImage(d,&c,nullptr,&o.image);logf(l,"M2A: creating %s image -> %d",n,(int)r);if(r)return false;VkMemoryRequirements q{};vk.getImageMemReq(d,o.image,&q);uint32_t t=memory_type(vk,p,q.memoryTypeBits,VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT);if(t==UINT32_MAX)return false;VkMemoryAllocateInfo a{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};a.allocationSize=q.size;a.memoryTypeIndex=t;if(vk.allocMemory(d,&a,nullptr,&o.memory)!=VK_SUCCESS||vk.bindImageMem(d,o.image,o.memory,0)!=VK_SUCCESS)return false;VkImageViewCreateInfo v{VK_STRUCTURE_TYPE_IMAGE_VIEW_CREATE_INFO};v.image=o.image;v.viewType=VK_IMAGE_VIEW_TYPE_2D;v.format=fmt;v.subresourceRange.aspectMask=VK_IMAGE_ASPECT_COLOR_BIT;v.subresourceRange.levelCount=v.subresourceRange.layerCount=1;r=vk.createImageView(d,&v,nullptr,&o.view);o.format=fmt;return r==VK_SUCCESS; }
bool buffer(VkFns &vk,VkPhysicalDevice p,VkDevice d,VkDeviceSize sz,VkBufferUsageFlags use,Buffer &o) { VkBufferCreateInfo c{VK_STRUCTURE_TYPE_BUFFER_CREATE_INFO};c.size=sz;c.usage=use;c.sharingMode=VK_SHARING_MODE_EXCLUSIVE;if(vk.createBuffer(d,&c,nullptr,&o.buffer)!=VK_SUCCESS)return false;VkMemoryRequirements q{};vk.getBufferMemReq(d,o.buffer,&q);uint32_t t=memory_type(vk,p,q.memoryTypeBits,VK_MEMORY_PROPERTY_HOST_VISIBLE_BIT|VK_MEMORY_PROPERTY_HOST_COHERENT_BIT);if(t==UINT32_MAX)return false;VkMemoryAllocateInfo a{VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};a.allocationSize=q.size;a.memoryTypeIndex=t;if(vk.allocMemory(d,&a,nullptr,&o.memory)!=VK_SUCCESS||vk.bindBufferMem(d,o.buffer,o.memory,0)!=VK_SUCCESS)return false;o.size=sz;return true; }
bool write(VkFns&vk,VkDevice d,Buffer&b,const void*x,size_t n){void*m=nullptr;if(n>b.size||vk.mapMemory(d,b.memory,0,n,0,&m)!=VK_SUCCESS)return false;memcpy(m,x,n);vk.unmapMemory(d,b.memory);return true;}
void transition(VkFns&vk,VkCommandBuffer c,Image&i,VkImageLayout n,VkPipelineStageFlags s,VkPipelineStageFlags d,VkAccessFlags sa,VkAccessFlags da){VkImageMemoryBarrier b{VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER};b.oldLayout=i.layout;b.newLayout=n;b.srcAccessMask=sa;b.dstAccessMask=da;b.image=i.image;b.subresourceRange.aspectMask=VK_IMAGE_ASPECT_COLOR_BIT;b.subresourceRange.levelCount=b.subresourceRange.layerCount=1;vk.cmdBarrier(c,s,d,0,0,nullptr,0,nullptr,1,&b);i.layout=n;}
void copy_in(VkFns&vk,VkCommandBuffer c,Buffer&b,Image&i){VkBufferImageCopy x{};x.imageSubresource.aspectMask=VK_IMAGE_ASPECT_COLOR_BIT;x.imageSubresource.layerCount=1;x.imageExtent={kWidth,kHeight,1};vk.cmdCopyB2I(c,b.buffer,i.image,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,1,&x);}
void copy_out(VkFns&vk,VkCommandBuffer c,Image&i,Buffer&b){VkBufferImageCopy x{};x.imageSubresource.aspectMask=VK_IMAGE_ASPECT_COLOR_BIT;x.imageSubresource.layerCount=1;x.imageExtent={kWidth,kHeight,1};vk.cmdCopyI2B(c,i.image,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,b.buffer,1,&x);}
void readback_barrier(VkFns&vk,VkCommandBuffer c,Buffer&b){VkBufferMemoryBarrier x{VK_STRUCTURE_TYPE_BUFFER_MEMORY_BARRIER};x.srcAccessMask=VK_ACCESS_TRANSFER_WRITE_BIT;x.dstAccessMask=VK_ACCESS_HOST_READ_BIT;x.buffer=b.buffer;x.size=b.size;vk.cmdBarrier(c,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_HOST_BIT,0,0,nullptr,1,&x,0,nullptr);}
void destroy(VkFns&v,VkDevice d,Image&i){if(i.view)v.destroyImageView(d,i.view,nullptr);if(i.image)v.destroyImage(d,i.image,nullptr);if(i.memory)v.freeMemory(d,i.memory,nullptr);}
void destroy(VkFns&v,VkDevice d,Buffer&b){if(b.buffer)v.destroyBuffer(d,b.buffer,nullptr);if(b.memory)v.freeMemory(d,b.memory,nullptr);}
void identity(float m[4][4]){memset(m,0,64);for(int i=0;i<4;i++)m[i][i]=1;}
NVSDK_NGX_DLSSG_Opt_Eval_Params constants(bool reset){NVSDK_NGX_DLSSG_Opt_Eval_Params c{};float f=1.f/tanf(0.5235987756f),a=float(kWidth)/kHeight; c.cameraViewToClip[0][0]=f/a;c.cameraViewToClip[1][1]=f;c.cameraViewToClip[2][2]=-1000.f/999.9f;c.cameraViewToClip[2][3]=-1;c.cameraViewToClip[3][2]=-100.f/999.9f; /* explicit inverse of this RH Vulkan projection */ c.clipToCameraView[0][0]=a/f;c.clipToCameraView[1][1]=1/f;c.clipToCameraView[2][3]=-9.999f;c.clipToCameraView[3][2]=-1;c.clipToCameraView[3][3]=10.f; identity(c.clipToLensClip);identity(c.clipToPrevClip);identity(c.prevClipToClip);c.multiFrameCount=1;c.multiFrameIndex=1;c.mvecScale[0]=1.f/kWidth;c.mvecScale[1]=1.f/kHeight;c.cameraUp[1]=1;c.cameraRight[0]=1;c.cameraFwd[2]=-1;c.cameraNear=.1f;c.cameraFar=1000;c.cameraFOV=1.0471975512f;c.cameraAspectRatio=a;c.colorBuffersHDR=false;c.depthInverted=false;c.cameraMotionIncluded=false;c.reset=reset;c.notRenderingGameFrames=false;c.orthoProjection=false;c.motionVectorsInvalidValue=0;c.motionVectorsDilated=false;c.menuDetectionEnabled=false;c.mvecsSubrectSize={kWidth,kHeight};c.depthSubrectSize={kWidth,kHeight};c.backbufferSubrectSize={kWidth,kHeight};c.outputInterpSubrectSize={kWidth,kHeight};return c;}
uint64_t hash(const std::vector<uint8_t>&x){uint64_t h=1469598103934665603ull;for(auto b:x){h^=b;h*=1099511628211ull;}return h;}
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

    if (feature && vr == VK_SUCCESS) {
        VkSubmitInfo si{VK_STRUCTURE_TYPE_SUBMIT_INFO};si.commandBufferCount=1;si.pCommandBuffers=&cmd;vr=vk.queueSubmit(queue,1,&si,VK_NULL_HANDLE);if(vr==VK_SUCCESS)vr=vk.queueWaitIdle(queue);
        logf(log,"M2A: feature-create submit/wait -> %d",(int)vr);
    }
    Image color{},depth{},mvec{},out{}; Buffer upColor{},upDepth{},upMvec{},readback{};
    bool m2ok = feature && vr==VK_SUCCESS;
    const size_t cb=size_t(kWidth)*kHeight*4, db=size_t(kWidth)*kHeight*4, mb=size_t(kWidth)*kHeight*4;
    if(m2ok) m2ok=image(vk,physical,device,VK_FORMAT_B8G8R8A8_UNORM,color,log,"color")&&image(vk,physical,device,VK_FORMAT_R32_SFLOAT,depth,log,"depth")&&image(vk,physical,device,VK_FORMAT_R16G16_SFLOAT,mvec,log,"motion-vector")&&image(vk,physical,device,VK_FORMAT_B8G8R8A8_UNORM,out,log,"output")&&buffer(vk,physical,device,cb,VK_BUFFER_USAGE_TRANSFER_SRC_BIT,upColor)&&buffer(vk,physical,device,db,VK_BUFFER_USAGE_TRANSFER_SRC_BIT,upDepth)&&buffer(vk,physical,device,mb,VK_BUFFER_USAGE_TRANSFER_SRC_BIT,upMvec)&&buffer(vk,physical,device,cb,VK_BUFFER_USAGE_TRANSFER_DST_BIT,readback);
    std::vector<uint8_t> a(cb),b(cb);std::vector<float> da(size_t(kWidth)*kHeight,.999f),dbuf(da);std::vector<uint16_t> ma(size_t(kWidth)*kHeight*2),mbuf(ma);
    for(uint32_t y=0;y<kHeight;y++)for(uint32_t x=0;x<kWidth;x++){size_t i=(size_t(y)*kWidth+x)*4;bool aa=x>=kRectAX&&x<kRectAX+kRectW&&y>=kRectY&&y<kRectY+kRectH,bb=x>=kRectBX&&x<kRectBX+kRectW&&y>=kRectY&&y<kRectY+kRectH;for(auto*q:{&a,&b}){(*q)[i]=(*q)[i+1]=(*q)[i+2]=32;(*q)[i+3]=255;}if(aa){a[i]=96;a[i+1]=220;a[i+2]=255;da[size_t(y)*kWidth+x]=.9f;}if(bb){b[i]=96;b[i+1]=220;b[i+2]=255;dbuf[size_t(y)*kWidth+x]=.9f;mbuf[(size_t(y)*kWidth+x)*2]=0xD500;} }
    logf(log,"M2A: motion vectors are raw R16G16 pixel current-to-previous; B rectangle=(-80,0), mvecScale=(1/2560,1/1440)");
    VkCommandBuffer ec[2]{};if(m2ok){VkCommandBufferAllocateInfo ai{VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO};ai.commandPool=pool;ai.level=VK_COMMAND_BUFFER_LEVEL_PRIMARY;ai.commandBufferCount=2;m2ok=vk.allocCommandBuffers(device,&ai,ec)==VK_SUCCESS&&write(vk,device,upColor,a.data(),cb)&&write(vk,device,upDepth,da.data(),db)&&write(vk,device,upMvec,ma.data(),mb);}
    auto resource=[](Image&i,bool rw){return NVSDK_NGX_Create_ImageView_Resource_VK(i.view,i.image,{VK_IMAGE_ASPECT_COLOR_BIT,0,1,0,1},i.format,kWidth,kHeight,rw);};
    auto eval=[&](VkCommandBuffer c,bool first)->bool {VkCommandBufferBeginInfo bi{VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO};bi.flags=VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;if(vk.beginCommandBuffer(c,&bi)!=VK_SUCCESS)return false;if(first){transition(vk,c,color,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,0,VK_ACCESS_TRANSFER_WRITE_BIT);transition(vk,c,depth,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,0,VK_ACCESS_TRANSFER_WRITE_BIT);transition(vk,c,mvec,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,0,VK_ACCESS_TRANSFER_WRITE_BIT);transition(vk,c,out,VK_IMAGE_LAYOUT_GENERAL,VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,0,VK_ACCESS_SHADER_WRITE_BIT);}else{transition(vk,c,color,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_SHADER_READ_BIT,VK_ACCESS_TRANSFER_WRITE_BIT);transition(vk,c,depth,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_SHADER_READ_BIT,VK_ACCESS_TRANSFER_WRITE_BIT);transition(vk,c,mvec,VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_SHADER_READ_BIT,VK_ACCESS_TRANSFER_WRITE_BIT);}copy_in(vk,c,upColor,color);copy_in(vk,c,upDepth,depth);copy_in(vk,c,upMvec,mvec);transition(vk,c,color,VK_IMAGE_LAYOUT_GENERAL,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_ACCESS_SHADER_READ_BIT|VK_ACCESS_SHADER_WRITE_BIT);transition(vk,c,depth,VK_IMAGE_LAYOUT_GENERAL,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_ACCESS_SHADER_READ_BIT);transition(vk,c,mvec,VK_IMAGE_LAYOUT_GENERAL,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_ACCESS_TRANSFER_WRITE_BIT,VK_ACCESS_SHADER_READ_BIT);auto rc=resource(color,true),rd=resource(depth,false),rm=resource(mvec,false),ro=resource(out,true);NVSDK_NGX_VK_DLSSG_Eval_Params ep{};ep.pBackbuffer=&rc;ep.pDepth=&rd;ep.pMVecs=&rm;ep.pOutputInterpFrame=&ro;auto op=constants(first);NVSDK_NGX_Result nr=NGX_VK_EVALUATE_DLSSG(c,feature,params,&ep,&op);logf(log,"M2A: evaluate %c -> 0x%08X (%s)",first?'A':'B',(unsigned)nr,ngx_name(nr));if(NVSDK_NGX_FAILED(nr))return false;if(!first){transition(vk,c,out,VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,VK_PIPELINE_STAGE_COMPUTE_SHADER_BIT,VK_PIPELINE_STAGE_TRANSFER_BIT,VK_ACCESS_SHADER_WRITE_BIT,VK_ACCESS_TRANSFER_READ_BIT);copy_out(vk,c,out,readback);readback_barrier(vk,c,readback);}if(vk.endCommandBuffer(c)!=VK_SUCCESS)return false;VkSubmitInfo s{VK_STRUCTURE_TYPE_SUBMIT_INFO};s.commandBufferCount=1;s.pCommandBuffers=&c;return vk.queueSubmit(queue,1,&s,VK_NULL_HANDLE)==VK_SUCCESS&&vk.queueWaitIdle(queue)==VK_SUCCESS;};
    if(m2ok){logf(log,"M2A: uploading/evaluating Frame A reset=true");m2ok=eval(ec[0],true);if(m2ok)m2ok=write(vk,device,upColor,b.data(),cb)&&write(vk,device,upDepth,dbuf.data(),db)&&write(vk,device,upMvec,mbuf.data(),mb);if(m2ok){logf(log,"M2A: uploading/evaluating Frame B reset=false");m2ok=eval(ec[1],false);}}
    std::vector<uint8_t> generated(cb);if(m2ok){void*p=nullptr;m2ok=vk.mapMemory(device,readback.memory,0,cb,0,&p)==VK_SUCCESS;if(m2ok){memcpy(generated.data(),p,cb);vk.unmapMemory(device,readback.memory);}}
    uint64_t nz=0,daDiff=0,dbDiff=0;uint8_t mn=255,mx=0;double avg[3]{},cx[3]{},cw[3]{};for(uint32_t y=0;y<kHeight;y++)for(uint32_t x=0;x<kWidth;x++){size_t i=(size_t(y)*kWidth+x)*4;for(int f=0;f<3;f++){auto&z=f==0?a:f==1?generated:b;double w=std::max(0.,(double(z[i])+z[i+1]+z[i+2])/3.-80.);cx[f]+=w*x;cw[f]+=w;}if(generated[i]||generated[i+1]||generated[i+2])nz++;avg[0]+=generated[i+2];avg[1]+=generated[i+1];avg[2]+=generated[i];mn=std::min(mn,std::min(generated[i],std::min(generated[i+1],generated[i+2])));mx=std::max(mx,std::max(generated[i],std::max(generated[i+1],generated[i+2])));if(memcmp(generated.data()+i,a.data()+i,3))daDiff++;if(memcmp(generated.data()+i,b.data()+i,3))dbDiff++;}for(double&v:avg)v/=double(kWidth)*kHeight;logf(log,"M2A: checksum=0x%016llX nonzero=%llu avgRGB=%.2f,%.2f,%.2f min=%u max=%u diffA=%.4f%% diffB=%.4f%% centroid A=%.2f generated=%.2f B=%.2f",(unsigned long long)hash(generated),(unsigned long long)nz,avg[0],avg[1],avg[2],mn,mx,100.*daDiff/(kWidth*double(kHeight)),100.*dbDiff/(kWidth*double(kHeight)),cx[0]/cw[0],cx[1]/cw[1],cx[2]/cw[2]);
    m2ok=m2ok&&nz&&daDiff&&dbDiff;logf(log,"MILESTONE 2A %s",m2ok?"PASSED":"FAILED: evaluation/readback was empty or identical to an input");destroy(vk,device,readback);destroy(vk,device,upMvec);destroy(vk,device,upDepth);destroy(vk,device,upColor);destroy(vk,device,out);destroy(vk,device,mvec);destroy(vk,device,depth);destroy(vk,device,color);

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
    return m2ok ? 0 : 1;
}
