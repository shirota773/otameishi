import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:image_picker/image_picker.dart';

import '../core/providers.dart';
import '../models/business_card.dart';
import '../models/event.dart';
import '../models/tag.dart';
import '../theme/app_theme.dart';
import '../usecases/update_card_usecase.dart';
import '../widgets/event_picker_sheet.dart';
import '../widgets/tag_picker_sheet.dart';

/// Screen for editing all user-editable fields of an existing [BusinessCard].
///
/// Loaded via `/card/edit` with [cardId] as the route argument.  Pops with
/// `true` on a successful save, or `null` when the user cancels.
class CardEditScreen extends ConsumerStatefulWidget {
  const CardEditScreen({super.key, required this.cardId});

  final String cardId;

  @override
  ConsumerState<CardEditScreen> createState() => _CardEditScreenState();
}

class _CardEditScreenState extends ConsumerState<CardEditScreen> {
  late final TextEditingController _name;
  late final TextEditingController _memo;

  final List<TextEditingController> _xCtrls = [];
  final List<TextEditingController> _urlCtrls = [];

  final List<Tag> _selectedTags = [];
  final List<String> _pendingNewTags = [];
  final List<Event> _selectedEvents = [];

  String? _imagePath;
  bool _pickingFrontImage = false;

  String? _backImagePath;
  String? _originalBackImagePath;
  bool _pickingBackImage = false;

  bool _initialized = false;
  bool _saving = false;
  String? _saveError;
  bool _dirty = false;

  @override
  void initState() {
    super.initState();
    _name = TextEditingController();
    _memo = TextEditingController();
    _name.addListener(_markDirty);
    _memo.addListener(_markDirty);
  }

