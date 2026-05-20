import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../core/providers.dart';
import '../models/event.dart';
import '../models/tag.dart';
import '../services/service_models.dart';
import '../theme/app_theme.dart';
import '../usecases/save_card_usecase.dart';
import '../widgets/event_picker_sheet.dart';
import '../widgets/tag_picker_sheet.dart';

/// Review and edit a [CardDraft] before saving.
///
/// Three entry modes share this screen:
///   • auto (撮影フロー)  — `draft.extractedData != null`, fields are
///     prefilled from OCR.
///   • manual (＋ボタン手入力)  — `draft.extractedData == null`, all fields
///     start empty.  The cancel button reads "キャンセル" instead of "撮り直す".
///   • my-card (マイカード登録) — `isMyCard: true`.  Title reads "マイカードを登録".
///     On save, [myCardProvider] is also invalidated.
class CaptureReviewScreen extends ConsumerStatefulWidget {
  const CaptureReviewScreen({
    super.key,
    required this.draft,
    this.isMyCard = false,
  });

  final CardDraft draft;

  /// When true, the saved card will be flagged as the user's own profile card.
  final bool isMyCard;

  @override
  ConsumerState<CaptureReviewScreen> createState() => _CaptureReviewScreenState();
}

class _CaptureReviewScreenState extends ConsumerState<CaptureReviewScreen> {
  late final TextEditingController _name;
  late final TextEditingController _memo;

  final List<TextEditingController> _xCtrls = [];
  final List<TextEditingController> _urlCtrls = [];

  // v3: tag state
  final List<Tag> _selectedTags = [];
  final List<String> _pendingNewTags = [];

  // v4: event state — multiple events per card
  final List<Event> _selectedEvents = [];

  // v5: back image
  String? _backImagePath;
  bool _pickingBackImage = false;

  /// OCR text lines that have not yet been routed to a form field.
  /// Tapping a chip shows a destination menu (name/X/tag/memo) and removes the
  /// line from this list once assigned.
  final List<String> _ocrCandidates = [];

  bool _saving = false;
  String? _saveError;

  bool get _isManual => widget.draft.extractedData == null;

  @override
  void initState() {
    super.initState();
    final extracted = widget.draft.extractedData;
    _name = TextEditingController(text: extracted?.nameCandidate ?? '');
    _memo = TextEditingController();

    for (final h in extracted?.xHandles ?? const <String>[]) {
      _xCtrls.add(TextEditingController(text: _stripLeadingAt(h)));
    }
    for (final u in extracted?.urls ?? const <String>[]) {
      _urlCtrls.add(TextEditingController(text: u));
    }

    _ocrCandidates.addAll(_buildInitialCandidates(extracted));
  }

  /// Build the candidate-line pool from raw OCR, excluding lines already
  /// routed to auto-filled fields (name / X handles / URLs).
  List<String> _buildInitialCandidates(ExtractedData? extracted) {
    final raw = widget.draft.ocr?.lines ?? const <String>[];
    if (raw.isEmpty) return const [];

    final consumed = <String>{
      if (extracted?.nameCandidate != null) extracted!.nameCandidate!.trim(),
      ...?extracted?.xHandles.map((s) => s.trim()),
      ...?extracted?.urls.map((s) => s.trim()),
    };

    final seen = <String>{};
    final result = <String>[];
    for (final line in raw) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      if (consumed.contains(trimmed)) continue;
      if (!seen.add(trimmed)) continue;
      result.add(trimmed);
    }
    return result;
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

  String _stripLeadingAt(String s) => s.startsWith('@') ? s.substring(1) : s;

  void _addXHandle() => setState(() => _xCtrls.add(TextEditingController()));
  void _addUrl() => setState(() => _urlCtrls.add(TextEditingController()));

  void _removeXHandle(int i) {
    setState(() {
      _xCtrls.removeAt(i).dispose();
    });
  }

  void _removeUrl(int i) {
    setState(() {
      _urlCtrls.removeAt(i).dispose();
    });
  }

  List<String> _cleanedHandles() => _xCtrls
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .map((s) => s.startsWith('@') ? s : '@$s')
      .toList(growable: false);

