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

/// パフォーマンス可視化のための軽量モニタ。
/// - どこで使う？
///   レンダラ側（例：MTLCommandBuffer 完了ハンドラや描画ループ）から
///   1フレームあたりの処理時間を `recordFrameRenderTime(_:)` で流し込む。
/// - 何が見える？
///   - averageFPS: 平均FPS（移動平均）
///   - current/peakMemoryUsage: ワーキングセット（resident）の現在値と最大値
///   - thermalState: サーマル状態（発熱によるスロットリング兆候）
///   - gpuUtilization: **近似**のGPU負荷（目標フレーム時間に対する平均レンダ時間の比）
///   - averageRenderTime: 平均レンダ時間（ms）
///   - frameDropCount: 目標フレーム時間を大幅に超えた回数
///
/// ⚠️ 注意:
/// - `gpuUtilization` は“実測のGPUカウンタ”ではなく**近似**（レンダ時間/目標フレーム時間）。
///   正確なGPUカウンタが必要なら、XcodeのGPU CaptureやMetal Counters等のツールを使う。
/// - メモリ監視は1秒ごとの Timer で常駐サイズ（resident）を取得。バックグラウンドでは止まる。
class PerformanceMonitor: ObservableObject {
    
    // MARK: - Published Properties (UIへ出す値)
    /// 移動平均のFPS
    @Published var averageFPS: Double = 0.0
    /// 常駐メモリの現在値（bytes）
    @Published var currentMemoryUsage: UInt64 = 0
    /// 常駐メモリのピーク（bytes）
    @Published var peakMemoryUsage: UInt64 = 0
    /// サーマル状態（nominal/fair/serious/critical）
    @Published var thermalState: ProcessInfo.ThermalState = .nominal
    /// GPU利用率の近似 [%]（averageRenderTime / targetFrameTime）
    @Published var gpuUtilization: Double = 0.0
    /// 平均レンダ時間 [ms]
    @Published var averageRenderTime: Double = 0.0
    /// 明確な“落ちフレーム”と見なした回数
    @Published var frameDropCount: Int = 0
    
    // MARK: - Private Properties (内部状態)
    /// 直近 maxFrameHistory フレームのレンダ時間（秒）
    private var frameRenderTimes: [CFTimeInterval] = []
    /// 履歴長（例: 60フレーム=およそ2秒@30FPS）
    private let maxFrameHistory = 60
    /// 1秒ごとのメモリ監視タイマー（RunLoop駆動）
    private var memoryMonitorTimer: Timer?
    /// OSログ（Console.app で閲覧）
    private let logger = Logger(subsystem: "com.istortionGlass", category: "Performance")
    /// 前フレームの終了タイムスタンプ（フレーム落ち検知用）
    private var lastFrameTime: CFTimeInterval = 0
    /// 目標フレーム時間（30FPSなら ~33.3ms）
    private let targetFrameTime: CFTimeInterval = 1.0 / 30.0
    
    // MARK: - Initialization
    init() {
        startMemoryMonitoring()
        startThermalMonitoring()
    }
    
    deinit {
        stopMonitoring()
    }
    
    // MARK: - Public Methods
    /// 1フレームのレンダ時間（秒）を記録する。
    /// - どこで呼ぶ？: コマンドバッファ完了ハンドラや描画ループの計測区間から。
    func recordFrameRenderTime(_ renderTime: CFTimeInterval) {
        frameRenderTimes.append(renderTime)
        // 履歴を一定長に保つ（移動平均）
        if frameRenderTimes.count > maxFrameHistory {
            frameRenderTimes.removeFirst()
        }
        
        // フレーム落ちの簡易検知：
        // 「前フレーム完了からの経過」が目標時間の 1.5倍を超えたら1カウント
        let currentTime = CACurrentMediaTime()
        if lastFrameTime > 0 {
            let frameInterval = currentTime - lastFrameTime
            if frameInterval > targetFrameTime * 1.5 { // 許容50%超え
                DispatchQueue.main.async { [weak self] in
                    self?.frameDropCount += 1
                }
            }
        }
        lastFrameTime = currentTime
        
        updateAverageFPS()
        updateRenderMetrics()
    }
    
    /// レンダ時間の移動平均から、平均レンダ時間と近似GPU利用率を更新
    private func updateRenderMetrics() {
        guard !frameRenderTimes.isEmpty else { return }
        let averageTime = frameRenderTimes.reduce(0, +) / Double(frameRenderTimes.count)
        // 目標フレーム時間に対する比率で“近似GPU負荷”を算出（100%上限）
        let gpuUtil = min(averageTime / targetFrameTime, 1.0) * 100.0
        
        DispatchQueue.main.async { [weak self] in
            self?.averageRenderTime = averageTime * 1000.0 // 秒→ms
            self?.gpuUtilization = gpuUtil
        }
    }
    
    /// 監視開始（再入OK）
    func startMonitoring() {
        startMemoryMonitoring()
        startThermalMonitoring()
    }
    
    /// 監視停止（Timer解放）
    func stopMonitoring() {
        memoryMonitorTimer?.invalidate()
        memoryMonitorTimer = nil
    }
    
    /// 警告ログ（Consoleで warning レベル）
    func logPerformanceWarning(_ message: String) {
        logger.warning("\(message)")
    }
    
    /// 情報ログ（Consoleで info レベル）
    func logPerformanceInfo(_ message: String) {
        logger.info("\(message)")
    }
    
    // MARK: - Private Methods
    /// FPS 更新（レンダ時間の逆数）
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
    
    /// 1秒ごとにメモリ使用量を取得する（resident size）
    private func startMemoryMonitoring() {
        memoryMonitorTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.updateMemoryUsage()
        }
    }
    
    /// `task_info` による常駐メモリ（resident）取得とピーク更新
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
                // しきい値超過で警告（例: 200MB）
                if usage > 200 * 1024 * 1024 {
                    self.logPerformanceWarning("High memory usage: \(usage / 1024 / 1024)MB")
                }
            }
        }
    }
    
    /// サーマル状態の監視（通知購読 + 初期状態反映）
    private func startThermalMonitoring() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(thermalStateChanged),
            name: ProcessInfo.thermalStateDidChangeNotification,
            object: nil
        )
        // 初期値を反映
        DispatchQueue.main.async { [weak self] in
            self?.thermalState = ProcessInfo.processInfo.thermalState
        }
    }
    
    /// サーマル状態変化時のハンドラ
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
/// `task_info` 用の簡易構造体（resident_size など最低限）
/// ⚠️ 本番では `mach_task_basic_info_data_t` / `MACH_TASK_BASIC_INFO_COUNT`
///    （<mach/task_info.h>）を使うと安全。
private struct mach_task_basic_info {
    var virtual_size: mach_vm_size_t = 0
    var resident_size: mach_vm_size_t = 0
    var resident_size_max: mach_vm_size_t = 0
    var user_time: time_value_t = time_value_t()
    var system_time: time_value_t = time_value_t()
    var policy: policy_t = 0
    var suspend_count: integer_t = 0
}

// MARK: - Extensions for Formatted Output (UI表示用のフォーマッタ)
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
