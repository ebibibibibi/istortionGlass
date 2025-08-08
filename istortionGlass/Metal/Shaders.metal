//
//  Shaders.metal
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

#include <metal_stdlib>
using namespace metal;

// Vertex input structure
struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

// Vertex output structure
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// Uniform data structure
struct Uniforms {
    float time;
    float2 resolution;
    int effectType;
    float strength;
    float2 center;
};

// Vertex shader
vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
    // Full-screen quad vertices
    float2 positions[4] = {
        float2(-1.0, -1.0),  // Bottom-left
        float2( 1.0, -1.0),  // Bottom-right
        float2(-1.0,  1.0),  // Top-left
        float2( 1.0,  1.0)   // Top-right
    };
    
    float2 texCoords[4] = {
        float2(0.0, 1.0),  // Bottom-left
        float2(1.0, 1.0),  // Bottom-right
        float2(0.0, 0.0),  // Top-left
        float2(1.0, 0.0)   // Top-right
    };
    
    VertexOut out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.texCoord = texCoords[vid];
    
    return out;
}

// Distortion functions
float2 fisheyeDistortion(float2 uv, float2 center, float strength) {
    float2 coord = uv - center;
    float distance = length(coord);
    
    if (distance == 0.0) {
        return uv;
    }
    
    float factor = 1.0 + strength * distance * distance;
    return center + coord * factor;
}

float2 rippleDistortion(float2 uv, float2 center, float strength, float time) {
    float2 coord = uv - center;
    float distance = length(coord);
    
    float ripple = sin(distance * 30.0 - time * 5.0) * strength * 0.02;
    float2 direction = normalize(coord);
    
    return uv + direction * ripple;
}

float2 swirlDistortion(float2 uv, float2 center, float strength, float time) {
    float2 coord = uv - center;
    float distance = length(coord);
    
    float angle = atan2(coord.y, coord.x);
    angle += strength * (1.0 - distance) * sin(time * 2.0);
    
    float2 rotated = float2(cos(angle), sin(angle)) * distance;
    return center + rotated;
}

// Fragment shader
fragment float4 fragment_main(VertexOut in [[stage_in]],
                             texture2d<float> inputTexture [[texture(0)]],
                             constant Uniforms& uniforms [[buffer(0)]]) {
    
    constexpr sampler textureSampler(mag_filter::linear,
                                   min_filter::linear);
    
    float2 uv = in.texCoord;
    float2 distortedUV = uv;
    
    // Apply distortion based on effect type
    switch (uniforms.effectType) {
        case 1: // Fisheye
            distortedUV = fisheyeDistortion(uv, uniforms.center, uniforms.strength);
            break;
            
        case 2: // Ripple
            distortedUV = rippleDistortion(uv, uniforms.center, uniforms.strength, uniforms.time);
            break;
            
        case 3: // Swirl
            distortedUV = swirlDistortion(uv, uniforms.center, uniforms.strength, uniforms.time);
            break;
            
        default: // No effect
            distortedUV = uv;
            break;
    }
    
    // Clamp UV coordinates to prevent sampling outside texture bounds
    distortedUV = clamp(distortedUV, 0.0, 1.0);
    
    // Sample the input texture
    float4 color = inputTexture.sample(textureSampler, distortedUV);
    
    return color;
}