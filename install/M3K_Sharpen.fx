#include "ReShade.fxh"

uniform float M3K_Sharpness <
    hidden = true;
> = 0.0;

float M3K_Luma(float3 c)
{
    return dot(c, float3(0.2126, 0.7152, 0.0722));
}

float4 M3K_SharpenPS(float4 pos : SV_Position, float2 uv : TEXCOORD) : SV_Target
{
    const float2 px = ReShade::PixelSize;
    const float4 center4 = tex2D(ReShade::BackBuffer, uv);
    const float3 c = center4.rgb;

    const float3 l  = tex2D(ReShade::BackBuffer, uv + float2(-px.x,  0.0)).rgb;
    const float3 r  = tex2D(ReShade::BackBuffer, uv + float2( px.x,  0.0)).rgb;
    const float3 u  = tex2D(ReShade::BackBuffer, uv + float2( 0.0, -px.y)).rgb;
    const float3 d  = tex2D(ReShade::BackBuffer, uv + float2( 0.0,  px.y)).rgb;

    const float3 ul = tex2D(ReShade::BackBuffer, uv + float2(-px.x, -px.y)).rgb;
    const float3 ur = tex2D(ReShade::BackBuffer, uv + float2( px.x, -px.y)).rgb;
    const float3 dl = tex2D(ReShade::BackBuffer, uv + float2(-px.x,  px.y)).rgb;
    const float3 dr = tex2D(ReShade::BackBuffer, uv + float2( px.x,  px.y)).rgb;

    const float3 blur = (l + r + u + d) * 0.1875 + (ul + ur + dl + dr) * 0.0625;
    float3 detail = c - blur;

    const float localRange =
        max(max(M3K_Luma(l), M3K_Luma(r)), max(M3K_Luma(u), M3K_Luma(d))) -
        min(min(M3K_Luma(l), M3K_Luma(r)), min(M3K_Luma(u), M3K_Luma(d)));

    const float limit = lerp(0.035, 0.14, saturate(localRange * 4.0));
    detail = clamp(detail, -limit.xxx, limit.xxx);

    const float amount = M3K_Sharpness * 1.6;
    return float4(saturate(c + detail * amount), center4.a);
}

technique M3K_Sharpen <
    hidden = true;
>
{
    pass
    {
        VertexShader = PostProcessVS;
        PixelShader = M3K_SharpenPS;
    }
}
