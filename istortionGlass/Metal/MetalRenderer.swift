//
//  MetalRenderer.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import Metal
import MetalKit
import simd

class MetalRenderer: NSObject {
    
    // MARK: - Properties
    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue
    private var pipelineState: MTLRenderPipelineState?
    private var vertexBuffer: MTLBuffer?
    
    // Uniform buffer for distortion parameters
    private var uniformBuffer: MTLBuffer?
    
    // Texture to render
    var inputTexture: MTLTexture?
    
    // Current effect type
    var currentEffect: DistortionEffect = .none
    
    enum DistortionEffect {
        case none
        case fisheye
        case ripple
        case swirl
    }
    
    // Uniform data structure
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
        guard let commandQueue = device.makeCommandQueue() else {
            fatalError("Failed to create command queue")
        }
        self.commandQueue = commandQueue
        
        super.init()
        
        setupMetal()
        setupVertexBuffer()
        setupUniformBuffer()
    }
    
    // MARK: - Public Methods
    func render(to drawable: CAMetalDrawable, with texture: MTLTexture) {
        guard let pipelineState = pipelineState,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: createRenderPassDescriptor(for: drawable)) else {
            return
        }
        
        renderEncoder.setRenderPipelineState(pipelineState)
        
        // Set vertex buffer
        if let vertexBuffer = vertexBuffer {
            renderEncoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        }
        
        // Update and set uniforms
        updateUniforms(resolution: simd_float2(Float(drawable.texture.width), Float(drawable.texture.height)))
        if let uniformBuffer = uniformBuffer {
            renderEncoder.setFragmentBuffer(uniformBuffer, offset: 0, index: 0)
        }
        
        // Set texture
        renderEncoder.setFragmentTexture(texture, index: 0)
        
        // Draw
        renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        renderEncoder.endEncoding()
        
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }
    
    func setEffect(_ effect: DistortionEffect, strength: Float = 1.0) {
        currentEffect = effect
        updateUniforms(strength: strength)
    }
    
    // MARK: - Private Methods
    private func setupMetal() {
        guard let library = device.makeDefaultLibrary() else {
            fatalError("Failed to create Metal library")
        }
        
        let vertexFunction = library.makeFunction(name: "vertex_main")
        let fragmentFunction = library.makeFunction(name: "fragment_main")
        
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction
        pipelineDescriptor.colorAttachments[0].pixelFormat = .bgra8Unorm
        
        do {
            pipelineState = try device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            fatalError("Failed to create pipeline state: \(error)")
        }
    }
    
    private func setupVertexBuffer() {
        // Full-screen quad vertices (position and texture coordinates)
        let vertices: [Float] = [
            -1.0, -1.0, 0.0, 1.0,  // Bottom-left
             1.0, -1.0, 1.0, 1.0,  // Bottom-right
            -1.0,  1.0, 0.0, 0.0,  // Top-left
             1.0,  1.0, 1.0, 0.0   // Top-right
        ]
        
        vertexBuffer = device.makeBuffer(bytes: vertices, length: vertices.count * MemoryLayout<Float>.size, options: [])
    }
    
    private func setupUniformBuffer() {
        uniformBuffer = device.makeBuffer(length: MemoryLayout<Uniforms>.size, options: [])
    }
    
    private func updateUniforms(resolution: simd_float2? = nil, strength: Float? = nil) {
        guard let uniformBuffer = uniformBuffer,
              let contents = uniformBuffer.contents().bindMemory(to: Uniforms.self, capacity: 1) else {
            return
        }
        
        let currentTime = Float(CACurrentMediaTime())
        
        var uniforms = contents.pointee
        uniforms.time = currentTime
        
        if let resolution = resolution {
            uniforms.resolution = resolution
        }
        
        if let strength = strength {
            uniforms.strength = strength
        }
        
        uniforms.effectType = Int32(currentEffect.rawValue)
        uniforms.center = simd_float2(0.5, 0.5) // Center of the screen
        
        contents.pointee = uniforms
    }
    
    private func createRenderPassDescriptor(for drawable: CAMetalDrawable) -> MTLRenderPassDescriptor {
        let descriptor = MTLRenderPassDescriptor()
        descriptor.colorAttachments[0].texture = drawable.texture
        descriptor.colorAttachments[0].loadAction = .clear
        descriptor.colorAttachments[0].clearColor = MTLClearColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 1.0)
        descriptor.colorAttachments[0].storeAction = .store
        return descriptor
    }
}

// MARK: - DistortionEffect Extension
extension MetalRenderer.DistortionEffect {
    var rawValue: Int {
        switch self {
        case .none: return 0
        case .fisheye: return 1
        case .ripple: return 2
        case .swirl: return 3
        }
    }
}