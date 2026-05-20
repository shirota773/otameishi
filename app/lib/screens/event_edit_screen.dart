import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:uuid/uuid.dart';

import '../core/providers.dart';
import '../models/event.dart';
import '../theme/app_theme.dart';

// ---------------------------------------------------------------------------
// Internal notifier — loads the existing event (edit mode) once on mount.
// ---------------------------------------------------------------------------

final _editEventProvider =
    FutureProvider.autoDispose.family<Event?, String?>((ref, id) async {
  if (id == null) return null;
  final repo = await ref.watch(eventRepositoryProvider.future);
  return repo.findById(id);
});

// ---------------------------------------------------------------------------

class EventEditScreen extends ConsumerStatefulWidget {
  const EventEditScreen({super.key, this.eventId});

  /// null = create new event; non-null = edit existing event.
  final String? eventId;

  @override
  ConsumerState<EventEditScreen> createState() => _EventEditScreenState();
}

class _EventEditScreenState extends ConsumerState<EventEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _memoController = TextEditingController();

  DateTime? _date;
  bool _isDirty = false;
  bool _isSaving = false;
  bool _initialised = false;

  static const int _nameMaxLength = 60;
  static const int _memoMaxLength = 500;

  @override
  void dispose() {
    _nameController.dispose();
    _memoController.dispose();
    super.dispose();
  }

  void _markDirty() {
    if (!_isDirty) setState(() => _isDirty = true);
  }

  void _initFromEvent(Event event) {
    if (_initialised) return;
    _nameController.text = event.name;
    _memoController.text = event.memo ?? '';
    _date = event.date;
    _initialised = true;
  }

  // ── Date picker ───────────────────────────────────────────────────────────

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _date ?? DateTime.now(),
      firstDate: DateTime(1990),
      lastDate: DateTime(2099),
      locale: const Locale('ja'),
    );
    if (picked != null && picked != _date) {
      setState(() {
        _date = picked;
        _isDirty = true;
      });
    }
  }

  void _clearDate() {
    setState(() {
      _date = null;
      _isDirty = true;
    });
  }

  // ── Save ─────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;
    setState(() => _isSaving = true);

    try {
      final repo = await ref.read(eventRepositoryProvider.future);
      final isNew = widget.eventId == null;
      final event = Event(
        id: isNew ? const Uuid().v4() : widget.eventId!,
        name: _nameController.text.trim(),
        date: _date,
        memo: _memoController.text.trim().isEmpty
            ? null
            : _memoController.text.trim(),
      );
      if (isNew) {
        await repo.insert(event);
      } else {
        await repo.update(event);
      }
      ref.invalidate(eventListProvider);
      if (mounted) Navigator.of(context).pop(event);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('保存に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Delete ────────────────────────────────────────────────────────────────

  Future<void> _confirmDelete() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('イベントを削除しますか?'),
        content: const Text('紐づくカードは残りますが、イベント情報は失われます。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('キャンセル'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('削除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await _delete();
  }

  Future<void> _delete() async {
    setState(() => _isSaving = true);
    try {
      final repo = await ref.read(eventRepositoryProvider.future);
      await repo.delete(widget.eventId!);
      ref.invalidate(eventListProvider);
      if (mounted) {
        // Pop twice to go back past detail screen to the list.
        Navigator.of(context).popUntil(
          (route) => route.settings.name == '/' || route.isFirst,
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('削除に失敗しました: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Unsaved-changes guard ─────────────────────────────────────────────────

  Future<bool> _onWillPop() async {
    if (!_isDirty) return true;
    final discard = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('編集中の内容を破棄しますか?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('編集を続ける'),
          ),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('破棄'),
          ),
        ],
      ),
    );
    return discard == true;
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final isEditMode = widget.eventId != null;
    final asyncEvent = isEditMode
        ? ref.watch(_editEventProvider(widget.eventId))
        : const AsyncData<Event?>(null);

    return asyncEvent.when(
      loading: () => Scaffold(
        appBar: AppBar(
          title: Text(isEditMode ? 'イベントを編集' : 'イベントを追加'),
        ),
        body: const Center(child: CircularProgressIndicator()),
      ),
      error: (e, _) => Scaffold(
        appBar: AppBar(
          title: Text(isEditMode ? 'イベントを編集' : 'イベントを追加'),
        ),
        body: Center(child: Text('エラー: $e')),
      ),
      data: (event) {
        if (isEditMode && event != null) _initFromEvent(event);

        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) async {
            if (didPop) return;
            final shouldPop = await _onWillPop();
            if (shouldPop && context.mounted) {
              Navigator.of(context).pop();
            }
          },
          child: Scaffold(
            appBar: AppBar(
              title: Text(isEditMode ? 'イベントを編集' : 'イベントを追加'),
              leading: IconButton(
                tooltip: '閉じる',
                icon: const Icon(Icons.close),
                onPressed: () async {
                  final shouldPop = await _onWillPop();
                  if (shouldPop && context.mounted) {
                    Navigator.of(context).pop();
                  }
                },
              ),
            ),
            body: _isSaving
                ? const Center(child: CircularProgressIndicator())
                : _FormBody(
                    formKey: _formKey,
                    nameController: _nameController,
                    memoController: _memoController,
                    date: _date,
                    isEditMode: isEditMode,
                    nameMaxLength: _nameMaxLength,
                    memoMaxLength: _memoMaxLength,
                    onMarkDirty: _markDirty,
                    onPickDate: _pickDate,
                    onClearDate: _clearDate,
                    onSave: _save,
                    onDelete: isEditMode ? _confirmDelete : null,
                  ),
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Private: form body extracted to keep EventEditScreen under 150 lines.
// ---------------------------------------------------------------------------

class _FormBody extends StatelessWidget {
  const _FormBody({
    required this.formKey,
    required this.nameController,
    required this.memoController,
    required this.date,
    required this.isEditMode,
    required this.nameMaxLength,
    required this.memoMaxLength,
    required this.onMarkDirty,
    required this.onPickDate,
    required this.onClearDate,
    required this.onSave,
    this.onDelete,
  });

  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController memoController;
  final DateTime? date;
  final bool isEditMode;
  final int nameMaxLength;
  final int memoMaxLength;
  final VoidCallback onMarkDirty;
  final VoidCallback onPickDate;
  final VoidCallback onClearDate;
  final VoidCallback onSave;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSpacing.s4),
      child: Form(
        key: formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _NameField(
              controller: nameController,
              maxLength: nameMaxLength,
              onChanged: (_) => onMarkDirty(),
            ),
            const SizedBox(height: AppSpacing.s4),
            _DateField(
              label: '開始日',
              date: date,
              onTap: onPickDate,
              onClear: onClearDate,
            ),
            const SizedBox(height: AppSpacing.s4),
            _MemoField(
              controller: memoController,
              maxLength: memoMaxLength,
              onChanged: (_) => onMarkDirty(),
            ),
            const SizedBox(height: AppSpacing.s6),
            ElevatedButton(
              onPressed: onSave,
              child: const Text('保存'),
            ),
            if (onDelete != null) ...[
              const SizedBox(height: AppSpacing.s3),
              OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: Theme.of(context).colorScheme.error,
                  side: BorderSide(
                    color: Theme.of(context).colorScheme.error,
                    width: 2,
                  ),
                ),
                onPressed: onDelete,
                child: const Text('削除'),
              ),
            ],
            const SizedBox(height: AppSpacing.s8),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Private sub-widgets
// ---------------------------------------------------------------------------

class _NameField extends StatelessWidget {
  const _NameField({
    required this.controller,
    required this.maxLength,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int maxLength;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'イベント名 *',
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.s1),
        TextFormField(
          controller: controller,
          maxLength: maxLength,
          textInputAction: TextInputAction.next,
          onChanged: onChanged,
          decoration: const InputDecoration(
            hintText: 'コミケ106',
            counterText: '',
          ),
          validator: (v) {
            final trimmed = (v ?? '').trim();
            if (trimmed.isEmpty) return 'イベント名を入力してください';
            if (trimmed.length > maxLength) {
              return '$maxLength文字以内で入力してください';
            }
            return null;
          },
        ),
      ],
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.label,
    required this.date,
    required this.onTap,
    required this.onClear,
  });

  final String label;
  final DateTime? date;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMMMd('ja');

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.labelLarge),
        const SizedBox(height: AppSpacing.s1),
        Semantics(
          label: '$label: ${date != null ? dateFmt.format(date!) : "未設定"}',
          button: true,
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            onTap: onTap,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.s4),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(AppRadius.sm),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      date != null ? dateFmt.format(date!) : '日付を選択',
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: date != null
                            ? null
                            : theme.colorScheme.onSurface.withValues(alpha: 0.4),
                      ),
                    ),
                  ),
                  if (date != null)
                    IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: '日付をクリア',
                      onPressed: onClear,
                      constraints: const BoxConstraints(
                        minWidth: 44,
                        minHeight: 44,
                      ),
                    )
                  else
                    const Icon(Icons.calendar_today_outlined, size: 20),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _MemoField extends StatelessWidget {
  const _MemoField({
    required this.controller,
    required this.maxLength,
    required this.onChanged,
  });

  final TextEditingController controller;
  final int maxLength;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('メモ (任意)', style: Theme.of(context).textTheme.labelLarge),
        const SizedBox(height: AppSpacing.s1),
        TextFormField(
          controller: controller,
          maxLength: maxLength,
          maxLines: 4,
          keyboardType: TextInputType.multiline,
          onChanged: onChanged,
          decoration: const InputDecoration(
            hintText: '備考・感想など',
          ),
          validator: (v) {
            if ((v ?? '').length > maxLength) {
              return '$maxLength文字以内で入力してください';
            }
            return null;
          },
        ),
      ],
    );
  }
}
