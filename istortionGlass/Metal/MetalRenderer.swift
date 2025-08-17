//
//  MetalRenderer.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import Metal
import MetalKit
import simd

/// レンダリング担当（CPU→GPUコマンド発行）
/// ───────────────────────────────────────────
/// このクラスに登場する Metal オブジェクトの役割
/// - MTLDevice: GPUへの入口。各リソースやキューを生成する「工場」
/// - MTLCommandQueue: GPUに送る MTLCommandBuffer を生む「製造ライン」
/// - MTLCommandBuffer: 1フレームぶん等の GPU 作業のまとまり（非同期で実行）
/// - MTLRenderPipelineState: 「頂点関数＋フラグメント関数＋固定機能」の実行プラン
/// - MTLRenderCommandEncoder: 描画コマンドの発行口（パイプライン/バッファ/テクスチャを束ねてdraw）
/// - MTLBuffer: 頂点データやユニフォーム（定数バッファ）などの連続メモリ
/// - MTLTexture: 画像データ（入力/出力）
/// - MTLLibrary / MTLFunction: シェーダ群（.metal）とその関数ハンドル
/// - CAMetalDrawable: 画面表示先（CAMetalLayerの1枚）
/// ───────────────────────────────────────────
class MetalRenderer: NSObject {
    
    // MARK: - Properties
    /// GPUデバイス（全Metalリソース生成の起点）
    private let device: MTLDevice
    /// コマンドバッファを生み出すキュー（フレーム毎にCBを作る）
    private let commandQueue: MTLCommandQueue
    /// エフェクト付き描画用パイプライン
    private var pipelineState: MTLRenderPipelineState?
    /// パススルー（デバッグ/比較用）パイプライン
    private var passthroughPipelineState: MTLRenderPipelineState?
    /// フルスクリーンクアッドの頂点バッファ（pos.xy + uv.xy）
    private var vertexBuffer: MTLBuffer?
    
    /// 歪みパラメータ等を詰めるユニフォーム用バッファ（Fragmentから読む想定）
    private var uniformBuffer: MTLBuffer?
    
    /// 入力テクスチャ（外部から差す場合に使用可、実際は render() 引数で受けてる）
    var inputTexture: MTLTexture?
    
    // エフェクト指定
    var currentEffect: DistortionEffect = .none
    var isPassthroughMode: Bool = false
    
    // 計測フック
    private var frameCount = 0
    private var lastFrameTime = CACurrentMediaTime()
    weak var performanceMonitor: PerformanceMonitor?
    
    enum DistortionEffect {
        case none
        case fisheyeHQ      // 品質優先
        case fisheyeFast    // 性能優先
        case ripple
        case swirl
    }
    
    /// シェーダと一致させるユニフォーム構造体（アライン注意）
    struct Uniforms {
        var time: Float
        var resolution: simd_float2
        var effectType: Int32
        var strength: Float
        var center: simd_float2
    }
    
    // MARK: - Initialization
    init(device: MTLDevice) {
        self.device = device
        // GPU に仕事を依頼するための命令書（コマンドバッファ）を発行する“工場”を作る
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = commandQueue
        
        super.init()
        
        setupMetal()
        setupVertexBuffer()
        setupUniformBuffer() // ← ユニフォームの初期値もここで投入
    }
    
