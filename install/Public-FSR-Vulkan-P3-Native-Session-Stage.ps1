[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)][string]$GeneratedRoot,
    [Parameter(Mandatory=$true)][string]$FeederSource
)
$ErrorActionPreference='Stop'

function Once([string]$Text,[string]$Old,[string]$New,[string]$Label){
    $count=0;$pos=0
    while(($i=$Text.IndexOf($Old,$pos,[StringComparison]::Ordinal))-ge 0){$count++;$pos=$i+$Old.Length}
    if($count-ne 1){throw "FSR P3 stage $Label : expected one match, found $count"}
    return $Text.Replace($Old,$New)
}

if(-not(Test-Path -LiteralPath $FeederSource)){throw "Missing feeder source: $FeederSource"}
$feed=[IO.File]::ReadAllText($FeederSource)

# P3's purpose is strict: when FSR is selected before the Vulkan session opens,
# do not create a private D3D12 device and do not initialize/query NGX at all.
# Allocate the feeder's temporary color/depth/MV/output surfaces directly on the
# game's VkDevice instead. The NVIDIA session path remains byte-for-byte reachable
# whenever FSR is not selected.
$initMarker='static bool InitSessionVk(reshade::api::effect_runtime *rt)'
$initAt=$feed.IndexOf($initMarker,[StringComparison]::Ordinal)
if($initAt-lt 0){throw 'FSR P3: InitSessionVk marker missing'}

$helpers=@'
static bool g_m3kFsrNativeSession=false;

static bool M3kFsrSelectedAtSessionOpen()
{
    wchar_t path[MAX_PATH]={};
    if(!GetModuleFileNameW(g_self,path,MAX_PATH))return false;
    wchar_t *slash=wcsrchr(path,L'\\');
    if(!slash)return false;
    *(slash+1)=0;
    wcscat_s(path,L"m3k-nr.ini");
    return GetPrivateProfileIntW(L"M3K",L"FSRProof",0,path)!=0;
}

// Minimal native-Vulkan loader for FSR. Unlike FeedVkLoad, this deliberately does
// NOT require any Win32 external-memory/semaphore entry point because P3 never
// crosses into D3D12.
static bool M3kFsrLoadNativeVk(FeedVk *vk,VkDevice device,VkPhysicalDevice phys)
{
    *vk={};
    vk->dev=device;vk->phys=phys;
    vk->lib=LoadLibraryW(L"vulkan-1.dll");
    if(vk->lib==nullptr)return false;
    vk->GetDeviceProcAddr=reinterpret_cast<PFN_vkGetDeviceProcAddr>(GetProcAddress(vk->lib,"vkGetDeviceProcAddr"));
    vk->GetPhysicalDeviceMemoryProperties=reinterpret_cast<PFN_vkGetPhysicalDeviceMemoryProperties>(
        GetProcAddress(vk->lib,"vkGetPhysicalDeviceMemoryProperties"));
    if(vk->GetDeviceProcAddr==nullptr)return false;
#define M3K_FSR_VK_GET(member,name) \
    vk->member=reinterpret_cast<PFN_vk##member>(vk->GetDeviceProcAddr(device,name)); \
    if(vk->member==nullptr)return false;
    M3K_FSR_VK_GET(CreateImage,"vkCreateImage")
    M3K_FSR_VK_GET(DestroyImage,"vkDestroyImage")
    M3K_FSR_VK_GET(GetImageMemoryRequirements,"vkGetImageMemoryRequirements")
    M3K_FSR_VK_GET(AllocateMemory,"vkAllocateMemory")
    M3K_FSR_VK_GET(FreeMemory,"vkFreeMemory")
    M3K_FSR_VK_GET(BindImageMemory,"vkBindImageMemory")
    M3K_FSR_VK_GET(CmdPipelineBarrier,"vkCmdPipelineBarrier")
    M3K_FSR_VK_GET(CmdCopyImage,"vkCmdCopyImage")
    M3K_FSR_VK_GET(CmdBlitImage,"vkCmdBlitImage")
    M3K_FSR_VK_GET(CreateBuffer,"vkCreateBuffer")
    M3K_FSR_VK_GET(DestroyBuffer,"vkDestroyBuffer")
    M3K_FSR_VK_GET(GetBufferMemoryRequirements,"vkGetBufferMemoryRequirements")
    M3K_FSR_VK_GET(BindBufferMemory,"vkBindBufferMemory")
    M3K_FSR_VK_GET(CmdCopyBufferToImage,"vkCmdCopyBufferToImage")
    M3K_FSR_VK_GET(CmdCopyImageToBuffer,"vkCmdCopyImageToBuffer")
#undef M3K_FSR_VK_GET
    vk->WaitSemaphores=nullptr;
    vk->GetSemaphoreCounterValue=nullptr;
    vk->CreateSemaphore=nullptr;
    vk->DestroySemaphore=nullptr;
    vk->ImportSemaphoreWin32HandleKHR=nullptr;
    vk->ok=true;
    return true;
}

