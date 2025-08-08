//
//  ContentView.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var cameraManager = CameraManager()
    @State private var currentEffect: MetalRenderer.DistortionEffect = .none
    @State private var effectStrength: Float = 1.0
    @State private var showingPermissionAlert = false
    
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
                        currentEffect: currentEffect,
                        effectStrength: effectStrength
                    )
                    .onAppear {
                        cameraManager.startSession()
                    }
                    .onDisappear {
                        cameraManager.stopSession()
                    }
                    
                    // Controls overlay
                    VStack {
                        Spacer()
                        
                        // Effect controls
                        VStack(spacing: 20) {
                            // Effect selection buttons
                            HStack(spacing: 15) {
                                EffectButton(
                                    title: "Original",
                                    isSelected: currentEffect == .none
                                ) {
                                    currentEffect = .none
                                }
                                
                                EffectButton(
                                    title: "Fisheye",
                                    isSelected: currentEffect == .fisheye
                                ) {
                                    currentEffect = .fisheye
                                }
                                
                                EffectButton(
                                    title: "Ripple",
                                    isSelected: currentEffect == .ripple
                                ) {
                                    currentEffect = .ripple
                                }
                                
                                EffectButton(
                                    title: "Swirl",
                                    isSelected: currentEffect == .swirl
                                ) {
                                    currentEffect = .swirl
                                }
                            }
                            
                            // Strength slider
                            if currentEffect != .none {
                                VStack {
                                    Text("Strength: \(effectStrength, specifier: "%.1f")")
                                        .foregroundColor(.white)
                                        .font(.caption)
                                    
                                    Slider(value: $effectStrength, in: 0.0...2.0, step: 0.1)
                                        .accentColor(.white)
                                }
                                .padding(.horizontal)
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
}

// Custom effect button component
struct EffectButton: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(isSelected ? .black : .white)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(
                    isSelected ? Color.white : Color.clear
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.white, lineWidth: 1)
                )
                .cornerRadius(8)
        }
    }
}

#Preview {
    ContentView()
}
