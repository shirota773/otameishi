# Design System — おためいし

Version 1.0 | 対象: Flutter MVP (Phases 0–7)

---

## 1. 設計原則

1. **イベント会場での可読性優先** — 強コントラスト、大きなタッチターゲット
2. **ジャーナル感** — 名刺管理ソフトではなく、ファン手帳に近い温かみ
3. **プライバシー信頼** — UIはデータが端末に閉じていることを暗示する
4. **片手操作** — 主要アクションは画面下部1/3に配置

---

## 2. カラーパレット

### 2-1. ブランドカラー (Seed)

アクセントは「推し活」らしい彩度の高い桜ピンク。

| トークン名 | ライト (Hex) | ダーク (Hex) | 用途 |
|---|---|---|---|
| `color.brand.primary` | `#E91E8C` | `#F06292` | メインアクセント |
| `color.brand.secondary` | `#7B2FBE` | `#CE93D8` | セカンダリアクセント (タグ等) |

### 2-2. サーフェス

| トークン名 | ライト (Hex) | ダーク (Hex) | 用途 |
|---|---|---|---|
| `color.surface.primary` | `#FFFFFF` | `#121212` | メイン背景 |
| `color.surface.secondary` | `#F5F5F5` | `#1E1E1E` | カード背景、セクション背景 |
| `color.surface.tertiary` | `#EEEEEE` | `#2A2A2A` | 区切り、インプット背景 |
| `color.surface.overlay` | `rgba(0,0,0,0.40)` | `rgba(0,0,0,0.60)` | モーダルスクリム |

### 2-3. テキスト

| トークン名 | ライト (Hex) | ダーク (Hex) | コントラスト比 (対 surface.primary) | WCAG |
|---|---|---|---|---|
| `color.text.primary` | `#1A1A1A` | `#F0F0F0` | 18.5:1 / 18.1:1 | AAA |
| `color.text.secondary` | `#555555` | `#AAAAAA` | 7.0:1 / 5.3:1 | AA |
| `color.text.tertiary` | `#888888` | `#777777` | 3.5:1 / 3.0:1 | AA Large のみ ※1 |
| `color.text.on-brand` | `#FFFFFF` | `#FFFFFF` | 4.6:1 (対 brand.primary) | AA |
| `color.text.link` | `#0066CC` | `#5AAEFF` | 4.6:1 / 4.5:1 | AA |

※1 `color.text.tertiary` は 14px 以下の本文には使用不可。プレースホルダー・ラベル補足にのみ使用すること。

### 2-4. セマンティックカラー

| トークン名 | ライト (Hex) | ダーク (Hex) | 用途 |
|---|---|---|---|
| `color.semantic.success` | `#1B8A4C` | `#4CAF7D` | 保存完了、OCR成功 |
| `color.semantic.warning` | `#B45309` | `#F59E0B` | OCR要確認 |
| `color.semantic.error` | `#C0392B` | `#EF5350` | エラー、削除確認 |
| `color.semantic.info` | `#1565C0` | `#64B5F6` | ヒント、通知 |

### 2-5. カメラUI専用

カメラプレビューは常時ダーク背景。ライト/ダークモードに関わらず固定。

| トークン名 | Hex | 用途 |
|---|---|---|
| `color.camera.overlay` | `rgba(0,0,0,0.55)` | コーナー検出外マスク |
| `color.camera.guide` | `#FFFFFF` | コーナー検出枠線 |
| `color.camera.guide-active` | `#E91E8C` | 名刺検出済み枠線 |
| `color.camera.shutter` | `#FFFFFF` | シャッターボタン |
| `color.camera.shutter-inner` | `#E91E8C` | シャッター内円 |

---

## 3. タイポグラフィ

### フォントファミリー

- **日本語**: Noto Sans JP (wght: 400 Regular, 500 Medium, 700 Bold)
- **英数字**: Noto Sans (same weights, fallback within Noto Sans JP)
- **システムフォント fallback**: `.SF Pro Text` (iOS), `Roboto` (Android)

### タイプスケール