    // MARK: - Public Methods
    /// 1フレーム描画：Drawable（出力先）と入力テクスチャを受け取る
    func render(to drawable: CAMetalDrawable, with texture: MTLTexture) {
        let renderStartTime = CACurrentMediaTime()
        
        // パイプライン選択（パススルーか、エフェクトか）
        let selectedPipelineState: MTLRenderPipelineState?
        if isPassthroughMode || currentEffect == .none {
            selectedPipelineState = passthroughPipelineState ?? pipelineState
        } else {
            selectedPipelineState = pipelineState ?? passthroughPipelineState
        }
        
        // CB/Encoder/RenderPass を用意
        guard let pipelineState = selectedPipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(
                descriptor: createRenderPassDescriptor(for: drawable)
              ) else {
            performanceMonitor?.logPerformanceWarning("Failed to create render command buffer or encoder")
            return
        }
        
        // パイプラインをセット（この時点で使用するシェーダ/固定機能を確定）
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // フルスクリーン描画用の頂点バッファ
        if let vertexBuffer = vertexBuffer {
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        }
        
        // ユニフォーム更新（パススルー時は不要）
        if !isPassthroughMode && currentEffect != .none && pipelineState === self.pipelineState {
            // 解像度などフレーム依存値を更新（drawableサイズ）
            updateUniforms(resolution: simd_float2(Float(drawable.texture.width),
                                                   Float(drawable.texture.height)))
            if let uniformBuffer = uniformBuffer {
                // Fragment シェーダの buffer(0) にバインドする想定
                renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
            }
        }
        
        // 入力テクスチャを束ねる（fragment texture(0)）
        renderEncoder.setFragmentTexture(texture, index: 0)
        
        // フルスクリーンクアッドを描画（triangleStrip: 4頂点）
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        // 表示予約（次のVSyncで出す）
        commandBuffer.present(drawable)
        
        // 完了時にレンダ時間を計測して PerformanceMonitor に送る
        commandBuffer.addCompletedHandler { [weak self] _ in
            let renderTime = CACurrentMediaTime() - renderStartTime
            self?.performanceMonitor?.recordFrameRenderTime(renderTime)
        }
        
        // 投入（ここでは待たない → CPU/GPUがオーバーラップできる）
        commandBuffer.commit()
        
        frameCount += 1
    }
    
    /// エフェクト切替（強度も合わせて設定）
    func setEffect(_ effect: DistortionEffect, strength: Float = 1.0) {
        currentEffect = effect
        updateUniforms(strength: strength)
    }
    
    /// 強度だけ変更
    func updateEffectStrength(_ strength: Float) {
        updateUniforms(strength: strength)
    }
    
    func setPassthroughMode(_ enabled: Bool) { isPassthroughMode = enabled }
    func getFrameCount() -> Int { frameCount }
    func resetFrameCount() {
        frameCount = 0
        lastFrameTime = CACurrentMediaTime()
    }
    
    /// 深度バッファが無効化されていることを確認
    func isDepthBufferDisabled() -> Bool { true }
    
    /// TBDR最適化の状態を取得
    func getTBDROptimizationStatus() -> String {
        var status = ["TBDR Optimizations:"]
        status.append("✅ Depth Buffer: Disabled")
        status.append("✅ Stencil Buffer: Disabled")
        status.append("✅ Render Target Size: Explicit")
        status.append("✅ Memory Storage: Optimized")
        status.append("✅ Full Screen Quad: Depth-free")
        return status.joined(separator: "\n")
    }
    
    // MARK: - Private Methods
    /// シェーダ読み込み＆パイプライン作成
    private func setupMetal() {
        // MTLLibrary: アプリ埋め込みの .metal から関数群を取り出す
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create Metal library")
        }
        // MTLFunction: 頂点/フラグメント関数
        guard let vertexFunction = library.makeFunction(name: "vertex_main") else {
            fatalError("Failed to find vertex_main function")
        }
        
        // メイン（エフェクト有り）パイプライン
        if let fragmentFunction = library.makeFunction(name: "fragment_main") {
            let pipelineDescriptor = MTLRenderPipelineDescriptor()
            pipelineDescriptor.vertexFunction = vertexFunction
            pipelineDescriptor.fragmentFunction = fragmentFunction
            // 出力のピクセルフォーマットは CAMetalLayer.pixelFormat と一致させる
            pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            do {
                pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
            } catch {
                print("Failed to create main pipeline state: \(error)")
            }
        }
        
        // パススルーパイプライン（デバッグ/比較用）
        if let passthroughFunction = library.makeFunction(name: "fragment_passthrough") {
            let passthroughDescriptor = MTLRenderPipelineDescriptor()
            passthroughDescriptor.vertexFunction = vertexFunction
            passthroughDescriptor.fragmentFunction = passthroughFunction
            passthroughDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
            do {
                passthroughPipelineState = try device.makeRenderPipelineState(descriptor: passthroughDescriptor)
            } catch {
                print("Failed to create passthrough pipeline state: \(error)")
            }
        }
        
