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

// Advanced fisheye distortion with improved accuracy and edge handling
float2 fisheyeDistortion(float2 uv, float2 center, float strength) {
    // Convert UV coordinates to centered coordinates (-0.5 to 0.5)
    float2 coord = uv - center;
    float distance = length(coord);
    
    // Early return for center point
    if (distance < 0.001) {
        return uv;
    }
    
    // Normalize strength parameter (0.0 to 1.0 maps to usable range)
    float normalizedStrength = strength * 2.0; // Scale to 0.0-2.0 for better control
    
    // Apply fisheye transformation using barrel distortion formula
    // r' = r * (1 + k1*r^2 + k2*r^4)
    float r2 = distance * distance;
    float r4 = r2 * r2;
    
    // Coefficients for fisheye effect
    float k1 = normalizedStrength * 0.5;
    float k2 = normalizedStrength * 0.1;
    
    float distortionFactor = 1.0 + k1 * r2 + k2 * r4;
    
    // Clamp distortion to prevent extreme values at edges
    distortionFactor = clamp(distortionFactor, 0.1, 3.0);
    
    // Apply distortion
    float2 distortedCoord = coord * distortionFactor;
    
    // Return to original coordinate space
    return center + distortedCoord;
}

// Optimized fisheye distortion for better performance
float2 fisheyeDistortionFast(float2 uv, float2 center, float strength) {
    float2 coord = uv - center;
    float distance = length(coord);
    
    // Fast early exit
    if (distance < 0.001) return uv;
    
    // Simplified barrel distortion with single coefficient
    float k = strength * 1.5;
    float r2 = distance * distance;
    float factor = 1.0 + k * r2;
    
    // Clamp for stability
    factor = clamp(factor, 0.2, 2.5);
    
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

// Passthrough fragment shader (for debugging and baseline performance)
fragment float4 fragment_passthrough(VertexOut in [[stage_in]],
                                    texture2d<float> inputTexture [[texture(0)]]) {
    
    constexpr sampler textureSampler(mag_filter::linear,
                                   min_filter::linear,
                                   address::clamp_to_edge);
    
    // Direct passthrough - no processing, just display the camera input
    float4 color = inputTexture.sample(textureSampler, in.texCoord);
    return color;
}

// Main fragment shader with effects and improved edge handling
fragment float4 fragment_main(VertexOut in [[stage_in]],
                             texture2d<float> inputTexture [[texture(0)]],
                             constant Uniforms& uniforms [[buffer(0)]]) {
    
    constexpr sampler textureSampler(mag_filter::linear,
                                   min_filter::linear,
                                   address::clamp_to_edge);
    
    float2 uv = in.texCoord;
    float2 distortedUV = uv;
    float edgeFade = 1.0; // For smooth edge transitions
    
    // Apply distortion based on effect type
    switch (uniforms.effectType) {
        case 1: // Fisheye (High Quality)
            distortedUV = fisheyeDistortion(uv, uniforms.center, uniforms.strength);
            break;
            
        case 2: // Fisheye (Fast Performance)
            distortedUV = fisheyeDistortionFast(uv, uniforms.center, uniforms.strength);
            break;
            
        case 3: // Ripple
            distortedUV = rippleDistortion(uv, uniforms.center, uniforms.strength, uniforms.time);
            break;
            
        case 4: // Swirl
            distortedUV = swirlDistortion(uv, uniforms.center, uniforms.strength, uniforms.time);
            break;
            
        default: // No effect (passthrough)
            distortedUV = uv;
            break;
    }
    
    // Check if distorted coordinates are within bounds
    bool inBounds = all(distortedUV >= 0.0) && all(distortedUV <= 1.0);
    
    float4 color;
    if (inBounds) {
        // Sample the input texture
        color = inputTexture.sample(textureSampler, distortedUV);
        
        // Apply edge fade for fisheye effects
        if (uniforms.effectType == 1 || uniforms.effectType == 2) {
            float2 fromCenter = distortedUV - uniforms.center;
            float distanceFromCenter = length(fromCenter);
            
            // Create smooth fade at edges (beyond certain radius)
            float fadeRadius = 0.4; // Start fading at 40% from center
            float maxRadius = 0.7;  // Complete fade at 70% from center
            
            if (distanceFromCenter > fadeRadius) {
                edgeFade = 1.0 - smoothstep(fadeRadius, maxRadius, distanceFromCenter);
            }
        }
    } else {
        // Use black for out-of-bounds areas with fisheye
        color = float4(0.0, 0.0, 0.0, 1.0);
        edgeFade = 0.0;
    }
    
    // Apply edge fading
    color.rgb *= edgeFade;
    
    return color;
}