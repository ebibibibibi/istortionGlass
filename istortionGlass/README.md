# istortionGlass - Metal Camera Distortion Effects

Metal と AVFoundation を使用したリアルタイム歪みエフェクトカメラアプリです。

## 機能

- **リアルタイムカメラプレビュー**: AVFoundation を使用した高性能カメラキャプチャ
- **Metal レンダリングパイプライン**: CVMetalTextureCache による効率的なテクスチャ変換
- **Metal ベースの歪みエフェクト**:
  - 魚眼エフェクト HQ (高品質・バレル歪み数式)
  - 魚眼エフェクト Fast (高性能・簡略化数式)
  - 波紋エフェクト (Ripple) 
  - 渦巻きエフェクト (Swirl)
  - パススルーモード (デバッグ用)
- **30FPS リアルタイム処理**: Metal の GPU アクセラレーション
- **インタラクティブコントロール**: エフェクトの強度調整
- **パフォーマンス監視**:
  - リアルタイムFPS表示 (Camera + Render)
  - メモリ使用量監視
  - 熱制約監視
  - エラーハンドリング

## 要件

- iOS 15.0+
- Metal 対応デバイス（iPhone 6s 以降）
- 実機でのテストが必要（シミュレーターではカメラアクセス不可）

## プロジェクト構造

```
istortionGlass/
├── Camera/
│   └── CameraManager.swift          # カメラ管理とキャプチャ + FPS監視
├── Metal/
│   ├── MetalRenderer.swift          # Metal レンダリングエンジン + パフォーマンス監視
│   └── Shaders.metal               # GPU シェーダー (メイン + パススルー)
├── Views/
│   └── CameraPreviewView.swift     # カメラプレビューUIView + MTKView統合
├── Utils/
│   └── PerformanceMonitor.swift    # パフォーマンス・メモリ・熱監視
├── ContentView.swift               # メインUI + デバッグ情報表示
├── istortionGlassApp.swift        # アプリエントリーポイント
└── Info.plist                     # アプリ設定（カメラ許可等）
```

## 技術仕様

### アーキテクチャパターン
- **BBMetalImage パターン**: Metal フレームワークの効率的な使用
- **Alex Staravoitau の Metal Camera Tutorial 構造**: カメラとMetalの統合

### パフォーマンス最適化
- **テクスチャキャッシュ**: CVMetalTextureCache による効率的なピクセルバッファ変換
- **非同期処理**: 専用キューでのカメラキャプチャとテクスチャ処理
- **GPU アクセラレーション**: Metal シェーダーでのリアルタイム処理
- **フレームドロップ防止**: バックグラウンドキューでのテクスチャ生成
- **メモリリーク対策**: 適切なweak参照とタイマー管理
- **エラーハンドリング**: 連続失敗検出と自動復旧機能

### エフェクト実装
- **頂点シェーダー**: フルスクリーンクワッド生成
- **フラグメントシェーダー**: UV座標変換による歪み効果
- **Uniform バッファ**: エフェクトパラメーター渡し

## 使用方法

1. **アプリ起動時**: カメラアクセス許可を要求
2. **エフェクト選択**: 画面下部のボタンでエフェクト切り替え
3. **エフェクト制御**:
   - ON/OFFボタンでエフェクトの有効/無効切り替え
   - 強度スライダーで効果の強さを0-100%で調整
   - HQ/FASTボタンで魚眼エフェクトの品質モード切り替え
4. **デバッグモード**: 
   - 情報ボタン (i) でFPS・GPU・メモリ・熱状態を表示
   - RAW/GPUボタンでパススルーモード切り替え
   - TESTボタンで自動パフォーマンステスト実行

## 実機テスト注意

⚠️ **重要**: このアプリは実機でのみ動作します。Xcode シミュレーターではカメラアクセスができないため、物理的な iOS デバイスでのテストが必須です。

## 開発者証明書設定ガイド

### 無料Apple Developer アカウント設定

#### 1. Bundle Identifier の設定
```
推奨フォーマット: com.yourname.istortionglass.uniqueid
例: com.john.istortionglass.dev2025
```

