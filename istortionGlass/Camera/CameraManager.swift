//
//  CameraManager.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

// カメラI/O専任（CPU側）
// ───────────────────────────────────────────
// このファイルに登場する Metal 系オブジェクトの役割
// - MTLDevice: GPU との入り口。各種リソースやキューを「生成する工場」
// - MTLCommandQueue: GPU に流すコマンドバッファを作る「製造ライン」
//                   （このファイルでは“保持”のみ。実際の描画は別層で使用）
// - MTLTexture: GPU（または共有メモリ）上の画像データ本体（テクスチャ）
// - CVMetalTextureCache: CoreVideoのPixelBufferをMetalのTextureへ橋渡しするキャッシュ
//                        多くの場合 IOSurface 共有によりコピーなし/低コストで変換できる
// ───────────────────────────────────────────

import AVFoundation
import Metal
import MetalKit
import SwiftUI
import Combine

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager, didUpdatePreview texture: MTLTexture?)
}

class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var hasPermission = false
    @Published var previewTexture: MTLTexture?
    @Published var fps: Int = 0
    @Published var errorMessage: String?
    
    // MARK: - Private Properties
    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    
    // CPU並行処理用のシリアルキューを2本。
    // 同一キュー内は順次実行、別キュー間は並行に進められる。
    private let captureQueue = DispatchQueue(label: "camera.capture.queue", qos: .userInteractive)
    private let textureQueue = DispatchQueue(label: "texture.processing.queue", qos: .userInteractive)
    
    // Metal properties
    // MTLDevice: GPUデバイスのハンドル。各種Metalオブジェクト生成の起点。
    private let device: MTLDevice
    // MTLCommandQueue: コマンドバッファを生み出すキュー（製造ライン）。
    // このクラスはカメラI/O担当なので、描画は別オブジェクトで行い、ここでは共有/保持のみ。
    private let commandQueue: MTLCommandQueue
    // CVMetalTextureCache: CVPixelBuffer →（ラップ）→ MTLTexture を作るブリッジ兼キャッシュ。
    // 連続フレームでも割り当て負荷を抑え、ゼロコピー/低コピーでGPUが読める形にする。
    private var textureCache: CVMetalTextureCache?
    
    // FPS tracking（目安用カウンタ）
    private var frameCount = 0
    private var lastTimestamp = CACurrentMediaTime()
    private let fpsUpdateInterval: TimeInterval = 1.0
    
    // Error handling（連続失敗時に停止して通知）
    private var consecutiveTextureFailures = 0
    private let maxConsecutiveFailures = 10
    
    weak var delegate: CameraManagerDelegate?
    
    // MARK: - Initialization
    override init() {
        // MTLDevice: システム標準のGPUを取得。
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        // MTLCommandQueue: 後段（レンダラ）が使うコマンドバッファの製造ラインを用意。
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        super.init()
        
        // CVMetalTextureCache: PixelBuffer→Texture 変換のキャッシュを作成。
        // これにより各フレームのラップ作成コストを抑えられる。
        let cacheResult = CVMetalTextureCacheCreate(
            kCFAllocatorDefault,
            nil,
            device,
            nil,
            &textureCache
        )
        if cacheResult != kCVReturnSuccess {
            fatalError("Failed to create CVMetalTextureCache: \(cacheResult)")
        }
        
        setupSession()
        checkPermissions()
    }
    
    // MARK: - Public Methods
    func startSession() {
        guard hasPermission else { return }
        // セッション制御はキャプチャ用キューで（UIスレッドを塞がない）
        captureQueue.async { [weak self] in
            self?.captureSession.startRunning()
            DispatchQueue.main.async {
                self?.isRunning = true
            }
        }
    }
    
    func stopSession() {
        captureQueue.async { [weak self] in
            self?.captureSession.stopRunning()
            DispatchQueue.main.async {
                self?.isRunning = false
            }
        }
    }
    
    func requestPermission() async -> Bool {
        await withCheckedContinuation { continuation in
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    self?.hasPermission = granted
                    continuation.resume(returning: granted)
                }
            }
        }
    }
    
    // MARK: - Private Methods
    private func checkPermissions() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            hasPermission = true
        case .notDetermined:
            Task {
                await requestPermission()
            }
        default:
            hasPermission = false
        }
    }
    
    private func setupSession() {
        captureSession.sessionPreset = .high
        
        // カメラ入力の用意
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device) else {
            print("Failed to create video input")
            return
        }
        
        videoDevice = device
        videoInput = input
        
        if captureSession.canAddInput(input) {
            captureSession.addInput(input)
        }
        
        // カメラ出力の用意（BGRAで受け取る）
        // デリゲートは captureQueue（I/Oトレッド）で呼ばれる。
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // 接続設定
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
        
        // 目標FPS設定（可能な範囲で30fpsへ）
        configureFPS()
    }
    
    private func configureFPS() {
        guard let device = videoDevice else { return }
        do {
            try device.lockForConfiguration()
            let targetFPS = 30.0
            for format in device.formats {
                for range in format.videoSupportedFrameRateRanges {
                    if range.minFrameRate <= targetFPS && range.maxFrameRate >= targetFPS {
                        device.activeFormat = format
                        device.activeVideoMinFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                        device.activeVideoMaxFrameDuration = CMTime(value: 1, timescale: Int32(targetFPS))
                        break
                    }
                }
            }
            device.unlockForConfiguration()
        } catch {
            print("Failed to configure frame rate: \(error)")
        }
    }
    
    // sampleBuffer（CVPixelBuffer）→ MTLTexture への変換
    // ここが「CPUでGPUが読める形に整える」ポイント。
    private func createTexture(from sampleBuffer: CMSampleBuffer) -> MTLTexture? {
        guard let textureCache = textureCache,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            handleTextureFailure("Failed to get pixel buffer or texture cache")
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        guard width > 0 && height > 0 else {
            handleTextureFailure("Invalid texture dimensions: \(width)x\(height)")
            return nil
        }
        
        // CVMetalTextureCacheCreateTextureFromImage:
        // PixelBuffer を GPU が参照できるテクスチャビュー（CVMetalTexture）にラップする。
        // 多くの構成で IOSurface 共有により実質ゼロコピー。
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,   // MTLTexture のピクセルフォーマット
            width,
            height,
            0,
            &cvTexture
        )
        guard status == kCVReturnSuccess else {
            handleTextureFailure("CVMetalTextureCache creation failed: \(status)")
            return nil
        }
        
        // CVMetalTextureGetTexture:
        // CoreVideoラッパ（CVMetalTexture）から Metalの MTLTexture を取得。
        // 取得後は cvTexture 自体を保持し続ける必要は通常ない（同じ基盤メモリを参照）。
        guard let cvTexture = cvTexture,
              let metalTexture = CVMetalTextureGetTexture(cvTexture) else {
            handleTextureFailure("Failed to get Metal texture from CVMetalTexture")
            return nil
        }
        
        // 成功したので失敗カウンタをリセットし、UIのエラー表示をクリア。
        consecutiveTextureFailures = 0
        DispatchQueue.main.async { [weak self] in
            self?.errorMessage = nil
        }
        return metalTexture // ← ここで返すのが MTLTexture（GPUが使う画像データ）
    }
    
    private func handleTextureFailure(_ message: String) {
        consecutiveTextureFailures += 1
        print("Texture creation failure #\(consecutiveTextureFailures): \(message)")
        if consecutiveTextureFailures >= maxConsecutiveFailures {
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Metal texture processing failed. Restart required."
                self?.stopSession()
            }
        }
    }
    
    private func updateFPS() {
        frameCount += 1
        let currentTime = CACurrentMediaTime()
        let elapsed = currentTime - lastTimestamp
        if elapsed >= fpsUpdateInterval {
            let calculatedFPS = Int(Double(frameCount) / elapsed)
            DispatchQueue.main.async { [weak self] in
                self?.fps = calculatedFPS
            }
            frameCount = 0
            lastTimestamp = currentTime
        }
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        // FPS更新（計測系は軽いのでここで）
        updateFPS()
        
        // 画像→テクスチャ変換は別キューで。I/OとUIを塞がないようにする。
        textureQueue.async { [weak self] in
            guard let self = self else { return }
            // sampleBuffer（CVPixelBuffer）を MTLTexture に変換
            let texture = self.createTexture(from: sampleBuffer)
            
            // UI更新やデリゲート通知はメインスレッドで。
            DispatchQueue.main.async {
                // previewTexture は「GPUが使う元画像」をUIプレビューにも流用。
                self.previewTexture = texture
                self.delegate?.cameraManager(self, didOutput: sampleBuffer)
                self.delegate?.cameraManager(self, didUpdatePreview: texture)
            }
        }
    }
}