  @override
  void dispose() {
    _name.dispose();
    _memo.dispose();
    for (final c in _xCtrls) {
      c.dispose();
    }
    for (final c in _urlCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  void _populateFromCard(BusinessCard card) {
    if (_initialized) return;
    _initialized = true;

    _name.text = card.displayName ?? '';
    _memo.text = card.memo ?? '';

    for (final link in card.snsLinks) {
      if (link.startsWith('@')) {
        _xCtrls.add(
          TextEditingController(text: link.substring(1))..addListener(_markDirty),
        );
      } else {
        _urlCtrls.add(TextEditingController(text: link)..addListener(_markDirty));
      }
    }

    _selectedTags
      ..clear()
      ..addAll(card.tags);
    _selectedEvents
      ..clear()
      ..addAll(card.events);

    _imagePath = card.imagePath;

    _backImagePath = card.backImagePath;
    _originalBackImagePath = card.backImagePath;

    // Controllers were added without triggering markDirty — reset flag.
    _dirty = false;
  }

  Future<void> _replaceFrontImage() async {
    if (_pickingFrontImage) return;
    final source = await _chooseImageSource();
    if (source == null || !mounted) return;

    setState(() => _pickingFrontImage = true);
    try {
      final picker = ref.read(imagePickerProvider);
      final file = await picker.pickImage(source: source);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final useCase = ref.read(manualEntryUseCaseProvider);
      final draft = await useCase.execute(bytes);
      if (!mounted) return;
      setState(() {
        _imagePath = draft.imagePath;
        _dirty = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('表面の取得に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _pickingFrontImage = false);
    }
  }

  Future<ImageSource?> _chooseImageSource() {
    return showModalBottomSheet<ImageSource>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('撮影'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.image_outlined),
              title: const Text('画像から選択'),
              onTap: () => Navigator.of(ctx).pop(ImageSource.gallery),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickBackImage() async {
    if (_pickingBackImage) return;
    setState(() => _pickingBackImage = true);
    try {
      final picker = ref.read(imagePickerProvider);
      final file = await picker.pickImage(source: ImageSource.gallery);
      if (file == null || !mounted) return;
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      final useCase = ref.read(manualEntryUseCaseProvider);
      final draft = await useCase.execute(bytes);
      if (!mounted) return;
      setState(() {
        _backImagePath = draft.imagePath;
        _dirty = true;
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('裏面の取得に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _pickingBackImage = false);
    }
  }

  void _removeBackImage() => setState(() {
        _backImagePath = null;
        _dirty = true;
      });

  // ---------------------------------------------------------------------------
  // X handle helpers
  // ---------------------------------------------------------------------------

  void _addXHandle() {
    setState(() {
      _xCtrls.add(TextEditingController()..addListener(_markDirty));
      _dirty = true;
    });
  }

  void _removeXHandle(int i) {
    setState(() {
      _xCtrls.removeAt(i).dispose();
      _dirty = true;
    });
  }

  // ---------------------------------------------------------------------------
  // URL helpers
  // ---------------------------------------------------------------------------

  void _addUrl() {
    setState(() {
      _urlCtrls.add(TextEditingController()..addListener(_markDirty));
      _dirty = true;
    });
  }

  void _removeUrl(int i) {
    setState(() {
      _urlCtrls.removeAt(i).dispose();
      _dirty = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Derived values
  // ---------------------------------------------------------------------------

  List<String> _cleanedHandles() => _xCtrls
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .map((s) => s.startsWith('@') ? s : '@$s')
      .toList(growable: false);

  List<String> _cleanedUrls() => _urlCtrls
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

  // ---------------------------------------------------------------------------
  // Tag picker
  // ---------------------------------------------------------------------------

  Future<void> _openTagPicker() async {
    final tagRepo = await ref.read(tagRepositoryProvider.future);
    final allTags = await tagRepo.findAll();
    if (!mounted) return;

    final result = await showTagPickerSheet(
      context: context,
      allTags: allTags,
      initialSelectedIds: _selectedTags.map((t) => t.id).toSet(),
      initialPendingNames: List.unmodifiable(_pendingNewTags),
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedTags
        ..clear()
        ..addAll(allTags.where((t) => result.selectedTagIds.contains(t.id)));
      _pendingNewTags
        ..clear()
        ..addAll(result.newTagNames);
      _dirty = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Event picker
  // ---------------------------------------------------------------------------

  Future<void> _openEventPicker() async {
    final eventRepo = await ref.read(eventRepositoryProvider.future);
    final allEvents = await eventRepo.findAll();
    if (!mounted) return;

    final result = await showEventPickerSheet(
      context: context,
      allEvents: allEvents,
      initialSelectedIds: _selectedEvents.map((e) => e.id).toSet(),
      onCreateNew: (_) async {
        try {
          final newEventId =
              await Navigator.of(context).pushNamed('/event/edit');
          if (newEventId is String && newEventId.isNotEmpty) {
            final repo = await ref.read(eventRepositoryProvider.future);
            final created = await repo.findById(newEventId);
            if (created != null && mounted) {
              setState(() {
                if (!_selectedEvents.any((e) => e.id == created.id)) {
                  _selectedEvents.add(created);
                }
                _dirty = true;
              });
            }
          }
        } catch (_) {
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('イベント作成画面はまだ利用できません')),
          );
        }
      },
    );

    if (result == null || !mounted) return;

    setState(() {
      _selectedEvents
        ..clear()
        ..addAll(allEvents.where((e) => result.contains(e.id)));
      _dirty = true;
    });
  }

  // ---------------------------------------------------------------------------
  // Save flow
  // ---------------------------------------------------------------------------

  Future<void> _save() async {
    if (_pendingNewTags.isNotEmpty) {
      final confirmed = await _showNewTagConfirmDialog();
      if (!confirmed || !mounted) return;
    }
    await _executeSave();
  }

  Future<bool> _showNewTagConfirmDialog() async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('新しいタグを作成しますか?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('以下のタグは初めて使用されます:'),
            const SizedBox(height: AppSpacing.s2),
            ..._pendingNewTags.map(
              (name) => Padding(
                padding: const EdgeInsets.only(left: AppSpacing.s2),
                child: Text('• $name'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('作成して保存'),
          ),
        ],
      ),
    );
    return result == true;
  }

  Future<void> _executeSave() async {
    setState(() {
      _saving = true;
      _saveError = null;
    });
    try {
      final useCase = await ref.read(updateCardUseCaseProvider.future);
      final clearBack = _backImagePath == null && _originalBackImagePath != null;
      await useCase.execute(UpdateCardInput(
        cardId: widget.cardId,
        displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        memo: _memo.text.trim().isEmpty ? null : _memo.text.trim(),
        tagNames: [
          ..._selectedTags.map((t) => t.name),
          ..._pendingNewTags,
        ],
        xHandles: _cleanedHandles(),
        urls: _cleanedUrls(),
        eventIds: _selectedEvents.map((e) => e.id).toList(),
        imagePath: _imagePath,
        backImagePath: _backImagePath,
        clearBackImagePath: clearBack,
      ));
      if (!mounted) return;
      ref.invalidate(cardListProvider);
      ref.invalidate(cardByIdProvider(widget.cardId));
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '保存に失敗しました: $e';
      });
    }
  }

  // ---------------------------------------------------------------------------
  // Unsaved-changes dialog (PopScope)
  // ---------------------------------------------------------------------------

  Future<bool> _confirmDiscard() async {
    if (!_dirty) return true;
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('変更を破棄しますか?'),
        content: const Text('保存されていない変更があります。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('破棄'),
          ),
        ],
      ),
    );
    return result == true;
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cardAsync = ref.watch(cardByIdProvider(widget.cardId));

    return cardAsync.when(
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(title: const Text('カードを編集')),
        body: Center(child: Text('読み込み失敗: $e')),
      ),
      data: (card) {
        if (card == null) {
          return Scaffold(
            appBar: AppBar(title: const Text('カードを編集')),
            body: const Center(child: Text('カードが見つかりません')),
          );
        }

        // Populate controllers on first data load (idempotent).
        _populateFromCard(card);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final nav = Navigator.of(context);
            final ok = await _confirmDiscard();
            if (ok && mounted) nav.pop();
          },
          child: Scaffold(
            appBar: AppBar(
              title: const Text('カードを編集'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                tooltip: '閉じる',
                onPressed: () async {
                  final nav = Navigator.of(context);
                  final ok = await _confirmDiscard();
                  if (ok && mounted) nav.pop();
                },
              ),
              actions: [
                Semantics(
                  label: '保存',
                  button: true,
                  child: TextButton(
                    key: const Key('appbar_save_button'),
                    onPressed: _saving ? null : _save,
                    child: const Text('保存'),
                  ),
                ),
              ],
            ),
            body: SafeArea(
              child: AbsorbPointer(
                absorbing: _saving,
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.s4),
                  children: [
                    _FrontImageEditor(
                      path: _imagePath ?? card.imagePath,
                      loading: _pickingFrontImage,
                      onReplace: _replaceFrontImage,
                    ),
                    const SizedBox(height: AppSpacing.s3),
                    _BackImageSection(
                      path: _backImagePath,
                      loading: _pickingBackImage,
                      onAdd: _pickBackImage,
                      onRemove: _removeBackImage,
                    ),
                    const SizedBox(height: AppSpacing.s6),

                    const _FieldLabel(text: '表示名'),
                    const SizedBox(height: AppSpacing.s2),
                    TextField(
                      controller: _name,
                      decoration:
                          const InputDecoration(hintText: '名前を入力'),
                      maxLength: 50,
                      buildCounter: (
                        _, {
                        required currentLength,
                        required isFocused,
                        maxLength,
                      }) =>
                          null,
                    ),
                    const SizedBox(height: AppSpacing.s5),

                    const _FieldLabel(text: 'X アカウント'),
                    const SizedBox(height: AppSpacing.s2),
                    ..._xCtrls.asMap().entries.map(
                          (e) => _XHandleRow(
                            controller: e.value,
                            onRemove: () => _removeXHandle(e.key),
                          ),
                        ),
                    const SizedBox(height: AppSpacing.s2),
                    OutlinedButton.icon(
                      onPressed: _addXHandle,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('X アカウントを追加'),
                    ),
                    const SizedBox(height: AppSpacing.s5),

                    const _FieldLabel(text: 'イベント (任意)'),
                    const SizedBox(height: AppSpacing.s2),
                    _EventSection(
                      selectedEvents: _selectedEvents,
                      onAddTap: _openEventPicker,
                      onRemoveEvent: (event) => setState(() {
                        _selectedEvents.remove(event);
                        _dirty = true;
                      }),
                    ),
                    const SizedBox(height: AppSpacing.s5),

                    const _FieldLabel(text: 'リンク'),
                    const SizedBox(height: AppSpacing.s2),
                    ..._urlCtrls.asMap().entries.map(
                          (e) => _UrlRow(
                            controller: e.value,
                            onRemove: () => _removeUrl(e.key),
                          ),
                        ),
                    const SizedBox(height: AppSpacing.s2),
                    OutlinedButton.icon(
                      onPressed: _addUrl,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(44, 44),
                      ),
                      icon: const Icon(Icons.add),
                      label: const Text('リンクを追加'),
                    ),
                    const SizedBox(height: AppSpacing.s5),

                    const _FieldLabel(text: 'タグ'),
                    const SizedBox(height: AppSpacing.s2),
                    _TagSection(
                      selectedTags: _selectedTags,
                      pendingNewTags: _pendingNewTags,
                      onRemoveTag: (tag) => setState(() {
                        _selectedTags.remove(tag);
                        _dirty = true;
                      }),
                      onRemovePending: (name) => setState(() {
                        _pendingNewTags.remove(name);
                        _dirty = true;
                      }),
                      onAddTap: _openTagPicker,
                    ),
                    const SizedBox(height: AppSpacing.s5),

                    const _FieldLabel(text: 'メモ (端末のみ)'),
                    const SizedBox(height: AppSpacing.s2),
                    TextField(
                      controller: _memo,
                      maxLines: 4,
                      decoration: const InputDecoration(
                          hintText: 'メモは端末のみに保存されます'),
                    ),
                    const SizedBox(height: AppSpacing.s8),

                    if (_saveError != null) ...[
                      Text(
                        _saveError!,
                        style: theme.textTheme.bodyMedium
                            ?.copyWith(color: theme.colorScheme.error),
                      ),
                      const SizedBox(height: AppSpacing.s4),
                    ],

                    ElevatedButton(
                      key: const Key('save_button'),
                      onPressed: _saving ? null : _save,
                      child: _saving
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text('保存'),
                    ),
                    const SizedBox(height: AppSpacing.s4),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Tag section
// ---------------------------------------------------------------------------

class _TagSection extends StatelessWidget {
  const _TagSection({
    required this.selectedTags,
    required this.pendingNewTags,
    required this.onRemoveTag,
    required this.onRemovePending,
    required this.onAddTap,
  });

  final List<Tag> selectedTags;
  final List<String> pendingNewTags;
  final ValueChanged<Tag> onRemoveTag;
  final ValueChanged<String> onRemovePending;
  final VoidCallback onAddTap;

  @override
  Widget build(BuildContext context) {
    final hasChips = selectedTags.isNotEmpty || pendingNewTags.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasChips)
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s1,
            children: [
              for (final tag in selectedTags)
                Chip(
                  label: Text(tag.name),
                  deleteIcon: const Icon(Icons.cancel, size: 18),
                  onDeleted: () => onRemoveTag(tag),
                ),
              for (final name in pendingNewTags)
                Chip(
                  label: Text(name),
                  avatar: const Icon(Icons.add_circle_outline, size: 16),
                  deleteIcon: const Icon(Icons.cancel, size: 18),
                  onDeleted: () => onRemovePending(name),
                ),
            ],
          ),
        if (hasChips) const SizedBox(height: AppSpacing.s2),
        Semantics(
          label: 'タグを追加',
          button: true,
          child: OutlinedButton.icon(
            key: const Key('add_tag_button'),
            onPressed: onAddTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(Icons.add),
            label: const Text('+ タグを追加'),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Event section
// ---------------------------------------------------------------------------

class _EventSection extends StatelessWidget {
  const _EventSection({
    required this.selectedEvents,
    required this.onAddTap,
    required this.onRemoveEvent,
  });

  final List<Event> selectedEvents;
  final VoidCallback onAddTap;
  final ValueChanged<Event> onRemoveEvent;

  @override
  Widget build(BuildContext context) {
    final hasChips = selectedEvents.isNotEmpty;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (hasChips)
          Wrap(
            spacing: AppSpacing.s2,
            runSpacing: AppSpacing.s1,
            children: [
              for (final event in selectedEvents)
                Chip(
                  key: Key('event_chip_${event.id}'),
                  label: Text(event.name),
                  deleteIcon: Semantics(
                    label: '${event.name}を解除',
                    child: const Icon(Icons.cancel, size: 18),
                  ),
                  onDeleted: () => onRemoveEvent(event),
                ),
            ],
          ),
        if (hasChips) const SizedBox(height: AppSpacing.s2),
        Semantics(
          label: 'イベントを追加',
          button: true,
          child: OutlinedButton.icon(
            key: const Key('select_event_button'),
            onPressed: onAddTap,
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(44, 44),
            ),
            icon: const Icon(Icons.event),
            label: const Text('+ イベントを追加'),
          ),
        ),
      ],
    );
  }
}


// ---------------------------------------------------------------------------
// Shared sub-widgets
// ---------------------------------------------------------------------------

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.labelLarge);
  }
}

class _BackImageSection extends StatelessWidget {
  const _BackImageSection({
    required this.path,
    required this.loading,
    required this.onAdd,
    required this.onRemove,
  });

  final String? path;
  final bool loading;
  final VoidCallback onAdd;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final p = path;
    if (p == null) {
      return Align(
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          key: const Key('add_back_image_button'),
          onPressed: loading ? null : onAdd,
          icon: loading
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add_photo_alternate_outlined, size: 18),
          label: const Text('裏面を追加 (任意)'),
        ),
      );
    }
    final file = File(p);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: 120,
            width: double.infinity,
            child: file.existsSync()
                ? Image.file(file, fit: BoxFit.cover)
                : const ColoredBox(color: Colors.black12),
          ),
        ),
        Positioned(
          top: 4,
          right: 4,
          child: Material(
            color: Colors.black54,
            shape: const CircleBorder(),
            child: IconButton(
              key: const Key('remove_back_image_button'),
              icon: const Icon(Icons.close, color: Colors.white, size: 18),
              tooltip: '裏面を削除',
              onPressed: onRemove,
              constraints: const BoxConstraints.tightFor(width: 32, height: 32),
              padding: EdgeInsets.zero,
            ),
          ),
        ),
      ],
    );
  }
}