#### 2. Xcode プロジェクト設定手順

1. **プロジェクトを開く**
   - Xcode で `istortionGlass.xcodeproj` を開く

2. **プロジェクト設定**
   - 左側のプロジェクトナビゲーターで「istortionGlass」プロジェクトを選択
   - 「TARGETS」で「istortionGlass」を選択
   - 「Signing & Capabilities」タブを開く

3. **Team とBundle Identifier設定**
   ```
   Team: あなたのApple ID（Personal Team）
   Bundle Identifier: com.yourname.istortionglass.uniqueid
   ```
   
4. **自動管理の有効化**
   - ✅ 「Automatically manage signing」にチェック
   - Bundle Identifierを変更すると自動でプロビジョニングプロファイルが生成される

#### 3. 推奨プロジェクト設定値

```
# General タブ
Display Name: istortionGlass
Bundle Identifier: com.yourname.istortionglass.dev
Version: 1.0
Build: 1
Deployment Target: iOS 15.0

# Signing & Capabilities タブ
Team: [Your Apple ID] (Personal Team)
✅ Automatically manage signing
Provisioning Profile: Xcode Managed Profile

# Build Settings タブ
Development Team: [Your Team ID]
Code Signing Identity: Apple Development
Code Signing Style: Automatic
```

### 有料Apple Developer アカウント設定

有料アカウントをお持ちの場合:

```
Team: [Your Organization/Developer Name]
Bundle Identifier: com.yourcompany.istortionglass
Provisioning Profile: 手動または自動管理
Distribution Certificate: 配布用証明書設定可能
```

## よくあるエラーと対処法

### 1. 開発者証明書ペアリング問題

#### エラー例
```
Unable to install "istortionGlass"
Code signing error: No provisioning profile matching bundle identifier
```

#### 対処法
```bash
# 1. Bundle Identifierを変更
com.yourname.istortionglass.dev → com.yourname.istortionglass.fix

# 2. Xcode で「Product」→「Clean Build Folder」

# 3. 「Automatically manage signing」を一度オフ→オンに切り替え

# 4. 「Signing & Capabilities」でTeamを再選択

# 5. 「Window」→「Devices and Simulators」でデバイス接続を確認
```

### 2. デバイス信頼エラー

#### エラー例
```
This device is not registered for development
```

#### 対処法
```bash
# 1. iPhoneで「設定」→「一般」→「VPNとデバイス管理」
# 2. 開発者アプリセクションで証明書を信頼
# 3. 「開発者向けオプション」で証明書を信頼
```

### 3. Metal対応デバイスエラー

#### エラー例
```
Metal is not supported on this device
```

#### 対処法
```bash
# サポート対象デバイス確認:
- iPhone 6s 以降 ✅
- iPad Air 2 以降 ✅ 
- iPod touch (第7世代) 以降 ✅

# 非対応デバイス:
- iPhone 6 以前 ❌
- iPad Air (第1世代) ❌
- iPod touch (第6世代以前) ❌
```

### 4. カメラアクセス許可エラー

#### エラー例
```
Camera access denied
NSCameraUsageDescription not found
```

#### 対処法
```bash
# 1. Info.plist に NSCameraUsageDescription が含まれていることを確認
# 2. iPhoneで「設定」→「プライバシーとセキュリティ」→「カメラ」
# 3. istortionGlass をオンに切り替え
# 4. アプリを再起動
```

### 5. ビルドエラー

#### エラー例
```
Command failed with exit code 65
Provisioning profile doesn't include signing certificate
```

#### 対処法
```bash
# 1. Xcode > Preferences > Accounts で Apple ID を確認
# 2. 「Download Manual Profiles」をクリック
# 3. 「Automatically manage signing」を再度有効化
# 4. Bundle Identifier をユニークなものに変更
# 5. プロジェクトをクリーンビルド
```

### 6. パフォーマンス問題

#### 症状
```
FPS が 30 を下回る
GPU使用率が 90% を超える
フレームドロップが頻発
```

