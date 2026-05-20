import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/providers.dart';
import '../models/business_card.dart';
import '../router/app_router.dart';
import '../services/service_models.dart';
import '../theme/accent_colors.dart';
import '../theme/app_theme.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('設定')),
      body: ListView(
        padding: const EdgeInsets.all(AppSpacing.s4),
        children: [
          _MyCardSection(),
          const Divider(),
          _ThemeModeSection(theme: theme),
          const SizedBox(height: AppSpacing.s2),
          _AccentColorSection(theme: theme),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.label_outline),
            title: const Text('タグ管理'),
            onTap: () => Navigator.of(context).pushNamed('/tags'),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.shield_outlined),
            title: const Text('プライバシー'),
            subtitle: Text(
              'すべての名刺データは端末のみに保存されます。\nクラウド同期や外部送信は行いません。',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('バージョン'),
            subtitle: const Text('1.0.0 (MVP)'),
          ),
        ],
      ),
    );
  }
}

// ─── マイカード section ──────────────────────────────────────────────────────

class _MyCardSection extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final asyncMyCard = ref.watch(myCardProvider);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.s4,
              bottom: AppSpacing.s2,
            ),
            child: Text('マイカード', style: theme.textTheme.titleLarge),
          ),
          asyncMyCard.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.s4),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(AppSpacing.s4),
              child: Text(
                'マイカードの読み込みに失敗しました',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.error),
              ),
            ),
            data: (myCard) => myCard == null
                ? _MyCardEmpty(onRegister: () => _startRegistration(context, ref))
                : _MyCardRegistered(
                    card: myCard,
                    onEdit: () => _editMyCard(context, ref, myCard.id),
                    onClear: () => _confirmClearMyCard(context, ref),
                  ),
          ),
        ],
      ),
    );
  }

  Future<void> _startRegistration(BuildContext context, WidgetRef ref) async {
    final choice = await showModalBottomSheet<_RegistrationChoice>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => const _MyCardChoiceSheet(),
    );
    if (choice == null || !context.mounted) return;

    final source = choice == _RegistrationChoice.camera
        ? ImageSource.camera
        : ImageSource.gallery;

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
    if (picked == null || !context.mounted) return;

    final bytes = await picked.readAsBytes();
    final useCase = ref.read(captureCardUseCaseProvider);
    final CardDraft draft;
    try {
      draft = await useCase.execute(bytes);
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('画像の処理に失敗しました: $e')),
      );
      return;
    }
    if (!context.mounted) return;

    await Navigator.of(context).pushNamed(
      '/capture/review',
      arguments: CaptureReviewArgs(draft: draft, isMyCard: true),
    );
  }

  Future<void> _editMyCard(
    BuildContext context,
    WidgetRef ref,
    String cardId,
  ) async {
    final result = await Navigator.of(context)
        .pushNamed('/card/edit', arguments: cardId);
    if (result == true) {
      ref.invalidate(myCardProvider);
    }
  }

  Future<void> _confirmClearMyCard(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('マイカードの登録を解除しますか?'),
        content: const Text(
          'カードのデータはそのまま残ります。マイカードとしての登録のみ解除されます。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            key: const Key('confirm_clear_my_card_button'),
            onPressed: () => Navigator.of(ctx).pop(true),
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            child: const Text('解除'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final repo = await ref.read(cardRepositoryProvider.future);
    await repo.clearMyCard();
    ref.invalidate(myCardProvider);
  }
}

// ─── Empty state widget ───────────────────────────────────────────────────────

class _MyCardEmpty extends StatelessWidget {
  const _MyCardEmpty({required this.onRegister});

  final VoidCallback onRegister;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      child: OutlinedCard(
        child: InkWell(
          key: const Key('register_my_card_button'),
          onTap: onRegister,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.s5),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.add_card, size: 28),
                const SizedBox(width: AppSpacing.s3),
                Text(
                  '自分の名刺を登録',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ─── Registered state widget ──────────────────────────────────────────────────

class _MyCardRegistered extends StatelessWidget {
  const _MyCardRegistered({
    required this.card,
    required this.onEdit,
    required this.onClear,
  });

  final BusinessCard card;
  final VoidCallback onEdit;
  final VoidCallback onClear;

  static const _thumbSize = 80.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _CardThumbnail(imagePath: card.imagePath, size: _thumbSize),
          const SizedBox(width: AppSpacing.s3),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  card.displayName ?? '名前未設定',
                  style: theme.textTheme.titleMedium,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (card.memo != null && card.memo!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.s1),
                  Text(
                    card.memo!,
                    style: theme.textTheme.bodySmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: AppSpacing.s2),
                Row(
                  children: [
                    Semantics(
                      label: 'マイカードを編集',
                      button: true,
                      child: OutlinedButton(
                        key: const Key('edit_my_card_button'),
                        onPressed: onEdit,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s3,
                            vertical: AppSpacing.s1,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                        ),
                        child: const Text('編集'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.s2),
                    Semantics(
                      label: 'マイカードの登録を解除',
                      button: true,
                      child: OutlinedButton(
                        key: const Key('clear_my_card_button'),
                        onPressed: onClear,
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size(44, 44),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.s3,
                            vertical: AppSpacing.s1,
                          ),
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          foregroundColor: theme.colorScheme.error,
                        ),
                        child: const Text('解除'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Thumbnail ────────────────────────────────────────────────────────────────

class _CardThumbnail extends StatelessWidget {
  const _CardThumbnail({required this.imagePath, required this.size});

  final String imagePath;
  final double size;

  @override
  Widget build(BuildContext context) {
    final file = File(imagePath);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: SizedBox.square(
        dimension: size,
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : ColoredBox(
                color: Theme.of(context).colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.image_outlined, size: 32),
                ),
              ),
      ),
    );
  }
}

// ─── Registration choice sheet ────────────────────────────────────────────────

enum _RegistrationChoice { camera, gallery }

class _MyCardChoiceSheet extends StatelessWidget {
  const _MyCardChoiceSheet();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.s2),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.s4,
                AppSpacing.s2,
                AppSpacing.s4,
                AppSpacing.s2,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text('マイカードの取り込み方法', style: theme.textTheme.titleMedium),
              ),
            ),
            Semantics(
              button: true,
              label: '撮影でマイカードを登録',
              child: ListTile(
                leading: Icon(
                  Icons.photo_camera_outlined,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                title: Text('撮影', style: theme.textTheme.titleMedium),
                subtitle: Text(
                  'カメラアプリで撮影',
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () =>
                    Navigator.of(context).pop(_RegistrationChoice.camera),
              ),
            ),
            Semantics(
              button: true,
              label: '画像からマイカードを登録',
              child: ListTile(
                leading: Icon(
                  Icons.image_outlined,
                  size: 28,
                  color: theme.colorScheme.primary,
                ),
                title: Text('画像から取り込み', style: theme.textTheme.titleMedium),
                subtitle: Text(
                  '保存済みの画像を選択',
                  style: theme.textTheme.bodySmall,
                ),
                onTap: () =>
                    Navigator.of(context).pop(_RegistrationChoice.gallery),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── OutlinedCard helper ──────────────────────────────────────────────────────

/// A Card with an outline border, used for the empty my-card placeholder.
class OutlinedCard extends StatelessWidget {
  const OutlinedCard({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
        side: BorderSide(
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
      ),
      child: child,
    );
  }
}

// ─── 表示モード section ──────────────────────────────────────────────────────

class _ThemeModeSection extends ConsumerWidget {
  const _ThemeModeSection({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(themeModeProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.s4,
              bottom: AppSpacing.s2,
            ),
            child: Text('表示モード', style: theme.textTheme.titleLarge),
          ),
          Semantics(
            label: '表示モード選択',
            child: SegmentedButton<ThemeMode>(
              segments: const [
                ButtonSegment(
                  value: ThemeMode.system,
                  label: Text('システム'),
                  icon: Icon(Icons.brightness_auto),
                ),
                ButtonSegment(
                  value: ThemeMode.light,
                  label: Text('ライト'),
                  icon: Icon(Icons.light_mode),
                ),
                ButtonSegment(
                  value: ThemeMode.dark,
                  label: Text('ダーク'),
                  icon: Icon(Icons.dark_mode),
                ),
              ],
              selected: {current},
              onSelectionChanged: (Set<ThemeMode> selected) {
                ref
                    .read(themeModeProvider.notifier)
                    .setMode(selected.first);
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ─── アクセントカラー section ─────────────────────────────────────────────────

class _AccentColorSection extends ConsumerWidget {
  const _AccentColorSection({required this.theme});

  final ThemeData theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final selectedIndex = ref.watch(accentColorIndexProvider);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.s3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(
              left: AppSpacing.s4,
              bottom: AppSpacing.s2,
            ),
            child: Text('アクセントカラー', style: theme.textTheme.titleLarge),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
            child: Wrap(
              spacing: AppSpacing.s3,
              runSpacing: AppSpacing.s3,
              children: List.generate(kAccentColors.length, (i) {
                return _ColorSwatch(
                  color: kAccentColors[i],
                  label: kAccentColorLabels[i],
                  isSelected: i == selectedIndex,
                  onTap: () =>
                      ref.read(accentColorIndexProvider.notifier).setIndex(i),
                );
              }),
            ),
          ),
        ],
      ),
    );
  }
}

// ─── _ColorSwatch ────────────────────────────────────────────────────────────

class _ColorSwatch extends StatelessWidget {
  const _ColorSwatch({
    required this.color,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  final Color color;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  static const _size = 44.0;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$label${isSelected ? '（選択中）' : ''}',
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: _size,
          height: _size,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: isSelected
                ? Border.all(
                    color: Theme.of(context).colorScheme.onSurface,
                    width: 2.5,
                  )
                : null,
          ),
          child: isSelected
              ? const Icon(Icons.check, color: Colors.white, size: 22)
              : null,
        ),
      ),
    );
  }
}
