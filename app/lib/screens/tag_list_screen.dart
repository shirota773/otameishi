import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../core/providers.dart';
import '../db/repositories/tag_repository.dart';
import '../models/tag.dart';
import '../theme/app_theme.dart';

const _kMaxTagLength = 20;
const _kTagRowHeight = 56.0;
const _kDeleteTargetSize = 44.0;
const _uuid = Uuid();

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------

class TagListScreen extends ConsumerStatefulWidget {
  const TagListScreen({super.key});

  @override
  ConsumerState<TagListScreen> createState() => _TagListScreenState();
}

class _TagListScreenState extends ConsumerState<TagListScreen> {
  final _controller = TextEditingController();
  final _focusNode = FocusNode();

  String _input = '';

  @override
  void dispose() {
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  // ── Validation ─────────────────────────────────────────────────────────────

  bool _isDuplicate(List<TagWithCount> tags) {
    if (_input.isEmpty) return false;
    return tags.any(
      (t) => t.tag.name.toLowerCase() == _input.toLowerCase(),
    );
  }

  bool _canAdd(List<TagWithCount> tags) =>
      _input.isNotEmpty && !_isDuplicate(tags);

  // ── Actions ────────────────────────────────────────────────────────────────

  Future<void> _addTag(TagRepository repo) async {
    final name = _input.trim();
    if (name.isEmpty) return;
    final tag = Tag(id: _uuid.v4(), name: name);
    await repo.insert(tag);
    _controller.clear();
    setState(() => _input = '');
    ref.invalidate(tagListWithCountsProvider);
  }

  Future<void> _deleteTag(TagWithCount item, TagRepository repo) async {
    final confirmed = await _showDeleteDialog(item);
    if (!confirmed) return;
    await repo.delete(item.tag.id);
    ref.invalidate(tagListWithCountsProvider);
  }

  Future<bool> _showDeleteDialog(TagWithCount item) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => _DeleteConfirmDialog(
        tagName: item.tag.name,
        cardCount: item.cardCount,
      ),
    );
    return result ?? false;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(tagListWithCountsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('タグ管理'),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAddForm(async),
          Expanded(
            child: async.when(
              loading: () => const _TagListSkeleton(),
              error: (e, _) => Center(child: Text('エラー: $e')),
              data: (tags) => tags.isEmpty
                  ? const _TagEmptyState()
                  : _TagListView(
                      tags: tags,
                      onDelete: (item) async {
                        final repo =
                            await ref.read(tagRepositoryProvider.future);
                        await _deleteTag(item, repo);
                      },
                    ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAddForm(AsyncValue<List<TagWithCount>> async) {
    return async.when(
      loading: () => _AddForm(
        controller: _controller,
        focusNode: _focusNode,
        input: _input,
        isDuplicate: false,
        canAdd: false,
        onChanged: (v) => setState(() => _input = v),
        onAdd: null,
      ),
      error: (e, _) => _AddForm(
        controller: _controller,
        focusNode: _focusNode,
        input: _input,
        isDuplicate: false,
        canAdd: false,
        onChanged: (v) => setState(() => _input = v),
        onAdd: null,
      ),
      data: (tags) {
        final isDup = _isDuplicate(tags);
        final canAdd = _canAdd(tags);
        return _AddForm(
          controller: _controller,
          focusNode: _focusNode,
          input: _input,
          isDuplicate: isDup,
          canAdd: canAdd,
          onChanged: (v) => setState(() => _input = v),
          onAdd: canAdd
              ? () async {
                  final repo = await ref.read(tagRepositoryProvider.future);
                  await _addTag(repo);
                }
              : null,
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Add Form
// ---------------------------------------------------------------------------

class _AddForm extends StatelessWidget {
  const _AddForm({
    required this.controller,
    required this.focusNode,
    required this.input,
    required this.isDuplicate,
    required this.canAdd,
    required this.onChanged,
    required this.onAdd,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String input;
  final bool isDuplicate;
  final bool canAdd;
  final ValueChanged<String> onChanged;
  final VoidCallback? onAdd;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final fillColor =
        isDark ? AppColors.surfaceTertiaryDark : AppColors.surfaceTertiaryLight;
    final errorColor = theme.colorScheme.error;
    final brandPrimary = theme.colorScheme.primary;
    final tertiaryText =
        isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.s4,
        AppSpacing.s4,
        AppSpacing.s4,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(
              color: fillColor,
              borderRadius: BorderRadius.circular(AppRadius.sm),
              border: isDuplicate
                  ? Border.all(color: errorColor, width: 1.5)
                  : null,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    label: '新しいタグ名を入力',
                    child: TextField(
                      controller: controller,
                      focusNode: focusNode,
                      decoration: const InputDecoration(
                        hintText: '新しいタグ名',
                        filled: false,
                        border: InputBorder.none,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: AppSpacing.s4,
                          vertical: AppSpacing.s3,
                        ),
                      ),
                      maxLength: _kMaxTagLength,
                      maxLengthEnforcement: MaxLengthEnforcement.enforced,
                      buildCounter: (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) =>
                          null,
                      onChanged: onChanged,
                      onSubmitted: canAdd ? (_) => onAdd?.call() : null,
                      textInputAction: TextInputAction.done,
                    ),
                  ),
                ),
                Semantics(
                  label: '追加、ダブルタップでタグを追加',
                  child: SizedBox(
                    height: _kDeleteTargetSize,
                    child: TextButton(
                      onPressed: onAdd,
                      style: TextButton.styleFrom(
                        foregroundColor: brandPrimary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.s4,
                        ),
                      ),
                      child: const Text(
                        '追加',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.s1),
          if (isDuplicate)
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.s1),
              child: Text(
                '同じ名前のタグがすでにあります',
                style: theme.textTheme.bodySmall?.copyWith(color: errorColor),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.only(left: AppSpacing.s1),
              child: Text(
                '${input.length} / $_kMaxTagLength',
                style: theme.textTheme.bodySmall
                    ?.copyWith(color: tertiaryText),
              ),
            ),
          const SizedBox(height: AppSpacing.s3),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Tag list
// ---------------------------------------------------------------------------

class _TagListView extends StatelessWidget {
  const _TagListView({required this.tags, required this.onDelete});

  final List<TagWithCount> tags;
  final Future<void> Function(TagWithCount) onDelete;

  @override
  Widget build(BuildContext context) {
    // left margin = space.4 + 24dp icon + space.3
    const dividerIndent = AppSpacing.s4 + 24.0 + AppSpacing.s3;

    return ListView.separated(
      itemCount: tags.length,
      separatorBuilder: (_, i) => const _TagDivider(leftIndent: dividerIndent),
      itemBuilder: (_, i) => _TagRow(
        item: tags[i],
        onDelete: () => onDelete(tags[i]),
      ),
    );
  }
}

class _TagRow extends StatelessWidget {
  const _TagRow({required this.item, required this.onDelete});

  final TagWithCount item;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tertiaryText =
        isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;
    final brandSecondary = theme.colorScheme.secondary;

    return Semantics(
      label: 'タグ ${item.tag.name}、${item.cardCount}枚に使用中',
      child: SizedBox(
        height: _kTagRowHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
          child: Row(
            children: [
              Icon(Icons.label, size: 24, color: brandSecondary),
              const SizedBox(width: AppSpacing.s3),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.tag.name,
                      style: theme.textTheme.bodyLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${item.cardCount}枚に使用中',
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: tertiaryText),
                    ),
                  ],
                ),
              ),
              Semantics(
                label: '${item.tag.name}を削除、ダブルタップで削除確認',
                button: true,
                child: SizedBox(
                  key: ValueKey('delete_btn_${item.tag.id}'),
                  width: _kDeleteTargetSize,
                  height: _kDeleteTargetSize,
                  child: IconButton(
                    padding: EdgeInsets.zero,
                    iconSize: 24,
                    color: tertiaryText,
                    icon: const Icon(Icons.delete_outline),
                    onPressed: onDelete,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagDivider extends StatelessWidget {
  const _TagDivider({required this.leftIndent});

  final double leftIndent;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return Divider(
      height: 1,
      thickness: 1,
      indent: leftIndent,
      color: isDark
          ? AppColors.surfaceTertiaryDark
          : AppColors.surfaceTertiaryLight,
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------

class _TagEmptyState extends StatelessWidget {
  const _TagEmptyState();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final tertiaryText =
        isDark ? AppColors.textTertiaryDark : AppColors.textTertiaryLight;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.s8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.label_outline, size: 64, color: tertiaryText),
            const SizedBox(height: AppSpacing.s4),
            Text(
              'タグがありません',
              textAlign: TextAlign.center,
              style: theme.textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.s2),
            Text(
              '名刺を保存するときにタグを追加できます',
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: isDark
                    ? AppColors.textSecondaryDark
                    : AppColors.textSecondaryLight,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Skeleton loading (3 placeholder rows)
// ---------------------------------------------------------------------------

class _TagListSkeleton extends StatelessWidget {
  const _TagListSkeleton();

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('tag_list_skeleton'),
      children: List.generate(3, (_) => const _SkeletonRow()),
    );
  }
}

class _SkeletonRow extends StatelessWidget {
  const _SkeletonRow();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final shimmer =
        isDark ? AppColors.surfaceTertiaryDark : AppColors.surfaceTertiaryLight;

    return SizedBox(
      height: _kTagRowHeight,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.s4,
          vertical: AppSpacing.s3,
        ),
        child: Row(
          children: [
            _ShimmerBox(width: 24, height: 24, color: shimmer, radius: 4),
            const SizedBox(width: AppSpacing.s3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _ShimmerBox(width: 120, height: 14, color: shimmer, radius: 4),
                  const SizedBox(height: 4),
                  _ShimmerBox(width: 72, height: 11, color: shimmer, radius: 4),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShimmerBox extends StatelessWidget {
  const _ShimmerBox({
    required this.width,
    required this.height,
    required this.color,
    required this.radius,
  });

  final double width;
  final double height;
  final Color color;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Delete confirm dialog
// ---------------------------------------------------------------------------

class _DeleteConfirmDialog extends StatelessWidget {
  const _DeleteConfirmDialog({
    required this.tagName,
    required this.cardCount,
  });

  final String tagName;
  final int cardCount;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return AlertDialog(
      title: Text('「$tagName」を削除しますか？'),
      content: cardCount > 0
          ? Text(
              'このタグは$cardCount枚から削除されます。',
              style: theme.textTheme.bodyMedium,
            )
          : null,
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('キャンセル'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          style: TextButton.styleFrom(
            foregroundColor: theme.colorScheme.error,
          ),
          child: const Text('削除'),
        ),
      ],
    );
  }
}
