# キャプチャレビュー画面 v2 — 編集可・手入力対応

Version 2.0 — supersedes `capture-review.md`. 主な変更は:
1. X アカウント / URL が**編集可能なリスト**に (v1 は読み取り専用 Chip / Text)
2. 撮影フロー (OCR 結果あり) と手入力フロー (OCR なし) の両方を扱う
3. 「撮り直す」ボタンの表示は撮影フロー時のみ、手入力時は「キャンセル」

---

## 1. 目的

撮影・補正済み or ユーザーが選択した名刺画像を確認し、表示名・X アカウント・URL・タグ・メモを編集してから保存する。OCR 結果は「候補」として埋まり、ユーザーは自由に書き換え・追加・削除できる。

---

## 2. エントリポイント

| 経由 | 状態 | プレフィル |
|---|---|---|
| キャプチャ画面シャッター後 (撮影フロー) | `mode = autoOcr` | OCR 候補で各フィールドを埋める |
| ホーム FAB → 画像ピッカー (手入力フロー) | `mode = manual` | すべて空欄、画像のみ表示 |

両エントリーで同じ `CaptureReviewScreen` を使う。モードは `CardDraft` に OCR 結果が含まれているかで判定:
```dart
final isAuto = widget.draft.extractedData != null;
```

---

## 3. レイアウト (ASCII)

```
┌─────────────────────────────────┐  ← StatusBar
│ ✕  内容を確認                    │  ← AppBar: 左端 close
├─────────────────────────────────┤
│                                 │  ← スクロールコンテンツ
│ ┌─────────────────────────────┐ │
│ │                             │ │  ← 名刺画像プレビュー (radius.xl, aspect 91:55)
│ │      [画像]                  │ │    撮影: 補正済み画像 / 手入力: 選択画像そのまま
│ └─────────────────────────────┘ │
│                                 │
│ 表示名                          │  ← type.label
│ ┌─────────────────────────────┐ │
│ │ じゅんじゅん                 │ │  ← TextField (撮影: OCR候補 / 手入力: 空)
│ └─────────────────────────────┘ │
│                                 │
│ X アカウント                    │  ← type.label
│ ┌─────────────────────────────┐ │
│ │ @junjun000918           [🗑] │ │  ← TextField + 削除アイコン
│ └─────────────────────────────┘ │
│ ┌─────────────────────────────┐ │
│ │ @sub_account            [🗑] │ │  ← 2件目以降は + で追加可
│ └─────────────────────────────┘ │
│ [ + X アカウントを追加        ]│  ← OutlinedButton, brandPrimary outline
│                                 │
│ リンク                          │
│ ┌─────────────────────────────┐ │
│ │ https://example.com     [🗑] │ │  ← TextField + 削除アイコン
│ └─────────────────────────────┘ │
│ [ + リンクを追加              ]│
│                                 │
│ タグ                            │  ← 既存どおり
│ ┌─────────────────────────────┐ │
│ │ ホロ Vtuber 推し活            │ │  ← スペース・カンマ区切り (既存)
│ └─────────────────────────────┘ │
│                                 │
│ メモ (端末のみ)                  │
│ ┌─────────────────────────────┐ │
│ │ (4行 multiline)               │ │
│ └─────────────────────────────┘ │
│                                 │
│ [ 保存                        ] │  ← ElevatedButton (フル幅)
│ [ 撮り直す / キャンセル        ]│  ← OutlinedButton (モード依存)
│                                 │
└─────────────────────────────────┘  ← SafeArea
```

---

## 4. フィールド仕様

### 4-1. 画像プレビュー

| 項目 | 値 |
|---|---|
| アスペクト比 | `91 / 55` (横向き名刺デフォルト) |
| 縦向き判定 | backend が出力した width/height で自動 (`height > width` なら `55/91`) |
| 角丸 | `AppRadius.xl` |
| BoxFit | `BoxFit.cover` |
| プレースホルダー | 画像ファイル不在時はグレー背景 + `Icons.image_outlined` |

### 4-2. 表示名 (TextField)

| 項目 | 値 |
|---|---|
| プレフィル | `extractedData?.nameCandidate ?? ''` |
| ヒント | `'名前を入力'` |
| 入力制限 | `maxLength: 50` (counter は非表示) |
| Autofill hints | `[AutofillHints.name]` |

### 4-3. X アカウント — 編集可能リスト

リスト ロジック:
- 内部状態: `List<TextEditingController> _xCtrls`
- 撮影フロー初期化: `extractedData!.xHandles` 各値で TextEditingController 生成
- 手入力フロー初期化: 空リスト (= 行 0)
- 各行は `Row(TextField + IconButton(Icons.delete_outline))`
- TextField の `prefixText` に `'@'` を表示 (ユーザーは @ を含めずに入力可)
  - 内部保存時に `@` を先頭に付与 (既に `@` から始まる場合は重複させない)
