# キャプチャレビュー画面 v4 — イベントマルチセレクト

Version 4.0 — extends `capture-review-v3.md`. v3 の全機能を維持しつつ、イベント選択を **1 件 (ラジオ)** から **複数件 (チェックボックス)** に変更。

---

## 変更点の概要

| v3 | v4 |
|----|----|
| `Event? selectedEvent` | `List<Event> selectedEvents` |
| 1 件のみ、chip 風コンテナ表示 | 複数件、Wrap チップ列 |
| `RadioListTile` ベースのシート | `CheckboxListTile` ベースのシート |
| 「選択を解除」でクリア | 「選択をクリア」でクリア (タグと統一) |
| シート pop 値: `_EventPickerResult` | シート pop 値: `Set<String>` (選択 ID) |

---

## 1. イベント欄レイアウト

### 1-1. 未選択時

```
イベント (任意)
┌─────────────────────────────────┐
│ [+ イベントを追加 ▼]            │  ← OutlinedButton.icon (key: select_event_button)
└─────────────────────────────────┘
```

### 1-2. 1 件以上選択時

```
イベント (任意)
┌─────────────────────────────────┐
│ [コミケ106 ×]  [にじフェス ×]   │  ← Chip ×N (Wrap, key: event_chip_{id})
│                                 │
│ [+ イベントを追加 ▼]            │  ← 常に表示 (タグ欄と同様)
└─────────────────────────────────┘
```

- `+ イベントを追加` ボタンは選択数に関わらず**常に表示** (追加のたびにシートを開ける)
- `×` タップで即座に該当イベントを解除 (`setState` のみ)

---

## 2. イベント選択ボトムシート (v4)

```
┌─────────────────────────────────┐
│ ─                                │
│ イベントを選択                   │
├─────────────────────────────────┤
│ 🔍 イベント名を検索               │  ← TextField (key: event_search_field)
├─────────────────────────────────┤
│ ☑ コミケ106  2024年12月29日       │  ← CheckboxListTile (key: event_picker_item_{id})
│ ☐ にじフェス2026  2026年3月15日   │
│ ☑ 蓮ノ空 4th LIVE  2026年8月23日  │
│ ☐ オフ会  日付未設定              │
├─────────────────────────────────┤
│ [+ 新しいイベントを作成]          │  ← 常に表示
│                                  │
│ [選択をクリア]  [完了 (2)]         │
└─────────────────────────────────┘
```

- 検索フィールドは名前の部分一致 (case-insensitive) でリストをフィルタ
- `CheckboxListTile`: `controlAffinity: ListTileControlAffinity.leading`
- 「+ 新しいイベントを作成」タップ → シートを `null` で pop し、`/event/edit` に push。戻り値の新規 ID をリポジトリで解決し `_selectedEvents` に追加
- 「選択をクリア」: シートを閉じず `_selectedIds = {}` にリセット
- 「完了 (N)」: `Set.unmodifiable(_selectedIds)` を pop。N = 0 のとき「完了」と表示
- フッターボタン: `minimumSize: const Size(44, 44)` を両ボタンに指定 (Row + Spacer と共存させるため `Size.fromHeight` は使わない)

---

## 3. 状態管理

```dart
// v4 state fields
final List<Event> _selectedEvents = [];

// open picker
Future<void> _openEventPicker() async {
  // ... load events, show sheet ...
  // result: Set<String>? of selected IDs
  setState(() {
    _selectedEvents
      ..clear()
      ..addAll(allEvents.where((e) => result.contains(e.id)));
  });
}

// save
eventIds: _selectedEvents.map((e) => e.id).toList(),
```

---

## 4. アクセシビリティ

| 要素 | Semantics |
|------|-----------|
| 追加ボタン | `Semantics(label: 'イベントを追加', button: true)` |
| Chip の削除アイコン | `Semantics(label: '{イベント名}を解除')` |
| 選択をクリアボタン | `Semantics(label: '選択をクリア', button: true)` |
| 完了ボタン | `Semantics(label: '完了', button: true)` |

タップターゲット最小 44×44 dp を全ボタン・アイコンで遵守。

---

## 5. キー一覧

| Widget | Key |
|--------|-----|
| 追加ボタン (0 件でも常に) | `Key('select_event_button')` |
| 各イベント Chip | `Key('event_chip_{eventId}')` |
| ピッカー内 CheckboxListTile | `Key('event_picker_item_{eventId}')` |
| 検索フィールド | `Key('event_search_field')` |

---

## 6. 変更なし

- タグ欄 (`_TagSection` / `_TagPickerSheet`) — 手を加えない
- `SaveCardInput.eventIds: List<String>` — `_selectedEvents.map((e) => e.id).toList()` で渡す
- カード詳細画面 / カード編集フロー — B2/B3 スコープ外
