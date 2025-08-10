//
//  CameraPreviewView.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import SwiftUI
import MetalKit
import CoreMedia

/// MTKView（画面）← MetalRenderer（描画）← CameraManager（入力）
/// SwiftUI から UIKit の MTKView を使うためのブリッジ。
/// - MTKView: CAMetalLayer を内包する描画ビュー（display link で draw を回す）
/// - Coordinator: MTKViewDelegate & CameraManagerDelegate を束ねる仲介（状態はここに持つ）
/// - CameraManager: カメラから来たフレームを MTLTexture にして通知
struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager

    // これらは UI 側から渡される「描画パラメータ」
    var currentEffect: MetalRenderer.DistortionEffect = .none
    var effectStrength: Float = 1.0
    var isPassthroughMode: Bool = false
    var performanceMonitor: PerformanceMonitor?

    // 補足: 参照は Coordinator 側でもつので、ここで @State に保持する必要は基本ない
    @State private var metalView: MTKView?
    @State private var renderer: MetalRenderer?

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }

        let mtkView = MTKView()
        mtkView.device = device
        mtkView.delegate = context.coordinator

        // framebufferOnly:
        //   画面への「描画のみ」なら true の方が速い（最適化される）。
        //   Drawable をテクスチャとしてサンプリング等するなら false が必要。
        // このアプリは描画のみなので true 推奨（必要なら false に戻す）
        mtkView.framebufferOnly = true

        // ピクセルフォーマットは RenderPipeline と一致させること（.bgra8Unorm）
        mtkView.colorPixelFormat = .bgra8Unorm

        // 描画モード: 連続描画（display link 駆動）
        mtkView.preferredFramesPerSecond = 30
        mtkView.enableSetNeedsDisplay = false // 手動トリガを使わない
        mtkView.isPaused = false              // 常時 draw(in:) が呼ばれる

        // Renderer 構築（デバイス共有）
        let metalRenderer = MetalRenderer(device: device)
        metalRenderer.performanceMonitor = performanceMonitor

        // CameraManager からのテクスチャ通知を受ける
        cameraManager.delegate = context.coordinator

        // SwiftUI 側でも参照が欲しい場合だけ保持（なくてもOK）
        DispatchQueue.main.async {
            self.metalView = mtkView
            self.renderer = metalRenderer
        }

        // Coordinator にも渡す（実体のオーナーはこっち）
        context.coordinator.metalView = mtkView
        context.coordinator.renderer = metalRenderer
        context.coordinator.parent = self

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // 最新のパラメータを Renderer へ反映（強度はリアルタイム更新）
        context.coordinator.parent = self
        context.coordinator.renderer?.setEffect(currentEffect, strength: effectStrength)
        context.coordinator.renderer?.setPassthroughMode(isPassthroughMode)
        context.coordinator.renderer?.updateEffectStrength(effectStrength)
    }

    func makeCoordinator() -> Coordinator { Coordinator() }

    // MARK: - Coordinator
    class Coordinator: NSObject, MTKViewDelegate, CameraManagerDelegate {
        var metalView: MTKView?
        var renderer: MetalRenderer?
        var parent: CameraPreviewView?
        private var currentTexture: MTLTexture?

        // ==== MTKViewDelegate ====

        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // 画面回転・サイズ変更時の対応が必要ならここで（頂点/UV/解像度の再設定等）
        }

        func draw(in view: MTKView) {
            // 連続描画モードでは display link ごとに呼ばれる
            guard let drawable = view.currentDrawable,
                  let renderer = renderer,
                  let texture = currentTexture else { return }

            // CPU→GPU コマンド発行（非同期）: present まで renderer 内で行う
            renderer.render(to: drawable, with: texture)
        }

        // ==== CameraManagerDelegate ====

        func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
            // 生のサンプルが必要ならここで追加処理（録画/解析など）
            // CameraManager 側で main に切り戻してくれている想定
        }

        func cameraManager(_ manager: CameraManager, didUpdatePreview texture: MTLTexture?) {
            // 最新フレームのテクスチャを保持（Renderer は draw 時に読む）
            currentTexture = texture

            // 連続描画モードでは setNeedsDisplay は不要。
            // もし「オンデマンド描画」に切り替えるなら:
            //  - view.enableSetNeedsDisplay = true
            //  - view.isPaused = true
            //  - ここで view.setNeedsDisplay() / view.draw() を呼ぶ
            // 今は連続モードなのでトリガは不要。
        }
    }
}

// Preview support
#Preview {
    CameraPreviewView(
        cameraManager: CameraManager(),
        currentEffect: .none,
        effectStrength: 1.0,
        isPassthroughMode: false,
        performanceMonitor: PerformanceMonitor()
    )
}