static bool M3kFsrAllocNativeImage(FeedVk *vk,UINT w,UINT h,VkFormat fmt,bool storage,
                                   VkImage *outImage,VkDeviceMemory *outMemory)
{
    *outImage=VK_NULL_HANDLE;*outMemory=VK_NULL_HANDLE;
    if(!vk||!vk->ok||!w||!h||fmt==VK_FORMAT_UNDEFINED)return false;

    VkImageCreateInfo ici={VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO};
    ici.imageType=VK_IMAGE_TYPE_2D;
    ici.format=fmt;
    ici.extent={w,h,1};
    ici.mipLevels=1;ici.arrayLayers=1;ici.samples=VK_SAMPLE_COUNT_1_BIT;
    ici.tiling=VK_IMAGE_TILING_OPTIMAL;
    ici.usage=VK_IMAGE_USAGE_TRANSFER_SRC_BIT|VK_IMAGE_USAGE_TRANSFER_DST_BIT|
              (storage?VK_IMAGE_USAGE_STORAGE_BIT:VK_IMAGE_USAGE_SAMPLED_BIT);
    ici.sharingMode=VK_SHARING_MODE_EXCLUSIVE;
    ici.initialLayout=VK_IMAGE_LAYOUT_UNDEFINED;
    if(vk->CreateImage(vk->dev,&ici,nullptr,outImage)!=VK_SUCCESS)return false;

    VkMemoryRequirements req={};
    vk->GetImageMemoryRequirements(vk->dev,*outImage,&req);
    uint32_t typeIndex=0;bool found=false;
    if(vk->GetPhysicalDeviceMemoryProperties&&vk->phys!=VK_NULL_HANDLE){
        VkPhysicalDeviceMemoryProperties mp={};
        vk->GetPhysicalDeviceMemoryProperties(vk->phys,&mp);
        for(uint32_t i=0;i<mp.memoryTypeCount;++i){
            if((req.memoryTypeBits&(1u<<i))==0)continue;
            if((mp.memoryTypes[i].propertyFlags&VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)==0)continue;
            typeIndex=i;found=true;break;
        }
    }
    if(!found){
        for(uint32_t i=0;i<32;++i)if(req.memoryTypeBits&(1u<<i)){typeIndex=i;found=true;break;}
    }
    if(!found){
        vk->DestroyImage(vk->dev,*outImage,nullptr);*outImage=VK_NULL_HANDLE;return false;
    }

    VkMemoryAllocateInfo mai={VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO};
    mai.allocationSize=req.size;mai.memoryTypeIndex=typeIndex;
    if(vk->AllocateMemory(vk->dev,&mai,nullptr,outMemory)!=VK_SUCCESS){
        vk->DestroyImage(vk->dev,*outImage,nullptr);*outImage=VK_NULL_HANDLE;return false;
    }
    if(vk->BindImageMemory(vk->dev,*outImage,*outMemory,0)!=VK_SUCCESS){
        vk->FreeMemory(vk->dev,*outMemory,nullptr);*outMemory=VK_NULL_HANDLE;
        vk->DestroyImage(vk->dev,*outImage,nullptr);*outImage=VK_NULL_HANDLE;return false;
    }
    return true;
}

static bool M3kFsrBuildNativeResourcesVk(UINT w,UINT h,DXGI_FORMAT bbFmt)
{
    if(g.frame_ready&&g.width==w&&g.height==h&&g.bb_fmt==bbFmt&&
       g.vk_img[SLOT_COLOR]!=VK_NULL_HANDLE&&g.vk_img[SLOT_OUTPUT]!=VK_NULL_HANDLE)
        return true;

    ReleaseFrameResources();
    g.width=w;g.height=h;g.bb_fmt=bbFmt;
    g.color_fmt=TypedColorFormat(bbFmt);
    g.output_fmt=g.color_fmt;
    g.hdr=g_cfg.hdr>=0?g_cfg.hdr!=0:IsHdrFormat(g.color_fmt);
    if(g.color_fmt==DXGI_FORMAT_UNKNOWN){
        Log("M3K-FSR-P3: unsupported backbuffer format %u (%s)",bbFmt,FormatName(bbFmt));
        return false;
    }

    const VkFormat colorFmt=FeedVkFormat(g.color_fmt);
    const bool ok=
        M3kFsrAllocNativeImage(&g.vk,w,h,colorFmt,false,&g.vk_img[SLOT_COLOR], &g.vk_mem[SLOT_COLOR]) &&
        M3kFsrAllocNativeImage(&g.vk,w,h,colorFmt,true, &g.vk_img[SLOT_OUTPUT],&g.vk_mem[SLOT_OUTPUT]) &&
        M3kFsrAllocNativeImage(&g.vk,w,h,VK_FORMAT_R32_SFLOAT,false,&g.vk_img[SLOT_DEPTH],&g.vk_mem[SLOT_DEPTH]) &&
        M3kFsrAllocNativeImage(&g.vk,w,h,VK_FORMAT_R16G16_SFLOAT,false,&g.vk_img[SLOT_MV],&g.vk_mem[SLOT_MV]) &&
        M3kFsrAllocNativeImage(&g.vk,w,h,VK_FORMAT_R8_UNORM,false,&g.vk_img[SLOT_MASK],&g.vk_mem[SLOT_MASK]);
    if(!ok){
        Log("M3K-FSR-P3: native Vulkan image allocation FAILED");
        ReleaseFrameResources();
        return false;
    }

    g.mask_ok=false;
    g.sr_active=false;
    g.sr_requested=false;
    g.output_width=w;g.output_height=h;
    g.vk_layout_init=false;g.vk_released=false;
    g.frame_ready=true;g.need_reset=true;
    Log("M3K-FSR-P3: native Vulkan frame resources READY %ux%u; D3D12 textures=0 NGX feature=0",w,h);
    return true;
}

