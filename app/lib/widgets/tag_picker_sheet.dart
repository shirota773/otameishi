import 'package:flutter/material.dart';

import '../models/tag.dart';
import '../theme/app_theme.dart';
import 'sheet_handle.dart';

/// Result returned by [showTagPickerSheet].
class TagPickerResult {
  const TagPickerResult({
    required this.selectedTagIds,
    required this.newTagNames,
  });

  final Set<String> selectedTagIds;
  final List<String> newTagNames;
}

/// Shows the tag-picker bottom sheet and returns the user's selection, or
/// null if the sheet was dismissed without confirming.
Future<TagPickerResult?> showTagPickerSheet({
  required BuildContext context,
  required List<Tag> allTags,
  required Set<String> initialSelectedIds,
  required List<String> initialPendingNames,
}) {
  return showModalBottomSheet<TagPickerResult>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => TagPickerSheet(
      allTags: allTags,
      initialSelectedIds: initialSelectedIds,
      initialPendingNames: initialPendingNames,
    ),
  );
}

/// Multi-select tag picker with inline "create new tag" affordance.
///
/// On confirm the sheet pops a [TagPickerResult]; on dismiss it pops null.
class TagPickerSheet extends StatefulWidget {
  const TagPickerSheet({
    super.key,
    required this.allTags,
    required this.initialSelectedIds,
    required this.initialPendingNames,
  });

  final List<Tag> allTags;
  final Set<String> initialSelectedIds;
  final List<String> initialPendingNames;

  @override
  State<TagPickerSheet> createState() => _TagPickerSheetState();
}

class _TagPickerSheetState extends State<TagPickerSheet> {
  late final TextEditingController _search;
  late Set<String> _selectedIds;
  late List<String> _pendingNames;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _selectedIds = Set.of(widget.initialSelectedIds);
    _pendingNames = List.of(widget.initialPendingNames);
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim();

  List<Tag> get _filteredTags {
    if (_query.isEmpty) return widget.allTags;
    final q = _query.toLowerCase();
    return widget.allTags
        .where((t) => t.name.toLowerCase().contains(q))
        .toList();
  }

  bool get _showCreateRow {
    if (_query.isEmpty) return false;
    final exactMatch = widget.allTags.any(
      (t) => t.name.toLowerCase() == _query.toLowerCase(),
    );
    if (exactMatch) return false;
    return !_pendingNames.any(
      (n) => n.toLowerCase() == _query.toLowerCase(),
    );
  }

  int get _totalSelectedCount => _selectedIds.length + _pendingNames.length;

  void _toggleTag(Tag tag) {
    setState(() {
      if (_selectedIds.contains(tag.id)) {
        _selectedIds.remove(tag.id);
      } else {
        _selectedIds.add(tag.id);
      }
    });
  }

  void _addPendingTag() {
    final name = _query;
    if (name.isEmpty) return;
    setState(() {
      _pendingNames = [..._pendingNames, name];
      _search.clear();
    });
  }

  void _clearAll() {
    setState(() {
      _selectedIds = {};
      _pendingNames = [];
    });
  }

  void _confirm() {
    Navigator.of(context).pop(
      TagPickerResult(
        selectedTagIds: Set.unmodifiable(_selectedIds),
        newTagNames: List.unmodifiable(_pendingNames),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredTags;

    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (_, scrollController) => Column(
        children: [
          const SheetHandle(),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s3,
            ),
            child: Text('タグを選択', style: theme.textTheme.titleLarge),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s2,
            ),
            child: TextField(
              key: const Key('tag_search_field'),
              controller: _search,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'タグを検索 or 新規作成',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                for (final tag in filtered)
                  CheckboxListTile(
                    title: Text(tag.name),
                    value: _selectedIds.contains(tag.id),
                    onChanged: (_) => _toggleTag(tag),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                    ),
                  ),
                for (final name in _pendingNames)
                  CheckboxListTile(
                    title: Text(name),
                    subtitle: const Text('新規作成予定'),
                    value: true,
                    onChanged: (_) => setState(
                      () => _pendingNames =
                          _pendingNames.where((n) => n != name).toList(),
                    ),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                    ),
                  ),
                if (_showCreateRow)
                  ListTile(
                    leading: const Icon(Icons.add_circle_outline),
                    title: Text('+ 新しいタグ「$_query」を作成'),
                    onTap: _addPendingTag,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                    ),
                  ),
              ],
            ),
          ),
          const Divider(height: 1),
          Padding(
            padding: EdgeInsets.fromLTRB(
              AppSpacing.s4,
              AppSpacing.s2,
              AppSpacing.s4,
              AppSpacing.s4 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Row(
              children: [
                Semantics(
                  label: '選択をクリア',
                  button: true,
                  child: OutlinedButton(
                    onPressed: _clearAll,
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    child: const Text('選択をクリア'),
                  ),
                ),
                const Spacer(),
                Semantics(
                  label: '完了',
                  button: true,
                  child: ElevatedButton(
                    key: const Key('tag_picker_done'),
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(
                      _totalSelectedCount > 0
                          ? '完了 ($_totalSelectedCount)'
                          : '完了',
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