| トークン名 | サイズ (sp) | ウェイト | 行高 | 用途 |
|---|---|---|---|---|
| `type.display` | 28 | Bold (700) | 1.3 | イベント名など大見出し |
| `type.headline` | 22 | Bold (700) | 1.35 | 画面タイトル |
| `type.title` | 18 | Medium (500) | 1.4 | カードタイトル、セクション見出し |
| `type.body` | 16 | Regular (400) | 1.55 | 本文、メモ |
| `type.body-bold` | 16 | Bold (700) | 1.55 | 強調本文 |
| `type.label` | 14 | Medium (500) | 1.4 | ラベル、タグ |
| `type.caption` | 12 | Regular (400) | 1.4 | 補足テキスト、タイムスタンプ |
| `type.overline` | 11 | Medium (500) | 1.3 | セクション分類 (全大文字不可、日本語で使用) |

### Dynamic Type (iOS) / Font Scale (Android)

- すべてのテキストが端末のフォントサイズ設定で最大 200% スケールを想定
- 200% 時にトランケートではなく折り返しで対応すること
- `type.caption` は最小フォントサイズとして機能。これより小さい文字は仕様に含めない

---

## 4. スペーシングスケール

4px ベースグリッド。

| トークン名 | px | 用途例 |
|---|---|---|
| `space.1` | 4 | アイコンと隣接テキスト間 |
| `space.2` | 8 | テキスト行間の追加余白 |
| `space.3` | 12 | カード内パディング小 |
| `space.4` | 16 | 標準コンテンツ余白 |
| `space.5` | 20 | セクション間隔小 |
| `space.6` | 24 | カード内パディング標準 |
| `space.8` | 32 | セクション間隔大 |
| `space.10` | 40 | 画面上下パディング |
| `space.12` | 48 | ボトムナビ高さ基準 |
| `space.16` | 64 | FAB・シャッターボタン余白 |

---

## 5. ボーダー半径スケール

| トークン名 | px | 用途 |
|---|---|---|
| `radius.xs` | 4 | タグチップ内小要素 |
| `radius.sm` | 8 | インプットフィールド |
| `radius.md` | 12 | カードコンポーネント |
| `radius.lg` | 16 | ボトムシート、モーダル上角 |
| `radius.xl` | 24 | キャプチャレビュー画像 |
| `radius.full` | 9999 | タグチップ、FAB、アバター |

---

## 6. エレベーション (シャドウ)

Flutter `BoxShadow` 相当。

| トークン名 | ライト | ダーク | 用途 |
|---|---|---|---|
| `elevation.none` | なし | なし | フラット要素 |
| `elevation.low` | `0 1px 3px rgba(0,0,0,0.12)` | `0 1px 3px rgba(0,0,0,0.40)` | カード、インプット |
| `elevation.mid` | `0 4px 12px rgba(0,0,0,0.15)` | `0 4px 12px rgba(0,0,0,0.50)` | FAB、ボトムシート |
| `elevation.high` | `0 8px 24px rgba(0,0,0,0.20)` | `0 8px 24px rgba(0,0,0,0.60)` | モーダル、フルスクリーンオーバーレイ |

---

## 7. モーションタイミングトークン

| トークン名 | 値 | イージング | 用途 |
|---|---|---|---|
| `motion.instant` | 0ms | — | 状態トグル (フラッシュ等) |
| `motion.fast` | 150ms | `easeOut` | タップフィードバック |
| `motion.standard` | 250ms | `easeInOut` | 画面内要素のトランジション |
| `motion.enter` | 300ms | `easeOut` | 画面のエンター |
| `motion.exit` | 200ms | `easeIn` | 画面のエグジット |
| `motion.spring` | 400ms | `spring(stiffness:200, damping:25)` | ボトムシートスプリング |

システム設定「視差効果を減らす」(iOS) / 「アニメーションを無効化」(Android) が ON のとき、`motion.standard` 以上の duration を 0 に落とすこと。

---

## 8. アイコノグラフィ

- **プラットフォーム**: Material Symbols Outlined (Flutter `material_symbols_icons` パッケージ)
- **サイズ**: 24dp 標準、20dp コンパクト文脈、32dp 強調
- **ウェイト**: 400 (標準)、600 (アクティブ状態)
- **塗り**: 0 (Outlined) 標準、1 (Filled) でアクティブ状態を区別

