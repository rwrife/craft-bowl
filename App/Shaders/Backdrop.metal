#include <metal_stdlib>
using namespace metal;

// Procedural placeholder backdrop: night sky + floodlit turf with yard lines.
// Proves the pipeline end to end until the real stadium scene lands (issues S1/S2).

struct VOut { float4 position [[position]]; float2 uv; };

vertex VOut backdrop_vertex(uint vid [[vertex_id]]) {
    float2 p = float2((vid << 1) & 2, vid & 2);   // fullscreen triangle
    VOut o;
    o.position = float4(p * 2.0 - 1.0, 0.0, 1.0);
    o.uv = float2(p.x, 1.0 - p.y);
    return o;
}

fragment float4 backdrop_fragment(VOut in [[stage_in]], constant float4 &u [[buffer(0)]]) {
    float2 uv = in.uv;
    float horizon = 0.38;
    // Pixelate to a chunky grid for the retro look.
    float2 px = floor(uv * float2(320.0, 180.0)) / float2(320.0, 180.0);
    if (px.y < horizon) {
        float t = px.y / horizon;
        float3 sky = mix(float3(0.01, 0.02, 0.07), float3(0.06, 0.10, 0.25), t);
        // Floodlight glows
        for (int i = 0; i < 4; i++) {
            float2 c = float2(0.14 + 0.24 * i, 0.06);
            sky += float3(1.0, 0.95, 0.8) * 0.02 / (distance(px, c) + 0.02);
        }
        return float4(sky, 1.0);
    }
    // Perspective turf
    float depth = (px.y - horizon) / (1.0 - horizon);
    float z = 1.0 / max(depth, 0.02);
    float yard = fract(z * 1.5 - u.x * 0.2);
    float3 grass = mix(float3(0.13, 0.45, 0.12), float3(0.18, 0.56, 0.16), step(0.5, fract(z * 0.75)));
    float line = step(0.96, yard) * step(0.03, depth);
    float3 col = mix(grass, float3(0.95), line);
    col *= 0.75 + 0.25 * depth;
    return float4(col, 1.0);
}
