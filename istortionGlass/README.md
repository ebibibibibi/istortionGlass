# istortionGlass - Metal Camera Distortion Effects

Metal と AVFoundation を使用したリアルタイム歪みエフェクトカメラアプリです。

## 機能

- **リアルタイムカメラプレビュー**: AVFoundation を使用した高性能カメラキャプチャ
- **Metal ベースの歪みエフェクト**:
  - 魚眼エフェクト (Fisheye)
  - 波紋エフェクト (Ripple) 
  - 渦巻きエフェクト (Swirl)
- **30FPS リアルタイム処理**: Metal の GPU アクセラレーション
- **インタラクティブコントロール**: エフェクトの強度調整

## 要件

- iOS 15.0+
- Metal 対応デバイス（iPhone 6s 以降）
- 実機でのテストが必要（シミュレーターではカメラアクセス不可）

## プロジェクト構造

```
istortionGlass/
├── Camera/
│   └── CameraManager.swift          # カメラ管理とキャプチャ
├── Metal/
│   ├── MetalRenderer.swift          # Metal レンダリングエンジン
│   └── Shaders.metal               # GPU シェーダー
├── Views/
│   └── CameraPreviewView.swift     # カメラプレビューUIView
├── ContentView.swift               # メインUI
├── istortionGlassApp.swift        # アプリエントリーポイント
└── Info.plist                     # アプリ設定（カメラ許可等）
```

## 技術仕様

### アーキテクチャパターン
- **BBMetalImage パターン**: Metal フレームワークの効率的な使用
- **Alex Staravoitau の Metal Camera Tutorial 構造**: カメラとMetalの統合

### パフォーマンス最適化
- **テクスチャキャッシュ**: CVMetalTextureCache 使用
- **非同期処理**: 専用キューでのカメラキャプチャ
- **GPU アクセラレーション**: Metal シェーダーでのリアルタイム処理

### エフェクト実装
- **頂点シェーダー**: フルスクリーンクワッド生成
- **フラグメントシェーダー**: UV座標変換による歪み効果
- **Uniform バッファ**: エフェクトパラメーター渡し

## 使用方法

1. **アプリ起動時**: カメラアクセス許可を要求
2. **エフェクト選択**: 画面下部のボタンでエフェクト切り替え
3. **強度調整**: スライダーでエフェクトの強度を調整

## 実機テスト注意

⚠️ **重要**: このアプリは実機でのみ動作します。Xcode シミュレーターではカメラアクセスができないため、物理的な iOS デバイスでのテストが必須です。

## 開発者向け情報

### エフェクト追加方法
1. `MetalRenderer.DistortionEffect` に新しいケースを追加
2. `Shaders.metal` に対応する歪み関数を実装
3. `ContentView.swift` にUIボタンを追加

### パフォーマンス監視
- Metal Performance Shaders を使用してGPU使用率を監視
- フレームレート監視により最適化ポイントを特定

## ライセンス

MIT License