#### 対処法
```bash
# 1. デバッグ情報で現在の状況を確認
# 2. 魚眼エフェクトを「HQ」から「Fast」に変更
# 3. エフェクト強度を下げる (50% 以下)
# 4. 他のアプリを終了してメモリを確保
# 5. デバイスを冷却 (熱制約の場合)
```

## 開発者向け情報

### エフェクト追加方法
1. `MetalRenderer.DistortionEffect` に新しいケースを追加
2. `Shaders.metal` に対応する歪み関数を実装
3. `ContentView.swift` にUIボタンを追加

### パフォーマンス監視
- カメラFPSとレンダリングFPSの独立監視
- リアルタイムメモリ使用量追跡
- 熱制約状態監視と警告表示
- Metal コマンドバッファ完了時間計測
- 連続エラー検出と自動回復機能

### 魚眼エフェクト実装詳細
- **高品質モード (HQ)**: バレル歪み数式 `r' = r * (1 + k1*r² + k2*r⁴)`
- **高性能モード (Fast)**: 簡略化数式 `r' = r * (1 + k*r²)`
- **エッジ処理**: スムーズフェード機能で自然な境界
- **座標クランプ**: テクスチャ範囲外アクセス防止
- **リアルタイム更新**: 強度パラメータの即座反映

### 自動パフォーマンステスト
- 全エフェクト×強度レベルの組み合わせテスト
- FPS・GPU使用率・フレームドロップ・メモリ使用量を自動計測
- 熱制約状態での性能劣化検出
- 最適/最悪パフォーマンス設定の自動判定

## 実機テスト手順詳細

### Step 1: 初期セットアップ確認

#### 1.1 デバイス接続確認
```bash
# Xcode で確認
1. 「Window」→「Devices and Simulators」を開く
2. 接続されたデバイスが表示されることを確認
3. デバイス横の緑丸（●）が表示されていることを確認
```

#### 1.2 証明書状態確認
```bash
# Signing & Capabilities タブで確認
✅ Team が設定されている
✅ Bundle Identifier がユニーク
✅ Provisioning Profile が生成されている
✅ エラーマークが表示されていない
```

#### 1.3 ビルドテスト
```bash
# 初回ビルド実行
1. 「Product」→「Clean Build Folder」
2. 「Product」→「Build」(⌘+B)
3. エラーなくビルド完了することを確認
```

### Step 2: 基本動作確認

#### 2.1 アプリ起動テスト
```bash
1. デバイスでアプリを起動
2. カメラアクセス許可ダイアログで「OK」を選択
3. カメラプレビューが表示されることを確認
4. エラーメッセージが表示されないことを確認
```

#### 2.2 UI操作テスト
```bash
# 基本UI確認
- 情報ボタン(i): デバッグ情報表示/非表示
- RAW/GPUボタン: パススルーモード切り替え
- ON/OFFボタン: エフェクト有効/無効切り替え
- エフェクトボタン: Original/Fisheye/Ripple/Swirl
- 強度スライダー: 0-100%調整（エフェクト有効時のみ）
```

### Step 3: パフォーマンステスト

#### 3.1 基準性能測定
```bash
# パススルーモードでの基準値測定
1. RAWボタンを押してパススルーモード有効化
2. デバッグ情報を表示
3. 30秒間動作させて以下を記録:
   - Camera FPS: 目標30FPS
   - Render FPS: 目標30FPS
   - GPU Load: 基準値として記録
   - Memory: ベースライン記録
```

#### 3.2 魚眼エフェクトテスト
```bash
# HQ vs Fast モード比較
1. Fisheyeボタンを選択
2. HQモードで30秒測定:
   - FPS維持率
   - GPU使用率
   - フレームドロップ数
3. FASTボタンを押してFastモードに切り替え
4. 同じ条件で30秒測定
5. 品質とパフォーマンスを比較評価
```

