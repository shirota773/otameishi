# エントリーフロー v2 — 撮影 / 手入力 2系統

Version 2.0 — supersedes `capture-flow.md` for the entry point only. The OCR/補正/保存ステップ詳細は v1 を参照。

---

## 1. 背景

v1 では FAB タップ → カメラ起動の 1 系統だった。v2 では「保存済み画像から手入力で登録する」ユースケースが追加され、ホームに 2 系統のエントリーポイントを提供する。

| 系統 | 想定ケース |
|---|---|
| 撮影 (auto) | その場で受け取った名刺を即スキャン。OCR 自動入力 + 確認 |
| 手入力 (manual) | 過去に撮ったスクショ・ギャラリー保存済み画像。OCR 自動入力なし、ユーザー手入力 |

両系統とも、保存先の画面は同じ `CaptureReviewScreen` (改訂版 v2)。

---

## 2. ホームの FAB — 設計判断

**結論: 単一 FAB + ボトムシート 2 択。SpeedDial や 2 FAB は採用しない。**

理由:
- ブランド ピンク FAB はビジュアル上の起点。重要度を保つには 1 個のままが望ましい
- SpeedDial (radial fan) は MVP のミニマル感に合わない、また Material 3 で非推奨方向
- 2 FAB は親指リーチを浪費し、副 FAB が「2番手」に見えて手入力フローが弱くなる
- ボトムシートは Material 3 標準、片手親指で操作しやすい (画面下半分)

タップ動線:
```
[Home: カード一覧]
        │
        │ FAB タップ                      ← Tap 1
        ▼
[ModalBottomSheet: 2択]
   ┌──────────────────┐
   │ 📷 撮影          │ → カメラフロー (v1 と同じ)
   │ 🖼  画像から手入力 │ → 手入力フロー (新)
   └──────────────────┘
                                       ← Tap 2 (どちらか)
```

タップ回数は両系統とも +1 増えるが、誤エントリー回避と発見性のトレードオフとして受容する。

---

## 3. FAB とボトムシートの仕様

### FAB