  List<String> _cleanedUrls() => _urlCtrls
      .map((c) => c.text.trim())
      .where((s) => s.isNotEmpty)
      .toList(growable: false);

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
    });
  }

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
    });
  }

  // v5: pick a back image via gallery and run it through ManualEntryUseCase
  // (encode + save only — no OCR).
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
      setState(() => _backImagePath = draft.imagePath);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('裏面の取得に失敗しました: $e')),
      );
    } finally {
      if (mounted) setState(() => _pickingBackImage = false);
    }
  }

  void _removeBackImage() => setState(() => _backImagePath = null);

  // ---------------------------------------------------------------------------
  // OCR candidate routing
  // ---------------------------------------------------------------------------

  Future<void> _onCandidateTap(String line) async {
    final dest = await showModalBottomSheet<_CandidateDest>(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (_) => _CandidateDestSheet(line: line),
    );
    if (dest == null || !mounted) return;

    setState(() {
      switch (dest) {
        case _CandidateDest.name:
          _name.text = line;
        case _CandidateDest.xHandle:
          _xCtrls.add(TextEditingController(text: _stripLeadingAt(line)));
        case _CandidateDest.tag:
          if (!_pendingNewTags.contains(line)) _pendingNewTags.add(line);
        case _CandidateDest.memo:
          final current = _memo.text;
          _memo.text = current.isEmpty ? line : '$current\n$line';
      }
      _ocrCandidates.remove(line);
    });
  }

  // v3: save with optional confirmation for new tags
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
      final useCase = await ref.read(saveCardUseCaseProvider.future);
      await useCase.execute(SaveCardInput(
        draft: widget.draft,
        displayName: _name.text.trim().isEmpty ? null : _name.text.trim(),
        memo: _memo.text.trim().isEmpty ? null : _memo.text.trim(),
        tagNames: [
          ..._selectedTags.map((t) => t.name),
          ..._pendingNewTags,
        ],
        xHandles: _cleanedHandles(),
        urls: _cleanedUrls(),
        eventIds: _selectedEvents.map((e) => e.id).toList(),
        backImagePath: _backImagePath,
        isMyCard: widget.isMyCard,
      ));
      if (!mounted) return;
      ref.invalidate(cardListProvider);
      if (widget.isMyCard) ref.invalidate(myCardProvider);
      Navigator.of(context).popUntil((r) => r.isFirst);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = '保存に失敗しました: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isMyCard ? 'マイカードを登録' : '内容を確認'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: SafeArea(
        child: AbsorbPointer(
          absorbing: _saving,
          child: ListView(
            padding: const EdgeInsets.all(AppSpacing.s4),
            children: [
              _ImagePreview(path: widget.draft.imagePath),
              const SizedBox(height: AppSpacing.s3),
              _BackImageSection(
                path: _backImagePath,
                loading: _pickingBackImage,
                onAdd: _pickBackImage,
                onRemove: _removeBackImage,
              ),
              const SizedBox(height: AppSpacing.s5),
              _OcrCandidatesPanel(
                candidates: _ocrCandidates,
                onCandidateTap: _onCandidateTap,
              ),

              const _Label(text: '表示名'),
              const SizedBox(height: AppSpacing.s2),
              TextField(
                controller: _name,
                decoration: const InputDecoration(hintText: '名前を入力'),
                maxLength: 50,
                buildCounter: (_, {required currentLength, required isFocused, maxLength}) => null,
              ),
              const SizedBox(height: AppSpacing.s5),

              const _Label(text: 'X アカウント'),
              const SizedBox(height: AppSpacing.s2),
              ..._xCtrls.asMap().entries.map((e) => _XHandleRow(
                    controller: e.value,
                    onRemove: () => _removeXHandle(e.key),
                  )),
              const SizedBox(height: AppSpacing.s2),
              OutlinedButton.icon(
                onPressed: _addXHandle,
                icon: const Icon(Icons.add),
                label: const Text('X アカウントを追加'),
              ),
              const SizedBox(height: AppSpacing.s5),

              // v4: event section — multi-select chips (between X accounts and links)
              const _Label(text: 'イベント (任意)'),
              const SizedBox(height: AppSpacing.s2),
              _EventSection(
                selectedEvents: _selectedEvents,
                onAddTap: _openEventPicker,
                onRemoveEvent: (event) =>
                    setState(() => _selectedEvents.remove(event)),
              ),
              const SizedBox(height: AppSpacing.s5),

              const _Label(text: 'リンク'),
              const SizedBox(height: AppSpacing.s2),
              ..._urlCtrls.asMap().entries.map((e) => _UrlRow(
                    controller: e.value,
                    onRemove: () => _removeUrl(e.key),
                  )),
              const SizedBox(height: AppSpacing.s2),
              OutlinedButton.icon(
                onPressed: _addUrl,
                icon: const Icon(Icons.add),
                label: const Text('リンクを追加'),
              ),
              const SizedBox(height: AppSpacing.s5),

              // v3: tag chips section
              const _Label(text: 'タグ'),
              const SizedBox(height: AppSpacing.s2),
              _TagSection(
                selectedTags: _selectedTags,
                pendingNewTags: _pendingNewTags,
                onRemoveTag: (tag) => setState(() => _selectedTags.remove(tag)),
                onRemovePending: (name) => setState(() => _pendingNewTags.remove(name)),
                onAddTap: _openTagPicker,
              ),
              const SizedBox(height: AppSpacing.s5),

              const _Label(text: 'メモ (端末のみ)'),
              const SizedBox(height: AppSpacing.s2),
              TextField(
                controller: _memo,
                maxLines: 4,
                decoration: const InputDecoration(hintText: 'メモは端末のみに保存されます'),
              ),
              const SizedBox(height: AppSpacing.s8),

              if (_saveError != null) ...[
                Text(_saveError!,
                    style: theme.textTheme.bodyMedium
                        ?.copyWith(color: theme.colorScheme.error)),
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
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('保存'),
              ),
              const SizedBox(height: AppSpacing.s4),
              OutlinedButton(
                onPressed: _saving ? null : () => Navigator.of(context).pop(),
                child: Text(_isManual ? 'キャンセル' : '撮り直す'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// v3 section widgets
// ---------------------------------------------------------------------------

/// Displays selected tag chips and an "+ タグを追加" button.
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
            icon: const Icon(Icons.add),
            label: const Text('+ タグを追加'),
          ),
        ),
      ],
    );
  }
}

