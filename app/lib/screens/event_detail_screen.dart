import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/providers.dart';
import '../models/business_card.dart';
import '../models/event.dart';
import '../theme/app_theme.dart';
import '../widgets/card_tile.dart';
import '../widgets/empty_state.dart';

class _EventDetailData {
  final Event event;
  final List<BusinessCard> cards;
  const _EventDetailData(this.event, this.cards);
}

final _eventDetailProvider = FutureProvider.autoDispose
    .family<_EventDetailData?, String>((ref, id) async {
  final eventRepo = await ref.watch(eventRepositoryProvider.future);
  final cardRepo = await ref.watch(cardRepositoryProvider.future);
  final event = await eventRepo.findById(id);
  if (event == null) return null;
  final cards = await cardRepo.findByEvent(id);
  return _EventDetailData(event, cards);
});

class EventDetailScreen extends ConsumerWidget {
  const EventDetailScreen({super.key, required this.eventId});

  final String eventId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(_eventDetailProvider(eventId));
    final dateFmt = DateFormat.yMMMd('ja');

    return Scaffold(
      appBar: AppBar(
        title: const Text('イベント詳細'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: '編集',
            onPressed: () async {
              final result = await Navigator.of(context)
                  .pushNamed('/event/edit', arguments: eventId);
              if (result != null) {
                ref.invalidate(_eventDetailProvider(eventId));
                ref.invalidate(eventListProvider);
              }
            },
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('エラー: $e')),
        data: (data) {
          if (data == null) {
            return const Center(child: Text('イベントが見つかりません'));
          }
          final event = data.event;
          final cards = data.cards;
          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: const EdgeInsets.all(AppSpacing.s4),
                sliver: SliverList.list(children: [
                  Text(event.name, style: theme.textTheme.headlineLarge),
                  if (event.date != null) ...[
                    const SizedBox(height: AppSpacing.s1),
                    Text(dateFmt.format(event.date!),
                        style: theme.textTheme.bodySmall),
                  ],
                  if (event.memo != null) ...[
                    const SizedBox(height: AppSpacing.s4),
                    Text(event.memo!, style: theme.textTheme.bodyMedium),
                  ],
                  const SizedBox(height: AppSpacing.s6),
                  Text('交換した名刺 (${cards.length})',
                      style: theme.textTheme.titleLarge),
                  const SizedBox(height: AppSpacing.s2),
                ]),
              ),
              if (cards.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.style_outlined,
                    message: 'このイベントの名刺はまだありません',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
                  sliver: SliverList.separated(
                    itemCount: cards.length,
                    separatorBuilder: (_, _) =>
                        const SizedBox(height: AppSpacing.s2),
                    itemBuilder: (_, i) => CardTile(
                      card: cards[i],
                      onTap: () => Navigator.of(context)
                          .pushNamed('/card', arguments: cards[i].id),
                    ),
                  ),
                ),
              const SliverPadding(padding: EdgeInsets.only(bottom: AppSpacing.s8)),
            ],
          );
        },
      ),
    );
  }
}
