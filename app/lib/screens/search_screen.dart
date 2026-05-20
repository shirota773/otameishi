import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/providers.dart';
import '../models/business_card.dart';
import '../models/event.dart';
import '../models/tag.dart';
import '../theme/app_theme.dart';
import '../widgets/card_tile.dart';
import '../widgets/empty_state.dart';
import '../widgets/filter_chip_row.dart';

// ─── Screen-local providers ───────────────────────────────────────────────────

final _queryProvider = StateProvider.autoDispose<String>((_) => '');

final _resultsProvider =
    FutureProvider.autoDispose<List<BusinessCard>>((ref) async {
  final query = ref.watch(_queryProvider);
  final filters = ref.watch(searchFiltersProvider);

  // Both empty → nothing to search.
  if (query.trim().isEmpty && filters.isEmpty) return const [];

  final useCase = await ref.watch(searchCardsUseCaseProvider.future);
  return useCase.execute(query, filters: filters);
});

final _allEventsProvider = FutureProvider.autoDispose<List<Event>>((ref) async {
  final repo = await ref.watch(eventRepositoryProvider.future);
  return repo.findAll();
});

final _allTagsProvider = FutureProvider.autoDispose<List<Tag>>((ref) async {
  final repo = await ref.watch(tagRepositoryProvider.future);
  return repo.findAll();
});

// ─── Screen ───────────────────────────────────────────────────────────────────

class SearchScreen extends ConsumerStatefulWidget {
  const SearchScreen({super.key});

  @override
  ConsumerState<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends ConsumerState<SearchScreen> {
  Timer? _debounce;
  final _controller = TextEditingController();

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    super.dispose();
  }

  void _onQueryChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 150), () {
      ref.read(_queryProvider.notifier).state = value;
    });
  }

  @override
  Widget build(BuildContext context) {
    final results = ref.watch(_resultsProvider);
    final query = ref.watch(_queryProvider);
    final filters = ref.watch(searchFiltersProvider);
    final eventsAsync = ref.watch(_allEventsProvider);
    final tagsAsync = ref.watch(_allTagsProvider);

    final events = eventsAsync.valueOrNull ?? const [];
    final tags = tagsAsync.valueOrNull ?? const [];

    final isIdle = query.trim().isEmpty && filters.isEmpty;

    return Scaffold(
      appBar: AppBar(title: const Text('検索')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s4,
              AppSpacing.s4,
              0,
            ),
            child: Semantics(
              label: '検索キーワード入力',
              textField: true,
              child: TextField(
                controller: _controller,
                autofocus: true,
                decoration: const InputDecoration(
                  prefixIcon: Icon(Icons.search),
                  hintText: '名前・タグ・メモ・イベント',
                ),
                onChanged: _onQueryChanged,
              ),
            ),
          ),
          FilterChipRow(
            filters: filters,
            events: events,
            tags: tags,
            onFiltersChanged: (updated) {
              ref.read(searchFiltersProvider.notifier).state = updated;
            },
          ),
          Expanded(
            child: isIdle
                ? const EmptyState(
                    icon: Icons.search,
                    message: '検索キーワードを入力',
                    hint: '名前・タグ・メモ・イベント名、またはフィルタで絞り込めます',
                  )
                : results.when(
                    loading: () =>
                        const Center(child: CircularProgressIndicator()),
                    error: (e, _) => Center(child: Text('エラー: $e')),
                    data: (cards) {
                      if (cards.isEmpty) {
                        return const EmptyState(
                          icon: Icons.search_off,
                          message: '一致するカードはありません',
                        );
                      }
                      return ListView.separated(
                        padding: const EdgeInsets.all(AppSpacing.s4),
                        itemCount: cards.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSpacing.s2),
                        itemBuilder: (_, i) => CardTile(
                          card: cards[i],
                          onTap: () => Navigator.of(context)
                              .pushNamed('/card', arguments: cards[i].id),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
