//
//  Shaders.metal
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

#include <metal_stdlib>
using namespace metal;

// ===================== 共通データ構造 =====================

// 頂点入力（属性）
// ※このファイルでは下の vertex_main は [[vertex_id]] を使って
//   フルスクリーンクアッドを“コードで”生成しているため未使用。
//   「頂点バッファの中身を読みたい」場合は vertex_main を
//   `vertex VertexOut vertex_main(VertexIn in [[stage_in]])` に差し替える。
struct VertexIn {
    float2 position [[attribute(0)]];
    float2 texCoord [[attribute(1)]];
};

// 頂点→フラグメントへ渡す出力
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// CPU側（Swift）の Uniforms と**レイアウト/順序を一致**させること！
// Swift側: Float(4) + float2(8) + int32(4) + float(4) + float2(8)
// Metal側: float(4) + float2(8) + int(4) + float(4) + float2(8)
struct Uniforms {
    float  time;        // アニメーション等の時間（秒）
    float2 resolution;  // 出力解像度（px）
    int    effectType;  // 0..N（Swift側の enum.rawValue と一致）
    float  strength;    // 効果の強さ（0..1）
    float2 center;      // 画面中心（UV空間 0..1）
};

// ===================== 頂点シェーダ =====================

// 今回は“フルスクリーンクアッド”を CPU から送らず、シェーダ側で生成する。
// .triangleStrip で 4 頂点を描けば画面全体を覆える。
vertex VertexOut vertex_main(uint vid [[vertex_id]]) {
    // クリップ空間の頂点座標（-1..1）
    float2 positions[4] = {
        float2(-1.0, -1.0),  // Bottom-left
        float2( 1.0, -1.0),  // Bottom-right
        float2(-1.0,  1.0),  // Top-left
        float2( 1.0,  1.0)   // Top-right
    };

    // テクスチャ座標（0..1）
    // ※カメラ入力の上下反転がある場合はここのVを入れ替える
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

// ===================== エフェクト関数群 =====================

// 高品質フィッシュアイ（樽型歪み r' = r * (1 + k1 r^2 + k2 r^4)）
float2 fisheyeDistortion(float2 uv, float2 center, float strength) {
    float2 coord = uv - center;
    float  r     = length(coord);

    // 中央は歪ませない（分岐で分母ゼロ/ノイズ回避）
    if (r < 1e-3) return uv;

    // 0..1 を 0..2 に拡げて可動域を取りやすく
    float s  = strength * 2.0;
    float r2 = r * r;
    float r4 = r2 * r2;

    float k1 = s * 0.5;
    float k2 = s * 0.1;

    float factor = 1.0 + k1 * r2 + k2 * r4;
    factor = clamp(factor, 0.1, 3.0); // 端の暴れを抑制

    return center + coord * factor;
}

// 軽量フィッシュアイ（単一係数の簡易版）
float2 fisheyeDistortionFast(float2 uv, float2 center, float strength) {
    float2 coord = uv - center;
    float  r     = length(coord);
    if (r < 1e-3) return uv;

    float k   = strength * 1.5;
    float r2  = r * r;
    float fac = 1.0 + k * r2;
    fac = clamp(fac, 0.2, 2.5);
    return center + coord * fac;
}

// 波紋
float2 rippleDistortion(float2 uv, float2 center, float strength, float time) {
    float2 coord = uv - center;
    float  r     = length(coord);

    float  ripple    = sin(r * 30.0 - time * 5.0) * strength * 0.02;
    float2 direction = (r > 1e-5) ? (coord / r) : float2(0.0, 0.0);

    return uv + direction * ripple;
}

// うずまき
float2 swirlDistortion(float2 uv, float2 center, float strength, float time) {
    float2 coord = uv - center;
    float  r     = length(coord);

    float angle = atan2(coord.y, coord.x);
    angle += strength * (1.0 - r) * sin(time * 2.0);

    float2 rotated = float2(cos(angle), sin(angle)) * r;
    return center + rotated;
}

// ===================== フラグメントシェーダ =====================

// パススルー（基準パス/デバッグ用）
fragment float4 fragment_passthrough(VertexOut in [[stage_in]],
                                     texture2d<float> inputTexture [[texture(0)]]) {
    // サンプラー：線形補間 + 端はクランプ（歪みで範囲外に出がちなのでrepeatは避ける）
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::clamp_to_edge);

    return inputTexture.sample(textureSampler, in.texCoord);
}

// メイン（エフェクトあり）
fragment float4 fragment_main(VertexOut in [[stage_in]],
                              texture2d<float> inputTexture [[texture(0)]],
                              constant Uniforms& uniforms [[buffer(0)]]) {
    constexpr sampler textureSampler(mag_filter::linear,
                                     min_filter::linear,
                                     address::clamp_to_edge);

    float2 uv = in.texCoord;
    float2 distortedUV = uv;
    float  edgeFade = 1.0; // 端のフェード（fisheye向け）

    // エフェクト切替（Swift 側 enum.rawValue と同期）
    switch (uniforms.effectType) {
        case 1: // Fisheye HQ
            distortedUV = fisheyeDistortion(uv, uniforms.center, uniforms.strength);
            break;
        case 2: // Fisheye Fast
            distortedUV = fisheyeDistortionFast(uv, uniforms.center, uniforms.strength);
            break;
        case 3: // Ripple
            distortedUV = rippleDistortion(uv, uniforms.center, uniforms.strength, uniforms.time);
            break;
        case 4: // Swirl
            distortedUV = swirlDistortion(uv, uniforms.center, uniforms.strength, uniforms.time);
            break;
        default: // None
            distortedUV = uv;
            break;
    }

    // 歪ませた座標が 0..1 の範囲にいるか
    bool inBounds = all(distortedUV >= 0.0) && all(distortedUV <= 1.0);

    float4 color;
    if (inBounds) {
        color = inputTexture.sample(textureSampler, distortedUV);

        // フィッシュアイ時は端の黒浮きをなだらかにフェード
        if (uniforms.effectType == 1 || uniforms.effectType == 2) {
            float  r = length(distortedUV - uniforms.center);
            float  fadeRadius = 0.4; // ここから薄く
            float  maxRadius  = 0.7; // ここでゼロ
            edgeFade = 1.0 - smoothstep(fadeRadius, maxRadius, r);
        }
    } else {
        // 範囲外は黒（必要なら last-sample / border-color 等に変更可）
        color = float4(0.0, 0.0, 0.0, 1.0);
        edgeFade = 0.0;
    }

    color.rgb *= edgeFade;
    return color;
}