class _FrontImageEditor extends StatelessWidget {
  const _FrontImageEditor({
    required this.path,
    required this.loading,
    required this.onReplace,
  });

  final String path;
  final bool loading;
  final VoidCallback onReplace;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final theme = Theme.of(context);
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.xl),
          child: AspectRatio(
            aspectRatio: 91 / 55,
            child: file.existsSync()
                ? Image.file(
                    file,
                    fit: BoxFit.cover,
                    // Force rebuild when path changes (file size differs).
                    key: ValueKey(path),
                  )
                : Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Center(
                      child: Icon(Icons.image_outlined, size: 48),
                    ),
                  ),
          ),
        ),
        Positioned(
          right: 8,
          bottom: 8,
          child: Material(
            color: Colors.black54,
            shape: const StadiumBorder(),
            child: InkWell(
              key: const Key('replace_front_image_button'),
              customBorder: const StadiumBorder(),
              onTap: loading ? null : onReplace,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.s3,
                  vertical: AppSpacing.s2,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (loading)
                      const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    else
                      const Icon(
                        Icons.edit_outlined,
                        color: Colors.white,
                        size: 18,
                      ),
                    const SizedBox(width: AppSpacing.s2),
                    const Text(
                      '差し替え',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _XHandleRow extends StatelessWidget {
  const _XHandleRow({required this.controller, required this.onRemove});

  final TextEditingController controller;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(
                prefixText: '@',
                hintText: 'ハンドル名',
              ),
              autocorrect: false,
              enableSuggestions: false,
            ),
          ),
          Semantics(
            label: 'この X アカウントを削除',
            button: true,
            child: IconButton(
              tooltip: 'この X アカウントを削除',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        ],
      ),
    );
  }
}

class _UrlRow extends StatelessWidget {
  const _UrlRow({required this.controller, required this.onRemove});

  final TextEditingController controller;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              decoration: const InputDecoration(hintText: 'https://...'),
              keyboardType: TextInputType.url,
              autocorrect: false,
              enableSuggestions: false,
            ),
          ),
          Semantics(
            label: 'このリンクを削除',
            button: true,
            child: IconButton(
              tooltip: 'このリンクを削除',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
          ),
        ],
      ),
    );
  }
}
