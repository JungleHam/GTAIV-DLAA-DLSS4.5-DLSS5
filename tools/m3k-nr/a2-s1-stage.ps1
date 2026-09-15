# A2-S1 build-time edits applied to the exact pinned Feeder source after feeder-m3k.patch.
# This file only transforms the generated staging checkout under tools/m3k-nr/_work.

function Invoke-M3kA2S1Stage {
    param([Parameter(Mandatory=$true)][string]$FeedText)

    function Replace-A2S1ExactOnce([string]$Text, [string]$Old, [string]$New, [string]$Label) {
        $count = 0
        $pos = 0
        while (($i = $Text.IndexOf($Old, $pos, [StringComparison]::Ordinal)) -ge 0) {
            $count++
            $pos = $i + $Old.Length
        }
        if ($count -ne 1) { throw "A2-S1 ${Label}: expected exactly one source match, found $count" }
        return $Text.Replace($Old, $New)
    }

    # The existing buffer_home workaround normally copies Vulkan-written linear buffers
    # into the D3D12 input textures. A2-S1 writes the true source + scaled guides directly
    # into the shared VkImages instead, so D3D12 must consume those images as-is.
    $bufferOld = '    if (g.in_buf12[SLOT_COLOR] != nullptr && g_cfg.mode >= 2)'
    $bufferNew = '    if (!g.sr_active && g.in_buf12[SLOT_COLOR] != nullptr && g_cfg.mode >= 2)'
    $FeedText = Replace-A2S1ExactOnce $FeedText $bufferOld $bufferNew 'shared-image input selection'

    # Inject after the ordinary mask capture, while bb/mv/depth are still copy sources and
    # before the imported images are released to D3D12. Colour comes from DXVK's true source;
    # only motion/depth are scaled from presenter resolution.
    $captureOld = @'
            else
                FeedVkCopyImage(&g.vk, cb, mk_img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, g.vk_img[SLOT_MASK], VK_IMAGE_LAYOUT_GENERAL, w, h);
            {
                const resource       res[1]  = { mask_res };
                const resource_usage from[1] = { resource_usage::copy_source };
                const resource_usage to[1]   = { resource_usage::shader_resource };
                cl->barrier(1, res, from, to);
            }
        }

        if (g_cfg.mode == 1)
'@
    $captureNew = @'
            else
                FeedVkCopyImage(&g.vk, cb, mk_img, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL, g.vk_img[SLOT_MASK], VK_IMAGE_LAYOUT_GENERAL, w, h);
            {
                const resource       res[1]  = { mask_res };
                const resource_usage from[1] = { resource_usage::copy_source };
                const resource_usage to[1]   = { resource_usage::shader_resource };
                cl->barrier(1, res, from, to);
            }
        }

        M3kSrCaptureVk(cb, mv_img, dp_img, w, h);

        if (g_cfg.mode == 1)
'@
    $FeedText = Replace-A2S1ExactOnce $FeedText $captureOld $captureNew 'true-source capture insertion'

    return $FeedText
}
