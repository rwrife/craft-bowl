#include "ShaderTypes.h"

// Forward pass: blocky lit geometry (players, crowd, stadium, turf), sky, floodlight glows, debug draw.
// Look rules (docs/PLAN.md §3): nearest-style pixel texels, wrapped diffuse + rim, soft PCF shadows,
// baked per-block AO, HDR emissive floodlights feeding bloom.

constant float kHalfWidth = 26.6665;

constant float3 kSkin[12] = {
    float3(0.965, 0.843, 0.765), float3(0.929, 0.769, 0.651), float3(0.886, 0.690, 0.549),
    float3(0.831, 0.620, 0.463), float3(0.776, 0.541, 0.384), float3(0.690, 0.463, 0.314),
    float3(0.604, 0.384, 0.259), float3(0.522, 0.322, 0.212), float3(0.439, 0.263, 0.173),
    float3(0.361, 0.212, 0.137), float3(0.290, 0.169, 0.110), float3(0.227, 0.133, 0.090),
};

static inline float hash21(float2 p) {
    p = fract(p * float2(123.34, 456.21));
    p += dot(p, p + 45.32);
    return fract(p.x * p.y);
}

static inline float hash11(uint n) {
    n = (n << 13u) ^ n;
    n = n * (n * n * 15731u + 789221u) + 1376312589u;
    return float(n & 0x7fffffffu) / float(0x7fffffff);
}

static inline float3 srgbToLinear(float3 c) { return pow(c, 2.2); }

static inline uint frameFlags(constant FrameUniforms& fu) { return as_type<uint>(fu.params.w); }

// MARK: - Scene geometry

struct SceneOut {
    float4 position [[position]];
    float3 worldPos;
    float3 normal;
    float3 albedo;
    float3 local;
    float4 lightPos;
    float ao;
    float emissive;
    uint material [[flat]];
    uint flags [[flat]];
};

struct Skinned { float4 world; float3 normal; };

static inline Skinned skin(Vertex v, Instance inst, const device float4x4* bones, constant FrameUniforms& fu) {
    float4 lp = float4(v.position.xyz, 1.0);
    float3 n = v.normal.xyz;
    if (inst.params.y != NO_BONES) {
        float4x4 b = bones[inst.params.y + uint(v.position.w)];
        lp = b * lp;
        n = (b * float4(n, 0.0)).xyz;
    }
    Skinned s;
    s.world = inst.model * lp;
    s.normal = normalize((inst.model * float4(n, 0.0)).xyz);
    if ((inst.params.z & INST_CROWD) != 0u) {
        uint seed = inst.params.w >> 16;
        float excite = fu.params.x;
        float phase = hash11(seed) * 6.2831;
        float speed = 2.0 + 5.0 * excite + hash11(seed + 7u) * 1.5;
        float amp = 0.03 + 0.28 * excite * hash11(seed + 13u);
        s.world.y += max(0.0, sin(fu.cameraPos.w * speed + phase)) * amp;
    }
    return s;
}

static inline float3 materialColor(uint mat, float3 base, Instance inst, constant TeamColors* teams) {
    uint team = min(inst.params.x, 1u);
    constant TeamColors& t = teams[team];
    switch (mat) {
        case MAT_SKIN: return srgbToLinear(kSkin[min(inst.params.w & 0xFFu, 11u)]);
        case MAT_PRIMARY: return t.primary.rgb;
        case MAT_SECONDARY: return t.secondary.rgb;
        case MAT_HELMET: return t.helmet.rgb;
        case MAT_PANTS: return t.pants.rgb;
        case MAT_TRIM: return t.trim.rgb;
        case MAT_STRIPE: return t.stripe.rgb;
        case MAT_FACEMASK: return float3(0.55, 0.56, 0.6);
        case MAT_CROWD: return inst.tint.rgb;
        default: return base * inst.tint.rgb;
    }
}

vertex SceneOut scene_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                             const device Vertex* verts [[buffer(0)]],
                             const device Instance* instances [[buffer(1)]],
                             const device uint* visible [[buffer(2)]],
                             constant DrawParams& dp [[buffer(3)]],
                             constant FrameUniforms& fu [[buffer(4)]],
                             const device float4x4* bones [[buffer(5)]],
                             constant TeamColors* teams [[buffer(6)]]) {
    uint idx = dp.useVisible != 0u ? visible[dp.visibleOffset + iid] : iid;
    Instance inst = instances[idx];
    Vertex v = verts[vid];
    Skinned s = skin(v, inst, bones, fu);

    SceneOut o;
    o.position = fu.viewProj * s.world;
    o.worldPos = s.world.xyz;
    o.normal = s.normal;
    o.local = v.position.xyz;
    o.lightPos = fu.lightViewProj * s.world;
    o.ao = v.normal.w;
    o.material = uint(v.color.a + 0.5);
    o.albedo = materialColor(o.material, v.color.rgb, inst, teams);
    o.emissive = inst.tint.a;
    o.flags = inst.params.z;
    return o;
}

