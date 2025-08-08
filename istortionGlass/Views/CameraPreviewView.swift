//
//  CameraPreviewView.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import SwiftUI
import MetalKit
import CoreMedia

struct CameraPreviewView: UIViewRepresentable {
    @ObservedObject var cameraManager: CameraManager
    @State private var metalView: MTKView?
    @State private var renderer: MetalRenderer?
    
    var currentEffect: MetalRenderer.DistortionEffect = .none
    var effectStrength: Float = 1.0
    var isPassthroughMode: Bool = false
    var performanceMonitor: PerformanceMonitor?
    
    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fatalError("Metal is not supported on this device")
        }
        
        let mtkView = MTKView()
        mtkView.device = device
        mtkView.delegate = context.coordinator
        mtkView.framebufferOnly = false
        mtkView.colorPixelFormat = .bgra8Unorm
        mtkView.preferredFramesPerSecond = 30
        mtkView.enableSetNeedsDisplay = false
        mtkView.isPaused = false
        
        // Create renderer
        let metalRenderer = MetalRenderer(device: device)
        
        // Set performance monitor
        metalRenderer.performanceMonitor = performanceMonitor
        
        // Set up camera manager delegate
        cameraManager.delegate = context.coordinator
        
        // Store references
        DispatchQueue.main.async {
            self.metalView = mtkView
            self.renderer = metalRenderer
        }
        
        context.coordinator.metalView = mtkView
        context.coordinator.renderer = metalRenderer
        context.coordinator.parent = self
        
        return mtkView
    }
    
    func updateUIView(_ uiView: MTKView, context: Context) {
        context.coordinator.parent = self
        
        // Update effect settings with real-time parameter updates
        renderer?.setEffect(currentEffect, strength: effectStrength)
        renderer?.setPassthroughMode(isPassthroughMode)
        
        // Immediate strength update for smooth real-time adjustment
        renderer?.updateEffectStrength(effectStrength)
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator()
    }
    
    class Coordinator: NSObject, MTKViewDelegate, CameraManagerDelegate {
        var metalView: MTKView?
        var renderer: MetalRenderer?
        var parent: CameraPreviewView?
        private var currentTexture: MTLTexture?
        
        // MARK: - MTKViewDelegate
        func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
            // Handle size changes if needed
        }
        
        func draw(in view: MTKView) {
            guard let drawable = view.currentDrawable,
                  let renderer = renderer,
                  let texture = currentTexture else {
                return
            }
            
            renderer.render(to: drawable, with: texture)
        }
        
        // MARK: - CameraManagerDelegate
        func cameraManager(_ manager: CameraManager, didOutput sampleBuffer: CMSampleBuffer) {
            // Handle sample buffer if needed for additional processing
        }
        
        func cameraManager(_ manager: CameraManager, didUpdatePreview texture: MTLTexture?) {
            currentTexture = texture
            
            // Trigger redraw
            DispatchQueue.main.async { [weak self] in
                self?.metalView?.setNeedsDisplay()
            }
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