- 削除ボタン: 行を即削除 (確認ダイアログなし、Undo は v2 対象外)
- 末尾の `+ X アカウントを追加` ボタンは常に表示
- 空行のまま保存ボタンを押すと、空行は自動的にフィルタされる (バリデーションエラーにしない)

検証:
- 1行あたり: `@[A-Za-z0-9_]{1,15}` の正規表現に**マッチしないと色付き警告** (フィールド枠 `color.semantic.warning`)。保存自体はブロックしない (ユーザー側に判断を委ねる)

### 4-4. リンク — 編集可能リスト

X アカウントと同じ構造:
- 内部状態: `List<TextEditingController> _urlCtrls`
- 撮影フロー初期化: `extractedData!.urls` で生成
- 手入力フロー初期化: 空リスト
- TextField: `keyboardType: TextInputType.url`
- `prefixText` なし
- 入力検証: `Uri.tryParse(value)?.hasAbsolutePath` で `https?://` を含むか確認、未含有なら警告色 (保存はブロックしない)
- 末尾に `+ リンクを追加` ボタン

### 4-5. タグ・メモ (既存どおり)

v1 から変更なし。

---

## 5. ボタン

### 5-1. 保存ボタン

| 項目 | 値 |
|---|---|
| Widget | `ElevatedButton` (フル幅) |
| ラベル | `保存` |
| 高さ | 52dp |
| 押下時 | スピナー (`CircularProgressIndicator` 22dp 白) に差し替え |
| 押下中 | フォーム全体を `IgnorePointer` で無効化 |
| 押下後 | 既存どおり `pushNamedAndRemoveUntil('/', (r) => false)` でホームへ |

### 5-2. キャンセル / 撮り直す

ラベルはエントリーモードで切り替える:

| モード | ラベル | 挙動 |
|---|---|---|
| autoOcr (撮影フロー) | `撮り直す` | `Navigator.pop` (= キャプチャ画面に戻る) |
| manual (手入力フロー) | `キャンセル` | `Navigator.pop` (= ホームに戻る) |

判定:
```dart
final isManual = widget.draft.extractedData == null;
final label = isManual ? 'キャンセル' : '撮り直す';
```

---

## 6. バリデーション

**最低限の保存条件**: なし。空のままでも保存可 (画像 + 何かが残る)。

ただし、すべて空欄 (`name == null && xHandles.isEmpty && urls.isEmpty && tagNames.isEmpty && memo == null`) の場合は確認ダイアログを 1 度だけ出す:

```
タイトル: 内容が空ですが保存しますか?
本文:    画像だけのカードとして登録されます。
OK:     保存
キャンセル: 戻る
```

理由: 推し活コンテキストでは「画像だけ」も有効 (絵柄の保存)、ただしうっかり全部空のまま誤タップした場合の救済として確認を入れる。

---

## 7. 状態

| 状態 | 名称 | 表示 |
|---|---|---|
| 通常 (autoOcr) | populated | 全フィールドに OCR 候補が埋まる |
| 通常 (manual) | blank | 画像のみ表示、フィールド空 |
| 保存中 | saving | 保存ボタンスピナー、フォーム無効化 |
| 保存エラー | error | エラーバナー (フォーム残留、入力保持) |

---

## 8. キャンセル時の挙動

- AppBar の `close` (✕) も `Navigator.pop` (キャンセル / 撮り直すと同じ)
- 入力途中での `pop` 防止確認は v2 では入れない (MVP スコープ外)

---

## 9. アクセシビリティ

| 要素 | Semantics ラベル |
|---|---|
| 画像プレビュー | `'名刺画像'` |
| X アカウント追加ボタン | `'X アカウントを追加'` |
| X アカウント削除ボタン | `'この X アカウントを削除'` |
| リンク追加ボタン | `'リンクを追加'` |
| リンク削除ボタン | `'このリンクを削除'` |
| 保存ボタン | `'保存、ダブルタップでこの名刺を保存'` |

タッチターゲット最低 44×44 を維持。削除アイコンは `IconButton` で OK。

---

## 10. 実装メモ (frontend向け)

- 既存 `capture_review_screen.dart` を v2 に拡張 (置き換えではなく上書き)
- `_xCtrls` / `_urlCtrls` は `StatefulWidget` の `initState` で生成、`dispose` で解放
- 行の動的増減は `setState` + `Column(children: ...)`、`ListView.builder` は不要 (件数は通常 1〜3)
- 保存時:
  ```dart
  final cleanedHandles = _xCtrls
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .map((s) => s.startsWith('@') ? s : '@$s')
      .toList(growable: false);
  ```
- `SaveCardUseCase` への入力は既存 `SaveCardInput.extraSnsLinks` を使い、`extractedData` 側は touched しない (ユーザーが編集後の最終値だけ渡す)
  - 既存実装が `extractedData.xHandles + extractedData.urls + extraSnsLinks` をマージしているため、ユーザー編集分を上書きするには `SaveCardInput` の構造を変更する必要あり。詳細は backend と要相談