struct ShadowOut { float4 position [[position]]; };

vertex ShadowOut shadow_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                               const device Vertex* verts [[buffer(0)]],
                               const device Instance* instances [[buffer(1)]],
                               const device uint* visible [[buffer(2)]],
                               constant DrawParams& dp [[buffer(3)]],
                               constant FrameUniforms& fu [[buffer(4)]],
                               const device float4x4* bones [[buffer(5)]]) {
    uint idx = dp.useVisible != 0u ? visible[dp.visibleOffset + iid] : iid;
    Skinned s = skin(verts[vid], instances[idx], bones, fu);
    ShadowOut o;
    o.position = fu.lightViewProj * s.world;
    return o;
}

// Procedural turf: chunky 6-texels-per-yard grass, mowing stripes, yard/goal lines, hashes,
// end zones, plus the blue line of scrimmage and yellow first-down line.
static float3 turfColor(float3 wp, constant FrameUniforms& fu) {
    const float tpy = 6.0;
    float2 f = float2(wp.x, -wp.z);
    int2 texel = int2(floor(f * tpy));
    float2 q = (float2(texel) + 0.5) / tpy;
    float n = hash21(float2(texel));
    float n2 = hash21(float2(texel / 3) + 17.0);

    bool inBounds = abs(q.x) <= kHalfWidth && q.y >= 0.0 && q.y <= 120.0;
    float3 g;
    if (inBounds) {
        float stripe = fmod(floor(q.y / 5.0), 2.0);
        g = mix(float3(0.055, 0.25, 0.045), float3(0.08, 0.33, 0.06), stripe);
        if (q.y < 10.0) g = mix(float3(0.30, 0.035, 0.04), float3(0.36, 0.05, 0.05), fmod(floor((q.x + q.y) / 2.0), 2.0));
        if (q.y > 110.0) g = mix(float3(0.035, 0.09, 0.40), float3(0.05, 0.12, 0.48), fmod(floor((q.x + q.y) / 2.0), 2.0));
    } else {
        g = float3(0.04, 0.17, 0.035);
    }
    g *= 0.86 + 0.18 * n + 0.08 * n2;

    const float3 white = float3(0.82);
    int row = texel.y;
    int rowsPerFive = int(5.0 * tpy);
    bool fieldOfPlay = abs(q.x) <= kHalfWidth && q.y >= 10.0 && q.y <= 110.0;
    // yard lines every 5 yards, goal lines doubled
    if (fieldOfPlay && (row % rowsPerFive == 0)) g = white;
    if (abs(q.x) <= kHalfWidth && (row == int(10.0 * tpy) - 1 || row == int(110.0 * tpy) - 1 ||
                                   row == int(110.0 * tpy))) g = white;
    // hash marks each yard (inbound + near-sideline)
    if (fieldOfPlay && row % int(tpy) == 0) {
        float ax = abs(q.x);
        if (abs(ax - 3.1) < 0.34 || abs(ax - (kHalfWidth - 1.0)) < 0.34) g = white;
    }
    // sidelines + end lines
    float ax = abs(q.x);
    if (ax > kHalfWidth && ax < kHalfWidth + 0.5 && q.y > -0.5 && q.y < 120.5) g = white;
    if (ax < kHalfWidth + 0.5 && ((q.y < 0.0 && q.y > -0.5) || (q.y > 120.0 && q.y < 120.5))) g = white;

    if (fu.field.z > 0.5 && ax <= kHalfWidth) {
        if (row == int(floor(fu.field.x * tpy))) g = float3(0.05, 0.25, 0.95);
        if (row == int(floor(fu.field.y * tpy)) && fu.field.y < 110.0) g = float3(0.95, 0.80, 0.05);
    }
    return g;
}

constexpr sampler shadowSampler(coord::normalized, filter::linear, address::clamp_to_edge, compare_func::less_equal);