#### 3.3 強度調整テスト
```bash
# リアルタイム調整の滑らかさ確認
1. 魚眼エフェクト有効化
2. 強度スライダーを以下パターンで操作:
   - 0% → 100% (5秒かけてゆっくり)
   - 100% → 0% (5秒かけてゆっくり)
   - 0% ↔ 100% (高速切り替え10回)
3. 各操作でFPSが30を維持することを確認
4. エフェクトが滑らかに変化することを確認
```

### Step 4: 負荷テスト

#### 4.1 長時間動作テスト
```bash
# 熱制約・バッテリー影響確認
1. 魚眼HQモード、強度100%で開始
2. 連続30分動作させる
3. 5分毎に以下を記録:
   - FPS
   - GPU Load
   - Memory Usage
   - Thermal State
   - Battery Level
4. 熱制約による性能低下を監視
```

#### 4.2 メモリリークテスト
```bash
# メモリ使用量の安定性確認
1. アプリ起動直後のメモリ使用量を記録
2. 全エフェクトを順番に5分ずつ実行:
   - Original → Fisheye HQ → Fisheye Fast → Ripple → Swirl
3. 各エフェクト後のメモリ使用量を確認
4. 初期値から大幅に増加していないことを確認
5. Originalに戻した時にメモリが解放されることを確認
```

### Step 5: 自動テスト実行

#### 5.1 自動パフォーマンステスト
```bash
# 科学的な性能比較
1. デバッグ情報を表示
2. 「TEST」ボタンを押してテスト開始
3. 全エフェクト×強度レベルの自動テスト実行（約15分）
4. テスト完了後、コンソールログで結果確認
5. 最適設定の判定結果を記録
```

#### 5.2 結果分析
```bash
# テスト結果の評価
- 30FPS維持できる最高品質設定を特定
- GPU使用率90%以下の安全な動作範囲を確認
- フレームドロップ発生条件を把握
- バッテリー影響が最小の設定を決定
```

### Step 6: エラーハンドリングテスト

#### 6.1 意図的エラー発生
```bash
# 異常状態での動作確認
1. アプリ動作中にカメラを他のアプリで使用
2. メモリ不足状態でのエフェクト切り替え
3. 熱制約状態での高負荷エフェクト実行
4. 各状況でアプリがクラッシュしないことを確認
```

### 実機テスト項目チェックリスト
- ✅ 30FPS安定動作の確認
- ✅ 画質劣化なしの検証
- ✅ 熱制約での動作継続
- ✅ メモリリークなし
- ✅ エラーハンドリング動作
- ✅ パススルーモードでの基準性能測定
- ✅ リアルタイム強度調整の滑らかさ
- ✅ エフェクト切り替え時のパフォーマンス影響
- ✅ バッテリー消費量測定
- ✅ 自動テスト結果の妥当性確認
- ✅ UI操作の応答性確認
- ✅ 異常状態での安定性確認

## クイックリファレンス

### 証明書問題解決チェックリスト
```bash
□ Bundle Identifier がユニーク (com.yourname.istortionglass.uniqueid)
□ Team が設定済み (Personal Team または Organization)
□ "Automatically manage signing" が有効
□ デバイスが信頼済み
□ Info.plist に NSCameraUsageDescription が存在
□ iOS 15.0+ 対応デバイス
□ Metal 対応デバイス (iPhone 6s+)
```

### 推奨開発環境
```bash
# 最小要件
Xcode: 14.0+
iOS Deployment Target: 15.0
Device: iPhone 6s / iPad Air 2 以降
Apple ID: 無料アカウント対応

# 推奨環境  
Xcode: 最新版
iOS: 16.0+
Device: iPhone 12 以降 (A14 Bionic+)
Apple Developer Account: 有料アカウント (推奨)
```

### 緊急時対処法
```bash
# ビルドエラー時
1. Bundle Identifier を変更
2. Clean Build Folder
3. Derived Data を削除
4. Xcode 再起動
5. デバイス再接続

# 実機動作不良時
1. アプリ削除 → 再インストール
2. デバイス再起動
3. 開発者証明書を再信頼
4. パススルーモードで基準動作確認
5. 他のアプリを終了してリソース確保
```

## ライセンス

MIT License
