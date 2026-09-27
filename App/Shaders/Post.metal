#include "ShaderTypes.h"

// Post stack (issue #10): dual-filter bloom → exposure + ACES tone map → 3D grade LUT → vignette.
// Output is display-referred (gamma encoded) RGBA8 so MetalFX spatial upscaling runs in perceptual space.

struct PostOut { float4 position [[position]]; float2 uv; };

vertex PostOut post_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    PostOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

constexpr sampler linearClamp(coord::normalized, filter::linear, address::clamp_to_edge);

static inline float3 prefilter(float3 c, float threshold, float knee) {
    float brightness = max(c.r, max(c.g, c.b));
    float soft = clamp(brightness - threshold + knee, 0.0, 2.0 * knee);
    soft = soft * soft / (4.0 * knee + 1e-4);
    float contribution = max(soft, brightness - threshold) / max(brightness, 1e-4);
    return c * contribution;
}

// First bloom level: read the dynamic-resolution HDR region, threshold, 2x downsample.
fragment float4 bloom_prefilter(PostOut in [[stage_in]], texture2d<float> src [[texture(0)]],
                                constant PostUniforms& pu [[buffer(0)]]) {
    float2 uv = in.uv * pu.source.xy;
    float2 hp = pu.source.zw * 0.5;
    float3 c = src.sample(linearClamp, uv).rgb * 4.0;
    c += src.sample(linearClamp, uv - hp).rgb;
    c += src.sample(linearClamp, uv + hp).rgb;
    c += src.sample(linearClamp, uv + float2(hp.x, -hp.y)).rgb;
    c += src.sample(linearClamp, uv - float2(hp.x, -hp.y)).rgb;
    c = min(c / 8.0, float3(64.0));
    return float4(prefilter(c, pu.bloom.x, pu.bloom.y), 1.0);
}

fragment float4 bloom_down(PostOut in [[stage_in]], texture2d<float> src [[texture(0)]],
                           constant PostUniforms& pu [[buffer(0)]]) {
    float2 hp = pu.source.zw * 0.5;
    float2 uv = in.uv;
    float3 c = src.sample(linearClamp, uv).rgb * 4.0;
    c += src.sample(linearClamp, uv - hp).rgb;
    c += src.sample(linearClamp, uv + hp).rgb;
    c += src.sample(linearClamp, uv + float2(hp.x, -hp.y)).rgb;
    c += src.sample(linearClamp, uv - float2(hp.x, -hp.y)).rgb;
    return float4(c / 8.0, 1.0);
}

fragment float4 bloom_up(PostOut in [[stage_in]], texture2d<float> src [[texture(0)]],
                         constant PostUniforms& pu [[buffer(0)]]) {
    float2 hp = pu.source.zw * 0.5;
    float2 uv = in.uv;
    float3 c = src.sample(linearClamp, uv + float2(-hp.x * 2.0, 0.0)).rgb;
    c += src.sample(linearClamp, uv + float2(-hp.x, hp.y)).rgb * 2.0;
    c += src.sample(linearClamp, uv + float2(0.0, hp.y * 2.0)).rgb;
    c += src.sample(linearClamp, uv + float2(hp.x, hp.y)).rgb * 2.0;
    c += src.sample(linearClamp, uv + float2(hp.x * 2.0, 0.0)).rgb;
    c += src.sample(linearClamp, uv + float2(hp.x, -hp.y)).rgb * 2.0;
    c += src.sample(linearClamp, uv + float2(0.0, -hp.y * 2.0)).rgb;
    c += src.sample(linearClamp, uv + float2(-hp.x, -hp.y)).rgb * 2.0;
    return float4(c / 12.0, 1.0);
}

static inline float3 aces(float3 x) {
    return saturate((x * (2.51 * x + 0.03)) / (x * (2.43 * x + 0.59) + 0.14));
}

static inline float3 linearToSRGB(float3 c) {
    return select(1.055 * pow(c, 1.0 / 2.4) - 0.055, c * 12.92, c <= 0.0031308);
}

fragment float4 composite(PostOut in [[stage_in]],
                          texture2d<float> hdr [[texture(0)]],
                          texture2d<float> bloom [[texture(1)]],
                          texture3d<float> lut [[texture(2)]],
                          constant PostUniforms& pu [[buffer(0)]]) {
    float2 uv = in.uv * pu.source.xy;
    float3 c;
    if (pu.misc.y > 0.0) {
        float2 dir = (in.uv - 0.5) * pu.misc.y * 0.006;
        c = float3(hdr.sample(linearClamp, uv + dir * pu.source.xy).r,
                   hdr.sample(linearClamp, uv).g,
                   hdr.sample(linearClamp, uv - dir * pu.source.xy).b);
    } else {
        c = hdr.sample(linearClamp, uv).rgb;
    }
    if (pu.bloom.w > 0.5) c += bloom.sample(linearClamp, in.uv).rgb * pu.bloom.z;
    c = aces(c * pu.grade.x);
    c = linearToSRGB(c);
    if (pu.grade.y > 0.5) {
        float size = pu.grade.w;
        float3 coord = c * ((size - 1.0) / size) + 0.5 / size;
        c = lut.sample(linearClamp, coord).rgb;
    }
    float2 v = in.uv - 0.5;
    c *= 1.0 - pu.grade.z * smoothstep(0.15, 0.75, dot(v, v) * 2.0);
    return float4(saturate(c), 1.0);
}

// Final: scale the (optionally MetalFX-upscaled) LDR image onto the drawable.
fragment float4 final_blit(PostOut in [[stage_in]], texture2d<float> src [[texture(0)]],
                           constant PostUniforms& pu [[buffer(0)]]) {
    return float4(src.sample(linearClamp, in.uv * pu.source.xy).rgb, 1.0);
}
