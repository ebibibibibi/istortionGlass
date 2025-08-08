//
//  CameraManager.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import AVFoundation
import Metal
import MetalKit
import SwiftUI

protocol CameraManagerDelegate: AnyObject {
    func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer)
    func cameraManager(_ manager: CameraManager, didUpdatePreview texture: MTLTexture?)
}

class CameraManager: NSObject, ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRunning = false
    @Published var hasPermission = false
    @Published var previewTexture: MTLTexture?
    
    // MARK: - Private Properties
    private let captureSession = AVCaptureSession()
    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private let videoOutput = AVCaptureVideoDataOutput()
    private let captureQueue = DispatchQueue(label: "camera.capture.queue", qos: .userInteractive)
    
    // Metal properties
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var textureCache: CVMetalTextureCache?
    
    weak var delegate: CameraManagerDelegate?
    
    // MARK: - Initialization
    override init() {
        guard let device = MTLCreateSystemDefaultDevice(),
              let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal device or command queue")
        }
        
        self.device = device
        self.commandQueue = commandQueue
        
        super.init()
        
        // Create texture cache
        CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &textureCache)
        
        setupSession()
        checkPermissions()
    }
    
    // MARK: - Public Methods
    func startSession() {
        guard hasPermission else { return }
        
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
        
        // Setup video input
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
        
        // Setup video output
        videoOutput.setSampleBufferDelegate(self, queue: captureQueue)
        videoOutput.videoSettings = [
            kCVPixelBufferPixelFormatTypeKey as String: kCVPixelFormatType_32BGRA
        ]
        
        if captureSession.canAddOutput(videoOutput) {
            captureSession.addOutput(videoOutput)
        }
        
        // Configure video orientation and connection
        if let connection = videoOutput.connection(with: .video) {
            connection.videoOrientation = .portrait
            if connection.isVideoMirroringSupported {
                connection.isVideoMirrored = false
            }
        }
        
        // Try to set frame rate to 30 FPS
        configureFPS()
    }
    
    private func configureFPS() {
        guard let device = videoDevice else { return }
        
        do {
            try device.lockForConfiguration()
            
            // Find 30 FPS format
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
    
    private func createTexture(from sampleBuffer: CMSampleBuffer) -> MTLTexture? {
        guard let textureCache = textureCache,
              let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return nil
        }
        
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        
        var cvTexture: CVMetalTexture?
        let status = CVMetalTextureCacheCreateTextureFromImage(
            kCFAllocatorDefault,
            textureCache,
            pixelBuffer,
            nil,
            .bgra8Unorm,
            width,
            height,
            0,
            &cvTexture
        )
        
        guard status == kCVReturnSuccess,
              let cvTexture = cvTexture else {
            return nil
        }
        
        return CVMetalTextureGetTexture(cvTexture)
    }
}

// MARK: - AVCaptureVideoDataOutputSampleBufferDelegate
extension CameraManager: AVCaptureVideoDataOutputSampleBufferDelegate {
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        // Create Metal texture from sample buffer
        let texture = createTexture(from: sampleBuffer)
        
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            self.previewTexture = texture
            self.delegate?.cameraManager(self, didOutput: sampleBuffer)
            self.delegate?.cameraManager(self, didUpdatePreview: texture)
        }
    }
}