static float sampleShadow(float4 lightPos, float3 normal, float3 lightDir, depth2d<float> shadowMap) {
    float3 p = lightPos.xyz / lightPos.w;
    float2 uv = p.xy * float2(0.5, -0.5) + 0.5;
    if (any(uv < 0.0) || any(uv > 1.0) || p.z > 1.0) return 1.0;
    float slope = 1.0 - saturate(dot(normal, -lightDir));
    float depth = p.z - (0.0012 + 0.0025 * slope);
    float2 texel = 1.0 / float2(shadowMap.get_width(), shadowMap.get_height());
    float sum = 0.0;
    for (int y = -1; y <= 1; y++) {
        for (int x = -1; x <= 1; x++) {
            sum += shadowMap.sample_compare(shadowSampler, uv + float2(x, y) * texel * 1.25, depth);
        }
    }
    return sum / 9.0;
}

fragment float4 scene_fragment(SceneOut in [[stage_in]],
                               constant FrameUniforms& fu [[buffer(0)]],
                               constant PointLight* lights [[buffer(1)]],
                               depth2d<float> shadowMap [[texture(0)]]) {
    uint flags = frameFlags(fu);
    float3 albedo = in.albedo;
    bool turf = in.material == MAT_TURF;
    if (turf) {
        albedo = turfColor(in.worldPos, fu);
    } else if ((flags & FLAG_PIXEL_NOISE) != 0u && in.material != MAT_EMISSIVE) {
        float3 texel = floor(in.local * 11.0 + 0.001);
        albedo *= 0.9 + 0.17 * hash21(texel.xy + texel.z * 7.31);
    }

    if (in.material == MAT_EMISSIVE) {
        return float4(albedo * (6.0 + in.emissive), 1.0);
    }

    float3 N = normalize(in.normal);
    float3 V = normalize(fu.cameraPos.xyz - in.worldPos);
    float3 L = -fu.lightDir.xyz;
    float wrap = fu.ambient.w;
    float diff = saturate((dot(N, L) + wrap) / (1.0 + wrap));
    float shadow = (flags & FLAG_SHADOWS) != 0u ? sampleShadow(in.lightPos, N, fu.lightDir.xyz, shadowMap) : 1.0;

    float3 hemi = mix(fu.groundAmbient.rgb, fu.ambient.rgb, N.y * 0.5 + 0.5);
    float3 lit = fu.lightColor.rgb * fu.lightDir.w * diff * shadow + hemi;

    uint lightCount = uint(fu.params.z);
    for (uint i = 0; i < lightCount; i++) {
        float3 d = lights[i].positionRadius.xyz - in.worldPos;
        float dist = length(d);
        float att = saturate(1.0 - dist / lights[i].positionRadius.w);
        att *= att;
        float nd = saturate((dot(N, d / dist) + wrap) / (1.0 + wrap));
        lit += lights[i].colorIntensity.rgb * lights[i].colorIntensity.w * att * nd;
    }

    // Floodlights pool on the field; the bowl falls off into darkness with height and distance from it.
    float3 wp = in.worldPos;
    float outside = max(abs(wp.x) - (kHalfWidth + 3.0), 0.0) + max(-wp.z - 124.0, 0.0) + max(wp.z - 6.0, 0.0);
    float pool = exp(-outside * 0.03) * exp(-max(wp.y - 1.5, 0.0) * 0.075);
    lit *= mix(0.03, 1.0, pool);

    float3 color = albedo * lit * in.ao;
    if (!turf) {
        float rim = pow(1.0 - saturate(dot(N, V)), 3.0);
        color += fu.lightColor.rgb * rim * fu.lightColor.w * (0.35 + 0.65 * shadow) * albedo * pool;
        if ((in.flags & INST_CONTROLLED) != 0u) color += float3(1.0, 0.85, 0.2) * rim * 0.35;
        if ((in.flags & INST_TURBO) != 0u) color += float3(1.0, 0.75, 0.15) * rim * 0.6;
    }

    float dist = distance(fu.cameraPos.xyz, in.worldPos);
    float fog = 1.0 - exp(-dist * fu.skyHorizon.w);
    color = mix(color, fu.skyHorizon.rgb * 0.6, fog);
    return float4(color, 1.0);
}

// MARK: - Sky

struct FullscreenOut { float4 position [[position]]; float2 uv; };

