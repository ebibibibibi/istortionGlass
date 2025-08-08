//
//  EffectTester.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import Foundation
import SwiftUI

class EffectTester: ObservableObject {
    
    // MARK: - Published Properties
    @Published var isRunningTest = false
    @Published var testResults: [TestResult] = []
    @Published var currentTestPhase = ""
    
    // MARK: - Test Configuration
    private let testDuration: TimeInterval = 10.0 // 10 seconds per test
    private let strengthLevels: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
    private var testTimer: Timer?
    private var currentTestIndex = 0
    
    struct TestResult {
        let effect: MetalRenderer.DistortionEffect
        let strength: Float
        let averageFPS: Double
        let gpuLoad: Double
        let frameTime: Double
        let frameDrops: Int
        let memoryUsage: UInt64
        let thermalState: ProcessInfo.ThermalState
    }
    
    // MARK: - Public Methods
    func startAutomaticTest(
        performanceMonitor: PerformanceMonitor,
        onEffectChange: @escaping (MetalRenderer.DistortionEffect, Float, Bool) -> Void
    ) {
        guard !isRunningTest else { return }
        
        isRunningTest = true
        testResults.removeAll()
        currentTestIndex = 0
        
        let effects: [MetalRenderer.DistortionEffect] = [.none, .fisheyeHQ, .fisheyeFast]
        
        runNextTest(
            effects: effects,
            performanceMonitor: performanceMonitor,
            onEffectChange: onEffectChange
        )
    }
    
    func stopTest() {
        testTimer?.invalidate()
        testTimer = nil
        isRunningTest = false
        currentTestPhase = ""
    }
    
    // MARK: - Private Methods
    private func runNextTest(
        effects: [MetalRenderer.DistortionEffect],
        performanceMonitor: PerformanceMonitor,
        onEffectChange: @escaping (MetalRenderer.DistortionEffect, Float, Bool) -> Void
    ) {
        
        let totalTests = effects.count * strengthLevels.count
        
        guard currentTestIndex < totalTests else {
            // All tests complete
            completeTest()
            return
        }
        
        let effectIndex = currentTestIndex / strengthLevels.count
        let strengthIndex = currentTestIndex % strengthLevels.count
        
        let effect = effects[effectIndex]
        let strength = strengthLevels[strengthIndex]
        
        currentTestPhase = "Testing \(effect.displayName) @ \(Int(strength * 100))%"
        
        // Apply effect
        onEffectChange(effect, strength, effect != .none)
        
        // Reset performance counters
        performanceMonitor.frameDropCount = 0
        
        // Wait for stabilization then measure
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) { [weak self] in
            self?.measurePerformance(
                effect: effect,
                strength: strength,
                performanceMonitor: performanceMonitor,
                completion: {
                    self?.currentTestIndex += 1
                    self?.runNextTest(
                        effects: effects,
                        performanceMonitor: performanceMonitor,
                        onEffectChange: onEffectChange
                    )
                }
            )
        }
    }
    
    private func measurePerformance(
        effect: MetalRenderer.DistortionEffect,
        strength: Float,
        performanceMonitor: PerformanceMonitor,
        completion: @escaping () -> Void
    ) {
        
        // Measure for test duration
        testTimer = Timer.scheduledTimer(withTimeInterval: testDuration, repeats: false) { [weak self] _ in
            
            let result = TestResult(
                effect: effect,
                strength: strength,
                averageFPS: performanceMonitor.averageFPS,
                gpuLoad: performanceMonitor.gpuUtilization,
                frameTime: performanceMonitor.averageRenderTime,
                frameDrops: performanceMonitor.frameDropCount,
                memoryUsage: performanceMonitor.currentMemoryUsage,
                thermalState: performanceMonitor.thermalState
            )
            
            DispatchQueue.main.async {
                self?.testResults.append(result)
            }
            
            completion()
        }
    }
    
    private func completeTest() {
        isRunningTest = false
        currentTestPhase = "Test Complete"
        
        // Log results
        print("=== Effect Performance Test Results ===")
        for result in testResults {
            print("\(result.effect.displayName) @ \(Int(result.strength * 100))%:")
            print("  FPS: \(result.averageFPS, specifier: "%.1f")")
            print("  GPU: \(result.gpuLoad, specifier: "%.1f")%")
            print("  Frame Time: \(result.frameTime, specifier: "%.1f")ms")
            print("  Drops: \(result.frameDrops)")
            print("  Memory: \(result.memoryUsage / 1024 / 1024)MB")
            print("  Thermal: \(result.thermalState)")
            print()
        }
        
        // Auto-clear test phase after delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.currentTestPhase = ""
        }
    }
    
    // MARK: - Test Analysis
    var bestPerformingEffect: TestResult? {
        return testResults.max { a, b in
            // Prioritize higher FPS with lower GPU load
            let scoreA = a.averageFPS - (a.gpuLoad * 0.1)
            let scoreB = b.averageFPS - (b.gpuLoad * 0.1)
            return scoreA < scoreB
        }
    }
    
    var worstPerformingEffect: TestResult? {
        return testResults.min { a, b in
            let scoreA = a.averageFPS - (a.gpuLoad * 0.1)
            let scoreB = b.averageFPS - (b.gpuLoad * 0.1)
            return scoreA < scoreB
        }
    }
}