'@
$feed=$feed.Substring(0,$initAt)+$helpers+$feed.Substring($initAt)

$sessionAnchor=@'
    if (g.rs_dev == nullptr || g.rs_queue == nullptr)
    {
        FeedDisable("the ReShade device/queue is not reachable");
        return false;
    }

    // Private D3D12 device, loaded so ReShade hooks it -- that hook is what lets the
'@
$sessionNew=@'
    if (g.rs_dev == nullptr || g.rs_queue == nullptr)
    {
        FeedDisable("the ReShade device/queue is not reachable");
        return false;
    }

    if(M3kFsrSelectedAtSessionOpen())
    {
        const VkDevice gameDevice=FeedVkDispatch<VkDevice>(g.rs_dev->get_native());
        if(gameDevice==VK_NULL_HANDLE||g_vk_phys==VK_NULL_HANDLE||
           !M3kFsrLoadNativeVk(&g.vk,gameDevice,g_vk_phys))
        {
            Log("M3K-FSR-P3: native Vulkan session FAILED (device=%p phys=%p)",
                (void*)gameDevice,(void*)g_vk_phys);
            FeedDisable("FSR native Vulkan session could not load the game device");
            return false;
        }
        g_m3kFsrNativeSession=true;
        g.session_ready=true;
        Log("M3K-FSR-P3: NATIVE VULKAN SESSION READY; D3D12 NOT CREATED; NGX NOT INITIALIZED");
        return true;
    }

    // Private D3D12 device, loaded so ReShade hooks it -- that hook is what lets the
'@
$feed=Once $feed $sessionAnchor $sessionNew 'native FSR session branch'

$buildAnchor=@'
static bool BuildResourcesVk(UINT w, UINT h, DXGI_FORMAT bb_fmt)
{
'@
$buildNew=@'
static bool BuildResourcesVk(UINT w, UINT h, DXGI_FORMAT bb_fmt)
{
    if(g_m3kFsrNativeSession)
        return M3kFsrBuildNativeResourcesVk(w,h,bb_fmt);
'@
$feed=Once $feed $buildAnchor $buildNew 'native resource branch'

$shutdownAnchor=@'
    ReleaseFrameResources();
    if (g.params != nullptr) { if (!g_ngx_dying) NVSDK_NGX_D3D12_DestroyParameters(g.params); g.params = nullptr; }
'@
$shutdownNew=@'
    ReleaseFrameResources();
    if(g_m3kFsrNativeSession&&g_m3kFsrBackend.IsReady()){
        // ReleaseFrameResources waited for the Vulkan queue, so FidelityFX shared
        // resources can now be destroyed without racing in-flight work.
        g_m3kFsrBackend.Shutdown();
        Log("M3K-FSR-P3: FidelityFX context shut down after Vulkan queue idle");
    }
    if (g.params != nullptr) { if (!g_ngx_dying) NVSDK_NGX_D3D12_DestroyParameters(g.params); g.params = nullptr; }
'@
$feed=Once $feed $shutdownAnchor $shutdownNew 'safe FSR shutdown'

$shutdownTail=@'
    g.rs_dev   = nullptr;
    g.vk_frame = 0;
    g.gl_frame = 0;
'@
$shutdownTailNew=@'
    g.rs_dev   = nullptr;
    g_m3kFsrNativeSession=false;
    g.vk_frame = 0;
    g.gl_frame = 0;
'@
$feed=Once $feed $shutdownTail $shutdownTailNew 'native session reset'

foreach($marker in @(
    'M3K-FSR-P3: NATIVE VULKAN SESSION READY; D3D12 NOT CREATED; NGX NOT INITIALIZED',
    'M3K-FSR-P3: native Vulkan frame resources READY',
    'M3kFsrLoadNativeVk',
    'M3kFsrAllocNativeImage',
    'if(g_m3kFsrNativeSession)',
    'g_m3kFsrBackend.Shutdown()'
)){
    if($feed.IndexOf($marker,[StringComparison]::Ordinal)-lt 0){throw "FSR P3 verification marker missing: $marker"}
}

[IO.File]::WriteAllText($FeederSource,$feed,[Text.UTF8Encoding]::new($false))
Write-Host 'FSR-P3 native Vulkan session stage applied: FSR no longer opens D3D12/NGX.'