| 項目 | 値 |
|---|---|
| アイコン | `Icons.add` (Material) — `photo_camera` ではない |
| 背景色 | `AppColors.brandPrimary` (#E91E8C) |
| 前景色 | `Colors.white` |
| Semantics label | `"名刺を追加"` |
| 位置 | 既存通り (画面右下、`FloatingActionButtonLocation.endFloat`) |

### ボトムシート

| 項目 | 値 |
|---|---|
| 種類 | `showModalBottomSheet` (Material 3) |
| 背景 | `Theme.of(context).colorScheme.surface` |
| 角丸 | `AppRadius.lg` (上端のみ) |
| パディング | `AppSpacing.s4` 全周 |
| ハンドルバー | デフォルト表示 (Material 3) |
| 高さ | `wrapContent` (2項目 + ヘッダー + 余白) |

### 選択肢項目

両項目とも `ListTile` で揃える:

| 項目 | アイコン | タイトル | サブタイトル |
|---|---|---|---|
| 撮影 | `Icons.photo_camera_outlined` (28dp, brandPrimary) | `撮影` | `その場で名刺を読み取り` |
| 手入力 | `Icons.image_outlined` (28dp, brandPrimary) | `画像から手入力` | `保存済み画像を選んで自分で入力` |

レイアウト:
- ListTile の `leading` にアイコン (44×44 タップ領域)
- タイトルは `Theme.textTheme.titleMedium`
- サブタイトルは `Theme.textTheme.bodySmall` + `AppColors.textSecondary`
- 両項目間に `Divider` 不要 (ListTile デフォルトの間隔で十分)
- ボトムシート上端に `Padding(top: s2)` + 視覚タイトル "追加方法" (任意、省略可)

---

## 4. フロー詳細

### 4-1. 撮影フロー (既存、変更なし)

ボトムシート「撮影」タップ → ボトムシート閉じ → `pushNamed('/capture')` (既存)。それ以降の挙動は `capture-flow.md` v1 のまま (パーミッション → カメラプレビュー → シャッター → 補正・OCR → レビュー画面)。

### 4-2. 手入力フロー (新規)

```
[ボトムシート: 画像から手入力]
        │
        │ タップ                                  ← Tap 2
        ▼
[ボトムシートを閉じる (自動)]
        │
        ▼
[OS 標準の画像ピッカー (image_picker pkg)]
        │
        ├──[キャンセル / Back] ── ホームに残留 (何も起きない)
        │
        │ 画像を1枚選択
        ▼
[CaptureReviewScreen (v2) — manual モード]
   - 画像プレビュー: 選択した画像をそのまま表示
   - 表示名 / X / URL / タグ / メモ: 全フィールド空欄
   - OCR は実行しない
        │
        │ 入力 → 「保存する」                       ← Tap 3
        ▼
[保存処理 → ホームに戻る (snackbar 表示)]
```

ポイント:
- OCR を一切走らせない (`CardDraft.ocr = null, extractedData = null`)
- 画像はそのまま保存 (透視補正・ノイズ除去なし、`StorageService.saveCardImage` で 1920px キャップ + 1MB 以下に再エンコードのみ)
- ユーザーが画像ピッカーから戻る (キャンセル) と何も起きない (ボトムシートも既に閉じている)

### 4-3. パーミッション

| プラットフォーム | 必要パーミッション | 取得タイミング |
|---|---|---|
| iOS | `NSPhotoLibraryUsageDescription` | `image_picker` が自動でハンドル |
| Android 13+ | `READ_MEDIA_IMAGES` | `image_picker` が自動でハンドル |
| Android 12 以下 | `READ_EXTERNAL_STORAGE` | 同上 |

拒否時: ピッカーは即終了。アプリは何もしない (ホームに残留)。ユーザーが再度タップすれば再リクエスト。

---

## 5. ボトムシート以外の挙動

| 状況 | 挙動 |
|---|---|
| ボトムシート表示中に Back キー | シートを閉じる、ホームに残留 |
| ボトムシート表示中に画面外タップ | シートを閉じる |
| キーボード表示 | 該当しない (シート内に入力フィールドなし) |
| Talkback / VoiceOver | シート表示時にフォーカスを移動、`"追加方法を選択"` |

---

## 6. 既存 v1 との差分まとめ

| 要素 | v1 | v2 |
|---|---|---|
| FAB アイコン | `Icons.photo_camera` | `Icons.add` |
| FAB タップ → | カメラ画面に直接遷移 | ボトムシートで 2 択 |
| 手入力エントリー | なし | 新規追加 |
| Review 画面の前提 | 必ず OCR 結果あり | OCR 有/無の両方を扱う (v2 で対応) |
| タップ回数 | カメラ起動まで 1 タップ | 2 タップ (シート経由) |

---

## 7. 実装メモ (frontend向け)

- 既存 `HomeScreen` の FAB の `onPressed` を `showModalBottomSheet` 呼び出しに差し替え
- ボトムシート内の 2 択は別 widget (`_EntryChoiceSheet`) に切り出して `home_screen.dart` 内 or `widgets/entry_choice_sheet.dart`
- 「画像から手入力」選択時のフロー:
  ```dart
  Navigator.pop(context);          // close sheet
  final picker = ImagePicker();
  final picked = await picker.pickImage(source: ImageSource.gallery);
  if (picked == null) return;      // user cancelled
  final bytes = await picked.readAsBytes();
  // manual = skip OCR, just save image bytes
  final draft = await ref.read(manualEntryDraftBuilderProvider)(bytes);
  if (!mounted) return;
  Navigator.of(context).pushNamed('/capture/review', arguments: draft);
  ```
- `manualEntryDraftBuilderProvider` は backend が追加する新ヘルパー (画像を 1920/1MB に丸めて保存し、`CardDraft(imagePath: ..., ocr: null, extractedData: null)` を返す)
- 詳細仕様は `screens/capture-review-v2.md` を参照
