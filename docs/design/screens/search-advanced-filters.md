# 検索画面 詳細フィルタ追加

Version 2.0 — extends `search-flow.md` and the existing search screen.

---

## 1. 目的

検索ボックスのキーワード検索だけでなく、**イベント** や **タグ** で絞り込めるようにする。複数選択可。

---

## 2. レイアウト追加部分 (ASCII)

```
┌─────────────────────────────────┐
│ 検索                            │
├─────────────────────────────────┤
│ 🔍 名前・タグ・メモ・イベント     │
├─────────────────────────────────┤
│ [すべて] [イベント 2 ▼] [タグ 3 ▼] │  ← フィルタチップ行 (横スクロール)
├─────────────────────────────────┤
│ (結果リスト or 空状態)            │
└─────────────────────────────────┘
```

検索フィールドのすぐ下に **フィルタチップ行** を sticky で配置:
- 「すべて」 — タップで全フィルタ解除 (= プレーン検索に戻る)
- 「イベント N」 — タップでイベント選択ボトムシート
- 「タグ N」 — タップでタグ選択ボトムシート

N はそれぞれの選択件数 (0 件のときは数字省略、chip は非アクティブ枠線)。

---

## 3. ボトムシート

両方とも同じ構造:

```
┌─────────────────────────────────┐
│ ─                                │  ← ハンドル
│ イベントで絞り込み                │  ← タイトル
├─────────────────────────────────┤
│ ☐ コミケ106                       │
│ ☑ にじフェス2026                  │
│ ☑ 蓮ノ空 4th LIVE                 │
│ ☐ オフ会                          │
│                                  │
│ [選択をクリア]  [適用 (3件)]      │
└─────────────────────────────────┘
```

- リスト: `CheckboxListTile` × 全候補
- 件数が多い場合は内部 `ListView` で縦スクロール
- フッター: 左に「クリア」(text button)、右に「適用」(ElevatedButton)
- 「適用」タップ → ボトムシート閉じ + 親に選択 ID リスト返却

---

## 4. データフロー

```dart
final _searchFiltersProvider = StateProvider<_SearchFilters>(
  (_) => const _SearchFilters(),
);

class _SearchFilters {
  const _SearchFilters({this.eventIds = const {}, this.tagIds = const {}});
  final Set<String> eventIds;
  final Set<String> tagIds;
}
```

検索クエリと filters の両方を `searchCardsUseCase` に渡す。`SearchRepository.search` 側に `{Set<String>? eventIds, Set<String>? tagIds}` のオプション引数を追加 (db agent 範囲)。

---

## 5. 空フィルタの扱い

| クエリ | eventIds | tagIds | 挙動 |
|---|---|---|---|
| "" | ∅ | ∅ | 現状 (空状態を表示) |
| "" | ∅ | not ∅ | タグで絞り込みされた全件を表示 |
| "" | not ∅ | ∅ | イベントで絞り込みされた全件 |
| not "" | … | … | キーワード AND フィルタ |

つまり「キーワード必須」を外す。フィルタだけでも検索が成立する。

---

## 6. 実装メモ

- ファイル: `lib/screens/search_screen.dart` (既存改修) + NEW `lib/widgets/filter_chip_row.dart` (任意で抽出)
- フィルタチップ: `FilterChip` (Material 3)
- ボトムシート: `showModalBottomSheet`、内部は `StatefulBuilder` または mini `ConsumerStatefulWidget`
- 適用時に親に返す値: `Set<String>?` (null = キャンセル)
- 検索のデバウンスは既存ロジックを流用
