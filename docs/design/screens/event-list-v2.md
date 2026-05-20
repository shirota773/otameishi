# イベント一覧画面 v2 — 検索 + カレンダートグル

Version 2.0 — extends `event-list.md`. v1 のリスト/FAB 仕様はそのまま、本ドキュメントは **追加機能のみ** をスペック化する。

---

## 1. 追加機能

1. **AppBar 下に検索バー** — イベント名で部分一致フィルタ
2. **リスト/カレンダーのトグル** — 右上 SegmentedButton or IconButton で切替
3. **カレンダー表示** — 月ビュー、開催日にドット表示、日付タップで該当イベントの絞り込み

---

## 2. レイアウト (ASCII)

```
┌─────────────────────────────────┐
│ イベント               [📋][📅] │  ← AppBar 右に IconButton 2つ (リスト/カレンダー)
├─────────────────────────────────┤
│ 🔍 イベント名を検索              │  ← 検索 TextField (sticky)
├─────────────────────────────────┤
│                                 │
│  (v1 と同じリスト or カレンダー) │
│                                 │
│                          [+ FAB] │
└─────────────────────────────────┘
│ [カード][検索][イベント][設定]    │
└─────────────────────────────────┘
```

---

## 3. 検索バー

| 項目 | 値 |
|---|---|
| Widget | `TextField` with leading search icon |
| 高さ | 48dp |
| 背景 | `theme.colorScheme.surfaceContainerHighest` |
| 角丸 | `AppRadius.md` |
| 動作 | 入力中に **debounce 200ms** で `EventRepository.findAll` の結果を `name.contains(query, ignoreCase: true)` でフィルタ (件数少なくクライアント側 filter で十分) |
| クリアボタン | テキストあり時のみ右端に `Icons.close` |

カレンダー表示時も検索バーは表示し、絞り込まれたイベントのドットだけが残る。

---

## 4. リスト/カレンダートグル

| ボタン | 状態 | アイコン |
|---|---|---|
| リスト (デフォルト) | 選択時 ピンク塗り、非選択時 outline | `Icons.list` / `Icons.list_outlined` |
| カレンダー | 同上 | `Icons.calendar_month` / `Icons.calendar_month_outlined` |

実装は `ToggleButtons` または `SegmentedButton` (Material 3) どちらでも可。`AppBar.actions` 内に置く。状態は `StatefulWidget` 内 `bool _calendar = false` で保持。

---

## 5. カレンダー表示

ライブラリ: **`table_calendar: ^3.1.3`** を `pubspec.yaml` の dependencies に追加。

```dart
TableCalendar<Event>(
  firstDay: DateTime.utc(2020, 1, 1),
  lastDay: DateTime.utc(2030, 12, 31),
  focusedDay: _focused,
  selectedDayPredicate: (d) => isSameDay(d, _selected),
  eventLoader: (day) => events.where((e) =>
      e.startDate != null && isSameDay(e.startDate!, day)).toList(),
  onDaySelected: (s, f) => setState(() {
    _selected = s;
    _focused = f;
  }),
  calendarStyle: CalendarStyle(
    markerDecoration: BoxDecoration(
      color: theme.colorScheme.primary,
      shape: BoxShape.circle,
    ),
  ),
  headerStyle: const HeaderStyle(
    formatButtonVisible: false,
    titleCentered: true,
  ),
)
```

- 月ビューのみ (週ビュー・2週ビューは MVP 対象外)
- 日付タップ → 下部に該当日のイベント1〜N件をカード形式で表示 (タップで `/event/detail`)
- イベントが複数日にまたがる場合、開始日にのみドットを置く (MVP 範囲)
- 検索クエリで絞られたイベントのみがドットに反映される

---

## 6. 空状態

カレンダーは月遷移ができるので空文言は出さず、その月に1件もイベントがなければカレンダー下部に inline で「この月にはイベントがありません」を表示。

---

## 7. 実装メモ (frontend向け)

- 既存 `event_list_screen.dart` を拡張
- 検索バーは `Padding > TextField` でリスト/カレンダー両方の上に配置
- カレンダー部分は `_CalendarView` private widget に切り出す
- リスト部分は v1 の既存実装をそのまま保持
- FAB は **`Icons.add`** で `/event/edit` (新規作成) に push