/// Displays selected event chips and a "+ イベントを追加" button.
/// Mirrors the structure of [_TagSection].
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
            icon: const Icon(Icons.event),
            label: const Text('+ イベントを追加'),
          ),
        ),
      ],
    );
  }
}


// ---------------------------------------------------------------------------
// Shared screen sub-widgets (unchanged from v2)
// ---------------------------------------------------------------------------

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(text, style: Theme.of(context).textTheme.labelLarge);
  }
}

class _ImagePreview extends StatelessWidget {
  const _ImagePreview({required this.path});
  final String path;

  @override
  Widget build(BuildContext context) {
    final file = File(path);
    final theme = Theme.of(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(AppRadius.xl),
      child: AspectRatio(
        aspectRatio: 91 / 55,
        child: file.existsSync()
            ? Image.file(file, fit: BoxFit.cover)
            : Container(
                color: theme.colorScheme.surfaceContainerHighest,
                child: const Center(
                  child: Icon(Icons.image_outlined, size: 48),
                ),
              ),
      ),
    );
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

// ---------------------------------------------------------------------------
// OCR candidates panel
// ---------------------------------------------------------------------------

enum _CandidateDest { name, xHandle, tag, memo }

class _OcrCandidatesPanel extends StatelessWidget {
  const _OcrCandidatesPanel({
    required this.candidates,
    required this.onCandidateTap,
  });

  final List<String> candidates;
  final ValueChanged<String> onCandidateTap;

  @override
  Widget build(BuildContext context) {
    if (candidates.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.s5),
      child: Container(
        padding: const EdgeInsets.all(AppSpacing.s3),
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(
                  Icons.text_snippet_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: AppSpacing.s1),
                Text(
                  '読み取り候補 (${candidates.length}件)',
                  style: theme.textTheme.labelLarge,
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.s1),
            Text(
              'タップして 名前 / X / タグ / メモ に振り分け',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.s2),
            Wrap(
              spacing: AppSpacing.s2,
              runSpacing: AppSpacing.s1,
              children: [
                for (final line in candidates)
                  ActionChip(
                    key: Key('ocr_chip_$line'),
                    label: Text(
                      line,
                      style: const TextStyle(fontSize: 13),
                    ),
                    onPressed: () => onCandidateTap(line),
                    visualDensity: VisualDensity.compact,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CandidateDestSheet extends StatelessWidget {
  const _CandidateDestSheet({required this.line});

  final String line;

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
                AppSpacing.s1,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '「$line」を…',
                  style: theme.textTheme.titleMedium,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const Divider(height: 1),
            _DestTile(
              icon: Icons.badge_outlined,
              label: '名前に設定 (既存を上書き)',
              onTap: () => Navigator.of(context).pop(_CandidateDest.name),
            ),
            _DestTile(
              icon: Icons.alternate_email,
              label: 'X アカウントとして追加',
              onTap: () => Navigator.of(context).pop(_CandidateDest.xHandle),
            ),
            _DestTile(
              icon: Icons.label_outline,
              label: 'タグとして追加',
              onTap: () => Navigator.of(context).pop(_CandidateDest.tag),
            ),
            _DestTile(
              icon: Icons.notes_outlined,
              label: 'メモに追記',
              onTap: () => Navigator.of(context).pop(_CandidateDest.memo),
            ),
          ],
        ),
      ),
    );
  }
}

class _DestTile extends StatelessWidget {
  const _DestTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label),
      onTap: onTap,
    );
  }
}
