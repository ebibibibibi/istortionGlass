//
//  PerformanceMonitor.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import Foundation
import Metal
import os.log
import QuartzCore
import Combine

class PerformanceMonitor: ObservableObject {
    
    // MARK: - Published Properties
    @Published var averageFPS: Double = 0.0
    @Published var currentMemoryUsage: UInt64 = 0
    @Published var peakMemoryUsage: UInt64 = 0
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    @Published var gpuUtilization: Double = 0.0
    @Published var averageRenderTime: Double = 0.0
    @Published var frameDropCount: Int = 0
    
    // MARK: - Private Properties
    private var frameRenderTimes: [CFTimeInterval] = []
    private let maxFrameHistory = 60 // Track last 60 frames
    private var memoryMonitorTimer: Timer?
    private let logger = Logger(subsystem: "com.istortionGlass", category: "Performance")
    private var lastFrameTime: CFTimeInterval = 0
    private let targetFrameTime: CFTimeInterval = 1.0 / 30.0 // 30 FPS target
    
    // MARK: - Initialization
    init() {
        startMemoryMonitoring()
        startThermalMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    func recordFrameRenderTime(_ renderTime: CFTimeInterval) {
        frameRenderTimes.append(renderTime)
        
        // Keep only the most recent frames
        if frameRenderTimes.count > maxFrameHistory {
            frameRenderTimes.removeFirst()
        }
        
        // Check for frame drops
        let currentTime = CACurrentMediaTime()
        if lastFrameTime > 0 {
            let frameInterval = currentTime - lastFrameTime
            if frameInterval > targetFrameTime * 1.5 { // 50% tolerance
                DispatchQueue.main.async { [weak self] in
                    self?.frameDropCount += 1
                }
            }
        }
        lastFrameTime = currentTime
        
        updateAverageFPS()
        updateRenderMetrics()
    }
    
    private func updateRenderMetrics() {
        guard !frameRenderTimes.isEmpty else { return }
        
        let averageTime = frameRenderTimes.reduce(0, +) / Double(frameRenderTimes.count)
        let gpuUtil = min(averageTime / targetFrameTime, 1.0) * 100.0
        
        DispatchQueue.main.async { [weak self] in
            self?.averageRenderTime = averageTime * 1000.0 // Convert to milliseconds
            self?.gpuUtilization = gpuUtil
        }
    }
    
    func startMonitoring() {
        startMemoryMonitoring()
        startThermalMonitoring()
    }
    
    func stopMonitoring() {
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
    }
    
    func logPerformanceWarning(_ message: String) {
        logger.warning("\(message)")
    }
    
    func logPerformanceInfo(_ message: String) {
        logger.info("\(message)")
    }
    
    // MARK: - Private Methods
    private func updateAverageFPS() {
        guard !frameRenderTimes.isEmpty else {
            averageFPS = 0.0
            return
        }
        
        let totalTime = frameRenderTimes.reduce(0, +)
        let averageRenderTime = totalTime / Double(frameRenderTimes.count)
        
        DispatchQueue.main.async { [weak self] in
            self?.averageFPS = averageRenderTime > 0 ? 1.0 / averageRenderTime : 0.0
        }
    }
    
    private func startMemoryMonitoring() {
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMemoryUsage()
        }
    }
    
    private func updateMemoryUsage() {
        var memoryInfo = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4
        
        let result = withUnsafeMutablePointer(to: &memoryInfo) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_, task_flavor_t(MACH_TASK_BASIC_INFO), $0, &count)
            }
        }
        
        if result == KERN_SUCCESS {
            let usage = memoryInfo.resident_size
            
            DispatchQueue.main.async { [weak self] in
                guard let self = self else { return }
                self.currentMemoryUsage = usage
                
                if usage > self.peakMemoryUsage {
                    self.peakMemoryUsage = usage
                }
                
                // Log warning if memory usage is high (> 200MB)
                if usage > 200 * 1024 * 1024 {
                    self.logPerformanceWarning("High memory usage: \(usage / 1024 / 1024)MB")
                }
            }
        }
    }
    
    private func startThermalMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        
        // Initial thermal state
        DispatchQueue.main.async { [weak self] in
            self?.thermalState = ProcessInfo.processInfo.thermalState
        }
    }
    
    @objc private func thermalStateChanged() {
        DispatchQueue.main.async { [weak self] in
            let newState = ProcessInfo.processInfo.thermalState
            self?.thermalState = newState
            
            switch newState {
            case .serious, .critical:
                self?.logPerformanceWarning("Thermal throttling detected: \(newState)")
            default:
                break
            }
        }
    }
}

// MARK: - Memory Info Structure
private struct mach_task_basic_info {
    var virtual_size: mach_vm_size_t = 0
    var resident_size: mach_vm_size_t = 0
    var resident_size_max: mach_vm_size_t = 0
    var user_time: time_value_t = time_value_t()
    var system_time: time_value_t = time_value_t()
    var policy: policy_t = 0
    var suspend_count: integer_t = 0
}

// MARK: - Extensions for Formatted Output
extension PerformanceMonitor {
    var formattedMemoryUsage: String {
        let mb = Double(currentMemoryUsage) / 1024.0 / 1024.0
        return String(format: "%.1f MB", mb)
    }
    
    var formattedPeakMemoryUsage: String {
        let mb = Double(peakMemoryUsage) / 1024.0 / 1024.0
        return String(format: "%.1f MB", mb)
    }
    
    var formattedFPS: String {
        return String(format: "%.1f FPS", averageFPS)
    }
    
    var thermalStateDescription: String {
        switch thermalState {
        case .nominal:
            return "Normal"
        case .fair:
            return "Fair"
        case .serious:
            return "Hot"
        case .critical:
            return "Critical"
        @unknown default:
            return "Unknown"
        }
    }
}
