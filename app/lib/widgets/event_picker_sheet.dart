import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/event.dart';
import '../theme/app_theme.dart';
import 'sheet_handle.dart';

/// Shows the event-picker bottom sheet (multi-select) and returns the set of
/// selected event IDs, or null if the sheet was dismissed without confirming.
///
/// [onCreateNew] is invoked when the user taps the "+ 新しいイベントを作成"
/// row; it receives the user's current selection so the caller can preserve
/// it across the create-event flow.
Future<Set<String>?> showEventPickerSheet({
  required BuildContext context,
  required List<Event> allEvents,
  required Set<String> initialSelectedIds,
  required ValueChanged<Set<String>> onCreateNew,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
    ),
    builder: (_) => EventPickerSheet(
      allEvents: allEvents,
      initialSelectedIds: initialSelectedIds,
      onCreateNew: onCreateNew,
    ),
  );
}

class EventPickerSheet extends StatefulWidget {
  const EventPickerSheet({
    super.key,
    required this.allEvents,
    required this.initialSelectedIds,
    required this.onCreateNew,
  });

  final List<Event> allEvents;
  final Set<String> initialSelectedIds;
  final ValueChanged<Set<String>> onCreateNew;

  @override
  State<EventPickerSheet> createState() => _EventPickerSheetState();
}

class _EventPickerSheetState extends State<EventPickerSheet> {
  late final TextEditingController _search;
  late Set<String> _selectedIds;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
    _selectedIds = Set.of(widget.initialSelectedIds);
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _query => _search.text.trim();

  List<Event> get _filteredEvents {
    if (_query.isEmpty) return widget.allEvents;
    final q = _query.toLowerCase();
    return widget.allEvents
        .where((e) => e.name.toLowerCase().contains(q))
        .toList();
  }

  void _toggleEvent(Event event) {
    setState(() {
      if (_selectedIds.contains(event.id)) {
        _selectedIds.remove(event.id);
      } else {
        _selectedIds.add(event.id);
      }
    });
  }

  void _clearAll() => setState(() => _selectedIds = {});

  void _confirm() => Navigator.of(context).pop(Set.unmodifiable(_selectedIds));

  /// Pops the sheet (returning current selections as the result so the caller's
  /// `await` resolves with them) and then invokes [widget.onCreateNew] so the
  /// caller can navigate to its create-event flow.
  void _onCreateNewTap() {
    final selections = Set.unmodifiable(_selectedIds);
    Navigator.of(context).pop(selections);
    widget.onCreateNew(selections);
  }

  String _eventSubtitle(Event e) {
    if (e.date == null) return '日付未設定';
    return DateFormat('yyyy年MM月dd日').format(e.date!);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filtered = _filteredEvents;

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
            child: Text('イベントを選択', style: theme.textTheme.titleLarge),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.s4,
              vertical: AppSpacing.s2,
            ),
            child: TextField(
              key: const Key('event_search_field'),
              controller: _search,
              autofocus: false,
              decoration: const InputDecoration(
                hintText: 'イベント名を検索',
                prefixIcon: Icon(Icons.search),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scrollController,
              children: [
                for (final event in filtered)
                  CheckboxListTile(
                    key: Key('event_picker_item_${event.id}'),
                    title: Text(event.name),
                    subtitle: Text(_eventSubtitle(event)),
                    value: _selectedIds.contains(event.id),
                    onChanged: (_) => _toggleEvent(event),
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.s4,
                    ),
                  ),
                ListTile(
                  leading: const Icon(Icons.add_circle_outline),
                  title: const Text('+ 新しいイベントを作成'),
                  onTap: _onCreateNewTap,
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
                    key: const Key('event_picker_done'),
                    onPressed: _confirm,
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(44, 44),
                    ),
                    child: Text(
                      _selectedIds.isNotEmpty
                          ? '完了 (${_selectedIds.length})'
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
