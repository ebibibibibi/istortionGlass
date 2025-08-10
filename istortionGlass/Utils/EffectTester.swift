//
//  EffectTester.swift
//  istortionGlass
//
//  Created by KotomiTakahashi on 2025/08/08.
//

import Foundation
import SwiftUI
import Combine

/// レンダリング効果（DistortionEffect）の「自動ベンチマーク実行器」
/// - 何をする？
///   複数のエフェクト × 強度を順番に適用し、一定時間のメトリクス（FPS/負荷/メモリ/サーマルなど）を収集する。
/// - どうやって切り替える？
///   外部から渡される `onEffectChange(effect, strength, enabled)` コールバックで
///   実際のレンダラ（MetalRenderer）側の状態を変更してもらう。
class EffectTester: ObservableObject {
    
    // MARK: - Published Properties（UI表示用）
    /// テスト進行中フラグ（UIの開始/停止ボタン制御など）
    @Published var isRunningTest = false
    /// 各条件（effect×strength）での測定結果一覧（UIで表やグラフに使う想定）
    @Published var testResults: [TestResult] = []
    /// 進行中フェーズの表示用（例: "Fisheye HQ @ 75%"）
    @Published var currentTestPhase = ""
    
    // MARK: - Test Configuration（テスト条件）
    /// 1条件あたりの測定時間（秒）。短すぎると平均値がブレやすい・長すぎると時間がかかる
    private let testDuration: TimeInterval = 10.0
    /// 強度スイープの離散値（0%〜100%）
    private let strengthLevels: [Float] = [0.0, 0.25, 0.5, 0.75, 1.0]
    /// 測定用タイマー（RunLoop駆動：UIスレッドで作ると確実）
    private var testTimer: Timer?
    /// いま何番目の条件を測定中か（effect×strength を線形に走査）
    private var currentTestIndex = 0
    
    /// 単一条件の測定結果（UI/ログに出す集約値）
    struct TestResult {
        let effect: MetalRenderer.DistortionEffect  // どのエフェクトか
        let strength: Float                         // 強度（0.0〜1.0）
        let averageFPS: Double                      // 平均FPS（PerformanceMonitor由来）
        let gpuLoad: Double                         // 近似GPU負荷[%]（平均レンダ時間/目標フレーム時間）
        let frameTime: Double                       // 平均フレーム時間[ms]
        let frameDrops: Int                         // 目標時間+α を超えた回数（ドロップ推定）
        let memoryUsage: UInt64                     // 常駐メモリ（bytes）
        let thermalState: ProcessInfo.ThermalState  // サーマル状態
    }
    
    // MARK: - Public Methods
    /// 自動テスト開始
    /// - Parameters:
    ///   - performanceMonitor: 計測元。描画ループ/コマンドバッファ完了から数値が流れてくる想定
    ///   - onEffectChange: 実際のレンダラへの変更フック（ここでeffect/strengthを適用する）
    func startAutomaticTest(
        performanceMonitor: PerformanceMonitor,
        onEffectChange: @escaping (MetalRenderer.DistortionEffect, Float, Bool) -> Void
    ) {
        guard !isRunningTest else { return }
        
        isRunningTest = true
        testResults.removeAll()
        currentTestIndex = 0
        
        // 対象エフェクトの集合（必要に応じて追加）
        let effects: [MetalRenderer.DistortionEffect] = [.none, .fisheyeHQ, .fisheyeFast]
        
        runNextTest(
            effects: effects,
            performanceMonitor: performanceMonitor,
            onEffectChange: onEffectChange
        )
    }
    
    /// テスト停止（現在条件の計測を中断）
    func stopTest() {
        testTimer?.invalidate()
        testTimer = nil
        isRunningTest = false
        currentTestPhase = ""
    }
    
    // MARK: - Private Methods
    /// 次の条件（effect×strength）へ進め、適用→安定化→測定の流れを回す
    private func runNextTest(
        effects: [MetalRenderer.DistortionEffect],
        performanceMonitor: PerformanceMonitor,
        onEffectChange: @escaping (MetalRenderer.DistortionEffect, Float, Bool) -> Void
    ) {
        let totalTests = effects.count * strengthLevels.count
        guard currentTestIndex < totalTests else {
            // すべての条件が完了
            completeTest()
            return
        }
        
        // 現在の effect/strength を決定
        let effectIndex = currentTestIndex / strengthLevels.count
        let strengthIndex = currentTestIndex % strengthLevels.count
        let effect = effects[effectIndex]
        let strength = strengthLevels[strengthIndex]
        
        currentTestPhase = "Testing \(effect.displayName) @ \(Int(strength * 100))%"
        
        // 実機レンダラに適用（.none の場合は enabled=false に）
        onEffectChange(effect, strength, effect != .none)
        
        // 直近のドロップカウントだけは手動でリセット
        // （Monitor側の移動平均バッファはそのまま＝安定化待ちで自然に馴染ませる想定）
        performanceMonitor.frameDropCount = 0
        
        // ✨ 安定化待ち（切り替え直後のスパイクを避ける）
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
    
    /// 実測フェーズ：`testDuration` 秒待って、PerformanceMonitorの“現在の平均値”をスナップショット
    private func measurePerformance(
        effect: MetalRenderer.DistortionEffect,
        strength: Float,
        performanceMonitor: PerformanceMonitor,
        completion: @escaping () -> Void
    ) {
        // Timer発火で「その時点の移動平均」を採取（※期間中にMonitorは継続更新される前提）
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
    
    /// テスト完了：フラグ更新・ログ出力・フェーズ表示の自動クリア
    private func completeTest() {
        isRunningTest = false
        currentTestPhase = "Test Complete"
        
        // 簡易ログ（Consoleで全体を確認）
        print("=== Effect Performance Test Results ===")
        for result in testResults {
            print("\(result.effect.displayName) @ \(Int(result.strength * 100))%:")
            print("  FPS: \(String(format: "%.1f", result.averageFPS))")
            print("  GPU: \(String(format: "%.1f", result.gpuLoad))%")
            print("  Frame Time: \(String(format: "%.1f", result.frameTime))ms")
            print("  Drops: \(result.frameDrops)")
            print("  Memory: \(result.memoryUsage / 1024 / 1024)MB")
            print("  Thermal: \(result.thermalState)")
            print()
        }
        
        // 表示を少し残してから消す（UIチラつき防止）
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) { [weak self] in
            self?.currentTestPhase = ""
        }
    }
    
    // MARK: - Test Analysis（簡易ランキング）
    /// “高FPSかつ低GPU負荷”を優先する単純スコアでベストを選出
    var bestPerformingEffect: TestResult? {
        return testResults.max { a, b in
            let scoreA = a.averageFPS - (a.gpuLoad * 0.1)
            let scoreB = b.averageFPS - (b.gpuLoad * 0.1)
            return scoreA < scoreB
        }
    }
    
    /// ワースト（スコアが最小）
    var worstPerformingEffect: TestResult? {
        return testResults.min { a, b in
            let scoreA = a.averageFPS - (a.gpuLoad * 0.1)
            let scoreB = b.averageFPS - (b.gpuLoad * 0.1)
            return scoreA < scoreB
        }
    }
}
