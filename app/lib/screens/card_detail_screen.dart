import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../core/providers.dart';
import '../models/event.dart';
import '../theme/app_theme.dart';

class CardDetailScreen extends ConsumerWidget {
  const CardDetailScreen({super.key, required this.cardId});

  final String cardId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final async = ref.watch(cardByIdProvider(cardId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('カード詳細'),
        actions: [
          Semantics(
            label: '編集',
            button: true,
            child: IconButton(
              icon: const Icon(Icons.edit_outlined),
              tooltip: '編集',
              onPressed: () async {
                final result = await Navigator.of(context)
                    .pushNamed('/card/edit', arguments: cardId);
                if (result == true && context.mounted) {
                  ref.invalidate(cardListProvider);
                  ref.invalidate(cardByIdProvider(cardId));
                }
              },
            ),
          ),
          Semantics(
            label: 'その他のメニュー',
            button: true,
            child: PopupMenuButton<_DetailMenuAction>(
              tooltip: 'その他',
              onSelected: (action) async {
                if (action == _DetailMenuAction.delete) {
                  await _confirmAndDelete(context, ref);
                }
              },
              itemBuilder: (_) => const [
                PopupMenuItem(
                  value: _DetailMenuAction.delete,
                  child: ListTile(
                    leading: Icon(Icons.delete_outline),
                    title: Text('削除'),
                    contentPadding: EdgeInsets.zero,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      body: async.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(child: Text('読み込み失敗: $e')),
        data: (card) {
          if (card == null) {
            return const Center(child: Text('カードが見つかりません'));
          }
          return ListView(
            padding: const EdgeInsets.all(AppSpacing.s4),
            children: [
              _CardImageCarousel(
                frontPath: card.imagePath,
                backPath: card.backImagePath,
              ),
              const SizedBox(height: AppSpacing.s6),
              if (card.displayName != null)
                Text(card.displayName!, style: theme.textTheme.headlineLarge),
              const SizedBox(height: AppSpacing.s2),
              Text(
                DateFormat.yMMMd('ja').format(card.createdAt.toLocal()),
                style: theme.textTheme.bodySmall,
              ),
              if (card.tags.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s5),
                Wrap(
                  spacing: AppSpacing.s2,
                  runSpacing: AppSpacing.s2,
                  children: card.tags
                      .map((t) => Chip(label: Text(t.name)))
                      .toList(growable: false),
                ),
              ],
              if (card.events.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s6),
                Text('イベント', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.s2),
                _EventChips(events: card.events),
              ],
              if (card.snsLinks.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s6),
                Text('リンク', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.s2),
                ...card.snsLinks.map(
                  (link) => _SnsLinkRow(link: link),
                ),
              ],
              if (card.memo != null && card.memo!.isNotEmpty) ...[
                const SizedBox(height: AppSpacing.s6),
                Text('メモ', style: theme.textTheme.titleLarge),
                const SizedBox(height: AppSpacing.s2),
                Text(card.memo!, style: theme.textTheme.bodyLarge),
              ],
            ],
          );
        },
      ),
    );
  }

  Future<void> _confirmAndDelete(BuildContext context, WidgetRef ref) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('このカードを削除しますか？'),
        content: const Text('削除すると元に戻せません。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirm != true || !context.mounted) return;

    try {
      final useCase = await ref.read(deleteCardUseCaseProvider.future);
      await useCase.execute(cardId);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('削除に失敗しました: $e')),
      );
      return;
    }

    if (!context.mounted) return;
    ref.invalidate(cardListProvider);
    Navigator.of(context).pop();
  }
}

enum _DetailMenuAction { delete }

// ---------------------------------------------------------------------------
// Sub-widgets
// ---------------------------------------------------------------------------

class _CardImageCarousel extends StatefulWidget {
  const _CardImageCarousel({required this.frontPath, required this.backPath});

  final String frontPath;
  final String? backPath;

  @override
  State<_CardImageCarousel> createState() => _CardImageCarouselState();
}

class _CardImageCarouselState extends State<_CardImageCarousel> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paths = <String>[
      widget.frontPath,
      if (widget.backPath != null) widget.backPath!,
    ];
    final labels = ['表面', if (widget.backPath != null) '裏面'];

    if (paths.length == 1) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.xl),
        child: AspectRatio(
          aspectRatio: 91 / 55,
          child: _CardImage(path: paths.first),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: AspectRatio(
            aspectRatio: 91 / 55,
            child: PageView(
              controller: _controller,
              onPageChanged: (i) => setState(() => _page = i),
              children: paths.map((p) => _CardImage(path: p)).toList(),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.s2),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(paths.length, (i) {
            final active = i == _page;
            return Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              child: GestureDetector(
                onTap: () => _controller.animateToPage(
                  i,
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeOut,
                ),
                child: Chip(
                  label: Text(labels[i]),
                  backgroundColor: active
                      ? theme.colorScheme.primaryContainer
                      : theme.colorScheme.surfaceContainerHighest,
                ),
              ),
            );
          }),
        ),
      ],
    );
  }
}

class _CardImage extends StatelessWidget {
  const _CardImage({required this.path});

  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    if (file.existsSync()) {
      return Image.file(file, fit: BoxFit.cover);
    }
    return Container(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      child: const Icon(Icons.image_not_supported_outlined, size: 64),
    );
  }
}

/// Renders a [Wrap] of tappable [ActionChip]s, one per linked [Event].
class _EventChips extends StatelessWidget {
  const _EventChips({required this.events});

  final List<Event> events;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: AppSpacing.s2,
      runSpacing: AppSpacing.s2,
      children: events.map((event) => _EventChip(event: event)).toList(growable: false),
    );
  }
}

class _EventChip extends StatelessWidget {
  const _EventChip({required this.event});

  final Event event;

  @override
  Widget build(BuildContext context) {
    final tooltip = event.date != null
        ? DateFormat.yMMMd('ja').format(event.date!.toLocal())
        : event.name;

    return Semantics(
      label: 'イベント: ${event.name}',
      button: true,
      child: ActionChip(
        avatar: const Icon(Icons.event, size: 18),
        label: Text(event.name),
        tooltip: tooltip,
        onPressed: () =>
            Navigator.of(context).pushNamed('/event', arguments: event.id),
      ),
    );
  }
}

class _SnsLinkRow extends ConsumerWidget {
  const _SnsLinkRow({required this.link});

  final String link;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final launcher = ref.watch(snsLauncherServiceProvider);
    final isHandle = link.startsWith('@');
    final isUrl = link.startsWith('http://') || link.startsWith('https://');
    final launchTarget = isHandle
        ? 'https://x.com/${link.substring(1)}'
        : (isUrl ? link : null);
    final iconData = isHandle
        ? Icons.alternate_email
        : (isUrl ? Icons.open_in_new : Icons.link);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s1),
      child: InkWell(
        onTap: launchTarget != null ? () => launcher.launch(launchTarget) : null,
        child: Row(
          children: [
            Icon(iconData,
                size: 20, color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: AppSpacing.s2),
            Expanded(
              child: Text(
                link,
                style: Theme.of(context).textTheme.bodyMedium,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