vertex FullscreenOut sky_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);
    FullscreenOut o;
    o.position = float4(p * 2.0 - 1.0, 1.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

fragment float4 sky_fragment(FullscreenOut in [[stage_in]], constant FrameUniforms& fu [[buffer(0)]]) {
    float2 ndc = float2(in.uv.x * 2.0 - 1.0, 1.0 - in.uv.y * 2.0);
    float4 p = fu.invViewProj * float4(ndc, 1.0, 1.0);
    float3 dir = normalize(p.xyz / p.w - fu.cameraPos.xyz);
    float up = saturate(dir.y);
    float3 sky = mix(fu.skyHorizon.rgb, fu.skyTop.rgb, pow(up, 0.45));
    // haze lit by the floodlight banks, strongest just above the rim of the stands
    sky += float3(0.06, 0.07, 0.1) * exp(-up * 6.0) * 0.5;

    if (dir.y > 0.04) {
        float2 sph = float2(atan2(dir.x, dir.z), asin(dir.y)) * 90.0;
        float2 cell = floor(sph);
        float h = hash21(cell);
        if (h > 0.965) {
            float2 c = fract(sph) - 0.5;
            float twinkle = 0.6 + 0.4 * sin(fu.cameraPos.w * (1.0 + h * 3.0) + h * 50.0);
            float star = step(length(c), 0.16) * twinkle * smoothstep(0.04, 0.25, dir.y);
            sky += float3(0.9, 0.95, 1.0) * star * (1.0 + 3.0 * fract(h * 91.0));
        }
    }
    return float4(sky, 1.0);
}

// MARK: - Floodlight glows (additive billboards)

struct GlowOut { float4 position [[position]]; float2 uv; float3 color; };

vertex GlowOut glow_vertex(uint vid [[vertex_id]], uint iid [[instance_id]],
                           const device Glow* glows [[buffer(0)]],
                           constant FrameUniforms& fu [[buffer(4)]]) {
    const float2 corners[6] = { float2(-1, -1), float2(1, -1), float2(1, 1), float2(-1, -1), float2(1, 1), float2(-1, 1) };
    Glow g = glows[iid];
    float2 c = corners[vid];
    float3 wp = g.positionSize.xyz + (fu.cameraRight.xyz * c.x + fu.cameraUp.xyz * c.y) * g.positionSize.w;
    GlowOut o;
    o.position = fu.viewProj * float4(wp, 1.0);
    o.uv = c;
    o.color = g.color.rgb;
    return o;
}

fragment float4 glow_fragment(GlowOut in [[stage_in]]) {
    float r2 = dot(in.uv, in.uv);
    float a = exp(-r2 * 5.0) * 0.6 + exp(-r2 * 60.0) * 2.0;
    return float4(in.color * a, 0.0);
}

// MARK: - Debug / gameplay overlay geometry

struct DebugOut { float4 position [[position]]; float4 color; };

vertex DebugOut debug_vertex(uint vid [[vertex_id]], const device DebugVertex* verts [[buffer(0)]],
                             constant FrameUniforms& fu [[buffer(4)]]) {
    DebugOut o;
    o.position = fu.viewProj * float4(verts[vid].position.xyz, 1.0);
    o.color = verts[vid].color;
    return o;
}

fragment float4 debug_fragment(DebugOut in [[stage_in]]) { return in.color; }

// Screen-space overlay (stat bars): positions are already NDC, colors already display-encoded.
vertex DebugOut overlay_vertex(uint vid [[vertex_id]], const device DebugVertex* verts [[buffer(0)]]) {
    DebugOut o;
    o.position = float4(verts[vid].position.xy, 0.0, 1.0);
    o.color = verts[vid].color;
    return o;
}

// MARK: - GPU culling

kernel void cull_instances(const device Instance* instances [[buffer(0)]],
                           constant CullUniforms& cu [[buffer(1)]],
                           device uint* visible [[buffer(2)]],
                           device IndexedIndirectArgs* args [[buffer(3)]],
                           uint gid [[thread_position_in_grid]]) {
    if (gid >= cu.instanceCount) return;
    Instance inst = instances[gid];
    if (cu.enabled != 0u) {
        float3 c = (inst.model * float4(inst.bounds.xyz, 1.0)).xyz;
        float s = max(length(inst.model[0].xyz), max(length(inst.model[1].xyz), length(inst.model[2].xyz)));
        float r = inst.bounds.w * s;
        for (int i = 0; i < 6; i++) {
            if (dot(cu.planes[i].xyz, c) + cu.planes[i].w < -r) return;
        }
        if (cu.lod.w > 0.0 && distance(c, cu.lod.xyz) > cu.lod.w) return;
    }
    uint slot = atomic_fetch_add_explicit(&args[cu.argsIndex].instanceCount, 1u, memory_order_relaxed);
    visible[cu.visibleOffset + slot] = gid;
}
