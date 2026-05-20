# Marketing assets

App Store / Play Store 配信物 + プレス用素材を集約する。アプリのバージョン (`app/pubspec.yaml` の `version:`) と一緒に管理し、リリースのたびに更新する。

## レイアウト

```
marketing/
  app-store/          ← iOS / App Store
    icon-1024.png       App Store 用 1024x1024 (alpha なし)
    screenshots/
      iphone-6.7/       1290x2796 (iPhone 16 Pro Max 等)
      iphone-6.5/       1242x2688 (iPhone 11 Pro Max 等、legacy 必須)
    metadata-ja.md      アプリ名 / 説明文 / キーワード / プロモテキスト
    metadata-en.md      英語版 (任意)
  play-store/         ← Android / Google Play
    icon-512.png        Play Store 用 512x512
    feature-graphic-1024x500.png   必須
    screenshots/
      phone/            最低 2 枚 (16:9 〜 9:16)
    metadata-ja.md      アプリ名 / 短い説明 (80字) / 詳細説明
    metadata-en.md
  shared/             ← 両ストア共通の素材
    press-kit/          ロゴ・スクショ・1枚紹介
    social/             SNS 用バナー
```

## ストア要件のメモ

- **両ストア共通**: プライバシーポリシー URL が審査で必須。`docs/privacy-policy.md` を GitHub Pages 等で公開して URL 化する
- **App Store**: スクショは最低 1 デバイス (iPhone 6.7" or 6.5") 必須。プロモテキストは 170 字
- **Play Store**: 機能グラフィック (1024x500) 必須、スクショは最低 2 枚、短い説明 80 字、詳細説明 4000 字