### キーアイコン対応表

| 用途 | Material Symbol 名 | 補足 |
|---|---|---|
| カメラ・撮影 | `photo_camera` | シャッターボタン周辺 |
| ホーム・カード一覧 | `style` | 名刺っぽいカードのニュアンス |
| 検索 | `search` | |
| イベント | `event` | |
| タグ | `label` | |
| メモ | `notes` | |
| SNSリンク (X) | `link` (+ X ロゴ文字) | カスタムSVGでX公式ロゴを使用 |
| 設定 | `settings` | |
| 追加・新規 | `add` | FAB内 |
| 削除 | `delete` | |
| 編集 | `edit` | |
| フラッシュON | `flash_on` | |
| フラッシュOFF | `flash_off` | |
| 戻る | `arrow_back` | Android / `chevron_left` iOS |
| 閉じる | `close` | |
| 完了・確定 | `check` | |
| フィルタ | `filter_list` | |
| ソート | `sort` | |
| 外部リンク | `open_in_new` | SNS遷移 |

---

## 9. コンポーネント共通仕様

### 9-1. プライマリボタン

- 高さ: 52dp (タッチターゲット 44dp 以上確保)
- 背景: `color.brand.primary`
- テキスト: `type.body-bold`, `color.text.on-brand`
- 角丸: `radius.full`
- 幅: 画面幅 − `space.8` × 2

### 9-2. セカンダリボタン

- 高さ: 52dp
- 背景: transparent
- 枠線: 2px `color.brand.primary`
- テキスト: `type.body-bold`, `color.brand.primary`
- 角丸: `radius.full`

### 9-3. タグチップ

- 高さ: 32dp (タッチターゲット padding で 44dp 確保)
- 背景: `color.surface.secondary`
- テキスト: `type.label`, `color.text.secondary`
- 角丸: `radius.full`
- 選択時: 背景 `color.brand.secondary`, テキスト `color.text.on-brand`

### 9-4. カードサムネイル

- アスペクト比: 91:55 (名刺標準比率)
- 角丸: `radius.md`
- エレベーション: `elevation.low`
- 画像読み込み中: `color.surface.secondary` + シマーアニメーション

### 9-5. ボトムナビゲーションバー

- 高さ: `space.12` + セーフエリア
- タブ: 4つ (ホーム、検索、イベント、設定)
- アクティブアイコン: `color.brand.primary`, Filled
- 非アクティブ: `color.text.tertiary`, Outlined
- 背景: `color.surface.primary`, `elevation.low`
- FABはボトムナビ中央に配置しない — キャプチャFABは各画面固有

### 9-6. フローティングアクションボタン (FAB)

- サイズ: 64dp × 64dp
- 背景: `color.brand.primary`
- アイコン: `photo_camera`, 32dp, `color.text.on-brand`
- 位置: 画面右下、`space.6` マージン、ボトムナビ上
- エレベーション: `elevation.mid`

### 9-7. ボトムシート

- 角丸 (上部のみ): `radius.lg`
- 背景: `color.surface.primary`
- ドラッグハンドル: 幅 40dp, 高さ 4dp, `color.surface.tertiary`
- エレベーション: `elevation.high`

---

## 10. ナビゲーション構造

```
BottomNavigationBar (常時表示)
  ├── [style] ホーム / カード一覧
  ├── [search] 検索
  ├── [event] イベント
  └── [settings] 設定

FAB (カメラ) — カード一覧・ホーム画面のみ表示
  └── → キャプチャ画面 (フルスクリーン、ナビバー非表示)
      └── → キャプチャレビュー画面
          └── → (保存後) カード詳細 or カード一覧

カード一覧 → カード詳細
イベント一覧 → イベント詳細
タグ管理 → 設定画面からアクセス
```

---

## 11. セーフエリア・ノッチ対応

- すべての画面で `SafeArea` を適用
- ボトムナビゲーションバーはシステムのホームインジケータ領域を考慮
- キャプチャ画面のみフルスクリーン (ステータスバー非表示可)
- ノッチ/Dynamic Island 領域へのコンテンツ配置は禁止
