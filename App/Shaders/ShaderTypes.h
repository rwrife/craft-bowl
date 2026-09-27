// Shared GPU data layouts. Mirrored 1:1 in Packages/CraftBowlKit/Sources/CBRender/ShaderTypes.swift —
// keep both in sync (only float4 / float4x4 / uint4-sized members to avoid packing surprises).
#pragma once
#include <metal_stdlib>
using namespace metal;

// Material IDs stored in Vertex.color.a
#define MAT_PLAIN      0
#define MAT_SKIN       1
#define MAT_PRIMARY    2
#define MAT_SECONDARY  3
#define MAT_HELMET     4
#define MAT_PANTS      5
#define MAT_TRIM       6
#define MAT_EMISSIVE   7
#define MAT_TURF       8
#define MAT_CROWD      9
#define MAT_STRIPE     10
#define MAT_FACEMASK   11

// Instance.params.z flags
#define INST_CROWD       1u
#define INST_CONTROLLED  2u
#define INST_TURBO       4u

// FrameUniforms.params.w debug/feature flags
#define FLAG_SHADOWS     1u
#define FLAG_PIXEL_NOISE 2u
#define FLAG_FIELD_LINES 4u

#define NO_BONES 0xFFFFFFFFu

struct Vertex {
    float4 position;   // xyz model space, w = bone index
    float4 normal;     // xyz, w = baked ambient occlusion
    float4 color;      // rgb base color, a = material id
};

struct Instance {
    float4x4 model;
    float4 tint;       // rgb tint (crowd shirts / plain materials), a = emissive boost
    uint4 params;      // x team (0 home, 1 away, 2 none), y bone offset or NO_BONES, z flags, w skin | number<<8 | seed<<16
    float4 bounds;     // local bounding sphere: xyz center, w radius
};

struct FrameUniforms {
    float4x4 viewProj;
    float4x4 invViewProj;
    float4x4 lightViewProj;
    float4 cameraPos;      // xyz, w = time (s)
    float4 cameraRight;    // xyz world-space camera right, w unused
    float4 cameraUp;       // xyz world-space camera up, w unused
    float4 lightDir;       // xyz direction the key light travels, w = intensity
    float4 lightColor;     // rgb, w = rim strength
    float4 skyTop;         // rgb, w = exposure
    float4 skyHorizon;     // rgb, w = fog density
    float4 ambient;        // rgb hemisphere sky ambient, w = wrap factor
    float4 groundAmbient;  // rgb hemisphere ground ambient, w = unused
    float4 params;         // x crowd excitement, y render scale, z light count, w flags (as float bits)
    float4 field;          // x line of scrimmage (field y), y first-down line, z show lines, w unused
    float4 viewport;       // render w, h (pixels actually rendered), 1/w, 1/h of the full target
};

struct PointLight {
    float4 positionRadius;
    float4 colorIntensity;
};

struct TeamColors {
    float4 primary, secondary, trim, helmet, stripe, pants, numberFill, numberOutline;
};

struct DrawParams {
    uint visibleOffset;
    uint useVisible;
    uint instanceBase;
    uint pad;
};

struct CullUniforms {
    float4 planes[6];
    float4 lod;            // xyz camera position, w max draw distance (0 = unlimited)
    uint instanceCount;
    uint visibleOffset;
    uint argsIndex;
    uint enabled;
};

struct IndexedIndirectArgs {
    uint indexCount;
    atomic_uint instanceCount;
    uint indexStart;
    int baseVertex;
    uint baseInstance;
};

struct Glow {
    float4 positionSize;   // xyz world, w size (yards)
    float4 color;          // rgb HDR
};

struct DebugVertex {
    float4 position;       // xyz world
    float4 color;
};

struct PostUniforms {
    float4 source;         // xy uv scale of source content, zw 1/source texel size
    float4 bloom;          // x threshold, y knee, z intensity, w enabled
    float4 grade;          // x exposure, y LUT enabled, z vignette strength, w LUT size
    float4 misc;           // x time, y chromatic aberration, zw unused
};
