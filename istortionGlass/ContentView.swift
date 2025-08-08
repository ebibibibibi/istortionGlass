//
//  ContentView.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @StateObject private var performanceMonitor = PerformanceMonitor()
    @StateObject private var effectTester = EffectTester()
    @State private var currentEffect: MetalRenderer.DistortionEffect = .none
    @State private var effectStrength: Float = 0.5 // Default to 50% strength
    @State private var isEffectEnabled = false // ON/OFF toggle
    @State private var showingPermissionAlert = false
    @State private var isPassthroughMode = false
    @State private var showDebugInfo = false
    @State private var usePerformanceMode = false // Toggle between HQ and Fast fisheye
    
    var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Background
                Color.black
                    .ignoresSafeArea()
                
                if cameraManager.hasPermission {
                    // Camera preview
                    CameraPreviewView(
                        cameraManager: cameraManager,
                        currentEffect: effectiveCurrentEffect,
                        effectStrength: effectiveStrength,
                        isPassthroughMode: isPassthroughMode,
                        performanceMonitor: performanceMonitor
                    )
                    .onAppear {
                        cameraManager.startSession()
                    }
                    .onDisappear {
                        cameraManager.stopSession()
                    }
                    
                    // Debug info overlay
                    if showDebugInfo {
                        VStack {
                            HStack {
                                VStack(alignment: .leading, spacing: 4) {
                                    Text("Camera FPS: \(cameraManager.fps)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.green)
                                    
                                    Text("Render FPS: \(performanceMonitor.formattedFPS)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.green)
                                    
                                    Text("GPU Load: \(Int(performanceMonitor.gpuUtilization))%")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(gpuLoadColor)
                                    
                                    Text("Frame Time: \(performanceMonitor.averageRenderTime, specifier: "%.1f")ms")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.cyan)
                                    
                                    Text("Drops: \(performanceMonitor.frameDropCount)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(performanceMonitor.frameDropCount > 0 ? .red : .green)
                                    
                                    Text("Memory: \(performanceMonitor.formattedMemoryUsage)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.cyan)
                                    
                                    Text("Thermal: \(performanceMonitor.thermalStateDescription)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(thermalStateColor)
                                    
                                    Text("Effect: \(effectiveCurrentEffect.displayName)")
                                        .font(.system(.caption, design: .monospaced))
                                        .foregroundColor(.yellow)
                                    
                                    if isEffectEnabled {
                                        Text("Strength: \(Int(effectStrength * 100))%")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.white)
                                    }
                                    
                                    if !effectTester.currentTestPhase.isEmpty {
                                        Text("Test: \(effectTester.currentTestPhase)")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.orange)
                                    }
                                    
                                    if let error = cameraManager.errorMessage {
                                        Text("Error: \(error)")
                                            .font(.system(.caption, design: .monospaced))
                                            .foregroundColor(.red)
                                            .lineLimit(2)
                                    }
                                }
                                Spacer()
                            }
                            Spacer()
                        }
                        .padding()
                        .background(
                            Color.black.opacity(0.7)
                                .blur(radius: 5)
                        )
                        .cornerRadius(8)
                        .padding()
                    }
                    
                    // Controls overlay
                    VStack {
                        Spacer()
                        
                        // Effect controls
                        VStack(spacing: 20) {
                            // Debug and control buttons
                            HStack(spacing: 12) {
                                Button(action: {
                                    showDebugInfo.toggle()
                                }) {
                                    Image(systemName: showDebugInfo ? "info.circle.fill" : "info.circle")
                                        .foregroundColor(.white)
                                        .font(.title3)
                                }
                                
                                Button(action: {
                                    isPassthroughMode.toggle()
                                }) {
                                    Text(isPassthroughMode ? "GPU" : "RAW")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(isPassthroughMode ? .black : .white)
                                        .padding(.horizontal, 8)
                                        .padding(.vertical, 4)
                                        .background(isPassthroughMode ? Color.green : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 6)
                                                .stroke(Color.white, lineWidth: 1)
                                        )
                                        .cornerRadius(6)
                                }
                                
                                // Performance mode toggle for fisheye
                                if currentEffect != .none {
                                    Button(action: {
                                        usePerformanceMode.toggle()
                                    }) {
                                        Text(usePerformanceMode ? "FAST" : "HQ")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(usePerformanceMode ? .black : .white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(usePerformanceMode ? Color.orange : Color.clear)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.white, lineWidth: 1)
                                            )
                                            .cornerRadius(6)
                                    }
                                }
                                
                                Spacer()
                                
                                // Performance test button
                                if showDebugInfo {
                                    Button(action: {
                                        if effectTester.isRunningTest {
                                            effectTester.stopTest()
                                        } else {
                                            effectTester.startAutomaticTest(
                                                performanceMonitor: performanceMonitor
                                            ) { effect, strength, enabled in
                                                currentEffect = effect
                                                effectStrength = strength
                                                isEffectEnabled = enabled
                                            }
                                        }
                                    }) {
                                        Text(effectTester.isRunningTest ? "STOP" : "TEST")
                                            .font(.caption)
                                            .fontWeight(.bold)
                                            .foregroundColor(effectTester.isRunningTest ? .black : .white)
                                            .padding(.horizontal, 8)
                                            .padding(.vertical, 4)
                                            .background(effectTester.isRunningTest ? Color.red : Color.clear)
                                            .overlay(
                                                RoundedRectangle(cornerRadius: 6)
                                                    .stroke(Color.white, lineWidth: 1)
                                            )
                                            .cornerRadius(6)
                                    }
                                    .disabled(effectTester.isRunningTest && effectTester.currentTestPhase.isEmpty)
                                }
                                
                                // Effect ON/OFF toggle
                                Button(action: {
                                    isEffectEnabled.toggle()
                                }) {
                                    Text(isEffectEnabled ? "ON" : "OFF")
                                        .font(.caption)
                                        .fontWeight(.bold)
                                        .foregroundColor(isEffectEnabled ? .black : .white)
                                        .padding(.horizontal, 12)
                                        .padding(.vertical, 6)
                                        .background(isEffectEnabled ? Color.white : Color.clear)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 8)
                                                .stroke(Color.white, lineWidth: 2)
                                        )
                                        .cornerRadius(8)
                                }
                                .disabled(effectTester.isRunningTest)
                            }
                            
                            // Effect selection buttons
                            HStack(spacing: 10) {
                                EffectButton(
                                    title: "Original",
                                    isSelected: currentEffect == .none && !isPassthroughMode,
                                    isEnabled: !effectTester.isRunningTest
                                ) {
                                    currentEffect = .none
                                    isPassthroughMode = false
                                    isEffectEnabled = false
                                }
                                
                                EffectButton(
                                    title: "Fisheye",
                                    isSelected: isFisheyeSelected && !isPassthroughMode,
                                    isEnabled: !effectTester.isRunningTest
                                ) {
                                    currentEffect = usePerformanceMode ? .fisheyeFast : .fisheyeHQ
                                    isPassthroughMode = false
                                    isEffectEnabled = true
                                }
                                
                                EffectButton(
                                    title: "Ripple",
                                    isSelected: currentEffect == .ripple && !isPassthroughMode,
                                    isEnabled: !effectTester.isRunningTest
                                ) {
                                    currentEffect = .ripple
                                    isPassthroughMode = false
                                    isEffectEnabled = true
                                }
                                
                                EffectButton(
                                    title: "Swirl",
                                    isSelected: currentEffect == .swirl && !isPassthroughMode,
                                    isEnabled: !effectTester.isRunningTest
                                ) {
                                    currentEffect = .swirl
                                    isPassthroughMode = false
                                    isEffectEnabled = true
                                }
                            }
                            
                            // Strength slider (always visible when effect is enabled)
                            if isEffectEnabled && currentEffect != .none {
                                VStack(spacing: 8) {
                                    HStack {
                                        Text("Effect Strength")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                        Spacer()
                                        Text("\(Int(effectStrength * 100))%")
                                            .foregroundColor(.white)
                                            .font(.caption)
                                            .fontWeight(.bold)
                                    }
                                    
                                    Slider(value: $effectStrength, in: 0.0...1.0, step: 0.05)
                                        .accentColor(.white)
                                        .onChange(of: effectStrength) { _ in
                                            // Real-time parameter update
                                            // This will be handled by effectiveStrength computed property
                                        }
                                }
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(
                                    Color.black.opacity(0.3)
                                        .cornerRadius(8)
                                )
                            }
                        }
                        .padding()
                        .background(
                            Color.black.opacity(0.7)
                                .blur(radius: 10)
                        )
                        .cornerRadius(15)
                        .padding()
                    }
                } else {
                    // Permission not granted view
                    VStack(spacing: 20) {
                        Image(systemName: "camera.fill")
                            .font(.system(size: 60))
                            .foregroundColor(.white)
                        
                        Text("Camera Access Required")
                            .font(.title2)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                        
                        Text("This app needs camera access to show live video with distortion effects.")
                            .font(.body)
                            .foregroundColor(.gray)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                        
                        Button("Grant Camera Access") {
                            Task {
                                await cameraManager.requestPermission()
                            }
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)
                    }
                    .padding()
                }
            }
        }
        .preferredColorScheme(.dark)
        .statusBarHidden()
    }
    
    // MARK: - Helper Properties
    private var effectiveCurrentEffect: MetalRenderer.DistortionEffect {
        guard isEffectEnabled && !isPassthroughMode else {
            return .none
        }
        
        // Auto-switch between HQ and Fast based on performance mode
        if currentEffect == .fisheyeHQ || currentEffect == .fisheyeFast {
            return usePerformanceMode ? .fisheyeFast : .fisheyeHQ
        }
        
        return currentEffect
    }
    
    private var effectiveStrength: Float {
        return isEffectEnabled ? effectStrength : 0.0
    }
    
    private var isFisheyeSelected: Bool {
        return currentEffect == .fisheyeHQ || currentEffect == .fisheyeFast
    }
    
    private var thermalStateColor: Color {
        switch performanceMonitor.thermalState {
        case .nominal:
            return .green
        case .fair:
            return .yellow
        case .serious:
            return .orange
        case .critical:
            return .red
        @unknown default:
            return .gray
        }
    }
    
    private var gpuLoadColor: Color {
        let load = performanceMonitor.gpuUtilization
        if load < 50 {
            return .green
        } else if load < 75 {
            return .yellow
        } else if load < 90 {
            return .orange
        } else {
            return .red
        }
    }
}

// Custom effect button component
struct EffectButton: View {
    let title: String
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void
    
    init(title: String, isSelected: Bool, isEnabled: Bool = true, action: @escaping () -> Void) {
        self.title = title
        self.isSelected = isSelected
        self.isEnabled = isEnabled
        self.action = action
    }
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(buttonTextColor)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(buttonBackgroundColor)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(buttonBorderColor, lineWidth: 1)
                )
                .cornerRadius(8)
        }
        .disabled(!isEnabled)
    }
    
    private var buttonTextColor: Color {
        if !isEnabled {
            return .gray
        }
        return isSelected ? .black : .white
    }
    
    private var buttonBackgroundColor: Color {
        if !isEnabled {
            return Color.gray.opacity(0.3)
        }
        return isSelected ? Color.white : Color.clear
    }
    
    private var buttonBorderColor: Color {
        return isEnabled ? .white : .gray
    }
}

#Preview {
    ContentView()
}
