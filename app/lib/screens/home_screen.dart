import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/providers.dart';
import '../services/service_models.dart';
import '../theme/app_theme.dart';
import '../widgets/card_gallery_tile.dart';
import '../widgets/card_tile.dart';
import '../widgets/empty_state.dart';

enum _EntryChoice { camera, gallery }

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asyncCards = ref.watch(cardListProvider);
    final viewMode = ref.watch(homeViewModeProvider);
    final isGallery = viewMode == HomeViewMode.gallery;

    return Scaffold(
      appBar: AppBar(
        title: const Text('カード'),
        actions: [
          _ViewToggleButton(isGallery: isGallery),
        ],
      ),
      body: asyncCards.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => Center(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s4),
            child: Text('読み込みに失敗しました\n$e', textAlign: TextAlign.center),
          ),
        ),
        data: (cards) {
          return RefreshIndicator(
            onRefresh: () => ref.refresh(cardListProvider.future),
            child: cards.isEmpty
                ? _EmptyScrollView()
                : isGallery
                    ? _GalleryGrid(cards: cards)
                    : _CardList(cards: cards),
          );
        },
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            key: const Key('home_search_fab'),
            heroTag: 'home_search_fab',
            onPressed: () => Navigator.of(context).pushNamed('/search'),
            tooltip: '検索',
            child: const Icon(Icons.search, size: 28),
          ),
          const SizedBox(height: AppSpacing.s3),
          FloatingActionButton(
            heroTag: 'home_add_fab',
            onPressed: () => _onAddPressed(context, ref),
            tooltip: '名刺を追加',
            child: const Icon(Icons.add, size: 32),
          ),
        ],
      ),
    );
  }

  Future<void> _onAddPressed(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<_EntryChoice>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => const _EntryChoiceSheet(),
    );
    if (choice == null || !context.mounted) return;

    final source = choice == _EntryChoice.camera
        ? ImageSource.camera
        : ImageSource.gallery;
    await _pickAndReview(context, ref, source);
  }

  Future<void> _pickAndReview(
    BuildContext context,
    WidgetRef ref,
    ImageSource source,
  ) async {
    final XFile? picked;
    try {
      picked = await ref.read(imagePickerProvider).pickImage(source: source);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像を取得できませんでした: $e')),
      );
      return;
    }
    if (picked == null) return;
    if (!context.mounted) return;

    final bytes = await picked.readAsBytes();
    final useCase = ref.read(captureCardUseCaseProvider);

    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _AnalyzingDialog(),
    );

    final CardDraft draft;
    try {
      draft = source == ImageSource.gallery
          ? await useCase.executeWithoutCorrection(bytes)
          : await useCase.execute(bytes);
    } finally {
      if (context.mounted) Navigator.of(context, rootNavigator: true).pop();
    }
    if (!context.mounted) return;

    await Navigator.of(context).pushNamed('/capture/review', arguments: draft);
  }
}

// ─── AppBar toggle ────────────────────────────────────────────────────────────

class _ViewToggleButton extends ConsumerWidget {
  const _ViewToggleButton({required this.isGallery});

  final bool isGallery;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Semantics(
      button: true,
      label: isGallery ? 'リスト表示' : 'ギャラリー表示',
      child: IconButton(
        icon: Icon(
          isGallery ? Icons.view_list_rounded : Icons.grid_view_rounded,
        ),
        tooltip: isGallery ? 'リスト表示' : 'ギャラリー表示',
        onPressed: () {
          ref.read(homeViewModeProvider.notifier).state = isGallery
              ? HomeViewMode.list
              : HomeViewMode.gallery;
        },
      ),
    );
  }
}

// ─── List body ────────────────────────────────────────────────────────────────

class _CardList extends StatelessWidget {
  const _CardList({required this.cards});

  final List<dynamic> cards;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.s4),
      itemCount: cards.length,
      separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.s2),
      itemBuilder: (_, i) => CardTile(
        card: cards[i],
        onTap: () => Navigator.of(context).pushNamed(
          '/card',
          arguments: cards[i].id,
        ),
      ),
    );
  }
}

// ─── Gallery body ─────────────────────────────────────────────────────────────

class _GalleryGrid extends StatelessWidget {
  const _GalleryGrid({required this.cards});

  final List<dynamic> cards;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.s4),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        childAspectRatio: 91 / 55,
        mainAxisSpacing: AppSpacing.s2,
        crossAxisSpacing: AppSpacing.s2,
      ),
      itemCount: cards.length,
      itemBuilder: (_, i) => CardGalleryTile(
        card: cards[i],
        onTap: () => Navigator.of(context).pushNamed(
          '/card',
          arguments: cards[i].id,
        ),
      ),
    );
  }
}

// ─── Empty state ──────────────────────────────────────────────────────────────

class _EmptyScrollView extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: const [
        SizedBox(height: 200),
        EmptyState(
          icon: Icons.style_outlined,
          message: 'まだ名刺がありません',
          hint: '右下の＋から取り込みを始めましょう',
        ),
      ],
    );
  }
}

// ─── Entry bottom sheet ───────────────────────────────────────────────────────

class _EntryChoiceSheet extends ConsumerWidget {
  const _EntryChoiceSheet();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                  AppSpacing.s4, AppSpacing.s2, AppSpacing.s4, AppSpacing.s2),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '追加方法',
                  style: theme.textTheme.titleMedium,
                ),
              ),
            ),
            _ChoiceTile(
              icon: Icons.photo_camera_outlined,
              title: '撮影',
              subtitle: 'カメラアプリで撮影 (端末の標準アプリを使用)',
              semantics: '撮影で名刺を追加',
              onTap: () => Navigator.of(context).pop(_EntryChoice.camera),
            ),
            _ChoiceTile(
              icon: Icons.image_outlined,
              title: '画像から取り込み',
              subtitle: '保存済みの画像を選択して読み取り',
              semantics: '画像から取り込んで名刺を追加',
              onTap: () => Navigator.of(context).pop(_EntryChoice.gallery),
            ),
          ],
        ),
      ),
    );
  }
}

class _ChoiceTile extends StatelessWidget {
  const _ChoiceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.semantics,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final String semantics;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      button: true,
      label: semantics,
      child: ListTile(
        leading: Icon(icon, size: 28, color: theme.colorScheme.primary),
        title: Text(title, style: theme.textTheme.titleMedium),
        subtitle: Text(subtitle, style: theme.textTheme.bodySmall),
        onTap: onTap,
      ),
    );
  }
}

class _AnalyzingDialog extends StatelessWidget {
  const _AnalyzingDialog();

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Theme.of(context).colorScheme.surface,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.s6,
            vertical: AppSpacing.s5,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
              const SizedBox(width: AppSpacing.s4),
              Text('読み取り中…', style: Theme.of(context).textTheme.titleSmall),
            ],
          ),
        ),
      ),
    );
  }
}