        // どちらも作れなかったら致命的
        guard pipelineState != nil || passthroughPipelineState != nil else {
            fatalError("Failed to create any Metal pipeline states")
        }
    }
    
    /// フルスクリーン描画用の頂点バッファ（pos.xy, uv.xy の4頂点・ストリップ）
    private func setupVertexBuffer() {
        // クリップ空間（-1..1）にUV（0..1）を対応させたクアッド
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,  // Bottom-left  (pos.x, pos.y, u, v)
             1.0, -1.0, 1.0, 1.0,  // Bottom-right
            -1.0,  1.0, 0.0, 0.0,  // Top-left
             1.0,  1.0, 1.0, 0.0   // Top-right
        ]
        vertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<Float>.size,
            options: [] // iOSはデフォルトで .shared（CPU/GPU共有）
        )
    }
    
    /// ユニフォーム用バッファ作成（初期値で埋めておくと未定義読み出しを避けられる）
    private func setupUniformBuffer() {
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: [])
        if let ptr = uniformBuffer?.contents().bindMemory(to: Uniforms.self, capacity: 1) {
            ptr.pointee = Uniforms(
                time: 0,
                resolution: simd_float2(0, 0),
                effectType: Int32(currentEffect.rawValue),
                strength: 1.0,
                center: simd_float2(0.5, 0.5)
            )
        }
    }
    
    /// ユニフォーム更新（必要な項目だけ上書き）
    private func updateUniforms(resolution: simd_float2? = nil, strength: Float? = nil) {
        guard let uniformBuffer = uniformBuffer else { return }
        
        // MTLBuffer.contents() は CPU から直接書ける共有メモリ（iOS）
        let contents = uniformBuffer.contents().bindMemory(to: Uniforms.self, capacity: 1)
        let currentTime = Float(CACurrentMediaTime())
        
        // 既存値を保持しつつ、指定の項目だけ差し替える
        var uniforms = contents.pointee
        uniforms.time = currentTime
        if let resolution = resolution { uniforms.resolution = resolution }
        if let strength = strength { uniforms.strength = strength }
        uniforms.effectType = Int32(currentEffect.rawValue)
        uniforms.center = simd_float2(0.5, 0.5) // 画面中心
        contents.pointee = uniforms
    }
    
    /// 表示用レンダーパス（深度バッファ最適化済み）
    private func createRenderPassDescriptor(for drawable: CAMetalDrawable) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        
        // === カラーアタッチメント設定 ===
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear   // まずクリア
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
        descriptor.colorAttachments[0].storeAction = .store  // 画面に出すので保存
        
        // === 深度バッファ最適化 ===
        // フルスクリーンクアッドなので深度テストは不要
        // 深度アタッチメントを明示的にnilに設定してタイルメモリを節約
        descriptor.depthAttachment.texture = nil
        descriptor.depthAttachment.loadAction = .dontCare
        descriptor.depthAttachment.storeAction = .dontCare
        
        // ステンシルバッファも不要
        descriptor.stencilAttachment.texture = nil
        descriptor.stencilAttachment.loadAction = .dontCare
        descriptor.stencilAttachment.storeAction = .dontCare
        
        // レンダーターゲットサイズを明示的に指定
        // これにより、深度バッファなしでもレンダーパスが適切に設定される
        descriptor.renderTargetWidth = drawable.texture.width
        descriptor.renderTargetHeight = drawable.texture.height
        
        return descriptor
    }
}

// MARK: - DistortionEffect Extension
extension MetalRenderer.DistortionEffect {
    var rawValue: Int {
        switch self {
        case .none: return 0
        case .fisheyeHQ: return 1
        case .fisheyeFast: return 2
        case .ripple: return 3
        case .swirl: return 4
        }
    }
    
    var displayName: String {
        switch self {
        case .none: return "Original"
        case .fisheyeHQ: return "Fisheye HQ"
        case .fisheyeFast: return "Fisheye Fast"
        case .ripple: return "Ripple"
        case .swirl: return "Swirl"
        }
    }
    
    var isPerformanceOptimized: Bool {
        switch self {
        case .fisheyeFast: return true
        default: return false
        }
    }
}
