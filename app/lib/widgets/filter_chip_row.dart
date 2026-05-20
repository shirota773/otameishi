import 'package:flutter/material.dart';

import '../models/event.dart';
import '../models/tag.dart';
import '../theme/app_theme.dart';
import '../usecases/search_cards_usecase.dart';

/// Horizontal scrollable row of filter chips: 「すべて」, 「イベント N」, 「タグ N」.
///
/// Reads [filters] from the parent and calls [onFiltersChanged] when the user
/// makes a selection in either bottom sheet.  The caller owns the provider
/// write-back so this widget remains testable without a full provider tree.
class FilterChipRow extends StatelessWidget {
  const FilterChipRow({
    super.key,
    required this.filters,
    required this.events,
    required this.tags,
    required this.onFiltersChanged,
  });

  final SearchFilters filters;
  final List<Event> events;
  final List<Tag> tags;
  final ValueChanged<SearchFilters> onFiltersChanged;

  @override
  Widget build(BuildContext context) {
    final eventCount = filters.eventIds.length;
    final tagCount = filters.tagIds.length;
    final hasAny = eventCount > 0 || tagCount > 0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: Row(
        children: [
          _ClearChip(
            active: !hasAny,
            onTap: hasAny
                ? () => onFiltersChanged(const SearchFilters())
                : null,
          ),
          const SizedBox(width: AppSpacing.s2),
          _FilterChipButton(
            label: eventCount > 0 ? 'イベント $eventCount' : 'イベント',
            active: eventCount > 0,
            semanticLabel: eventCount > 0
                ? 'イベントフィルタ（$eventCount件選択中）'
                : 'イベントで絞り込み',
            onTap: () => _openEventSheet(context),
          ),
          const SizedBox(width: AppSpacing.s2),
          _FilterChipButton(
            label: tagCount > 0 ? 'タグ $tagCount' : 'タグ',
            active: tagCount > 0,
            semanticLabel:
                tagCount > 0 ? 'タグフィルタ（$tagCount件選択中）' : 'タグで絞り込み',
            onTap: () => _openTagSheet(context),
          ),
        ],
      ),
    );
  }

  Future<void> _openEventSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SelectionSheet(
        title: 'イベントで絞り込み',
        items: events.map((e) => _SheetItem(id: e.id, label: e.name)).toList(),
        initialSelection: filters.eventIds,
      ),
    );
    if (selected != null) {
      onFiltersChanged(filters.copyWith(eventIds: selected));
    }
  }

  Future<void> _openTagSheet(BuildContext context) async {
    final selected = await showModalBottomSheet<Set<String>>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _SelectionSheet(
        title: 'タグで絞り込み',
        items: tags.map((t) => _SheetItem(id: t.id, label: t.name)).toList(),
        initialSelection: filters.tagIds,
      ),
    );
    if (selected != null) {
      onFiltersChanged(filters.copyWith(tagIds: selected));
    }
  }
}

// ─── Private chip widgets ──────────────────────────────────────────────────

class _ClearChip extends StatelessWidget {
  const _ClearChip({required this.active, this.onTap});

  final bool active;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: 'フィルタをすべてクリア',
      button: true,
      child: FilterChip(
        label: const Text('すべて'),
        selected: active,
        onSelected: (_) => onTap?.call(),
        showCheckmark: false,
        selectedColor: colorScheme.primaryContainer,
      ),
    );
  }
}

class _FilterChipButton extends StatelessWidget {
  const _FilterChipButton({
    required this.label,
    required this.active,
    required this.onTap,
    required this.semanticLabel,
  });

  final String label;
  final bool active;
  final VoidCallback onTap;
  final String semanticLabel;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Semantics(
      label: semanticLabel,
      button: true,
      child: FilterChip(
        label: Text(label),
        selected: active,
        onSelected: (_) => onTap(),
        showCheckmark: false,
        selectedColor: colorScheme.primaryContainer,
        avatar: const Icon(Icons.arrow_drop_down, size: 18),
      ),
    );
  }
}

// ─── Bottom sheet ──────────────────────────────────────────────────────────

class _SheetItem {
  const _SheetItem({required this.id, required this.label});

  final String id;
  final String label;
}

/// Generic multi-select bottom sheet used for both events and tags.
class _SelectionSheet extends StatefulWidget {
  const _SelectionSheet({
    required this.title,
    required this.items,
    required this.initialSelection,
  });

  final String title;
  final List<_SheetItem> items;
  final Set<String> initialSelection;

  @override
  State<_SelectionSheet> createState() => _SelectionSheetState();
}

class _SelectionSheetState extends State<_SelectionSheet> {
  late Set<String> _selected;

  @override
  void initState() {
    super.initState();
    _selected = Set.of(widget.initialSelection);
  }

  void _toggle(String id, bool checked) {
    setState(() {
      if (checked) {
        _selected = {..._selected, id};
      } else {
        _selected = _selected.difference({id});
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final applyLabel = _selected.isEmpty
        ? '適用'
        : '適用（${_selected.length}件）';

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.4,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        return Column(
          children: [
            _SheetHandle(),
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.s4,
                vertical: AppSpacing.s3,
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.items.isEmpty
                  ? const Center(child: Text('候補がありません'))
                  : ListView.builder(
                      controller: scrollController,
                      itemCount: widget.items.length,
                      itemBuilder: (_, i) {
                        final item = widget.items[i];
                        return CheckboxListTile(
                          title: Text(item.label),
                          value: _selected.contains(item.id),
                          onChanged: (v) => _toggle(item.id, v ?? false),
                          controlAffinity: ListTileControlAffinity.leading,
                        );
                      },
                    ),
            ),
            const Divider(height: 1),
            _SheetFooter(
              applyLabel: applyLabel,
              onClear: () {
                setState(() => _selected = {});
              },
              onApply: () => Navigator.of(context).pop(_selected),
            ),
          ],
        );
      },
    );
  }
}

class _SheetHandle extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.s3),
      child: Center(
        child: Container(
          width: 40,
          height: 4,
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.outlineVariant,
            borderRadius: BorderRadius.circular(AppRadius.full),
          ),
        ),
      ),
    );
  }
}

class _SheetFooter extends StatelessWidget {
  const _SheetFooter({
    required this.applyLabel,
    required this.onClear,
    required this.onApply,
  });

  final String applyLabel;
  final VoidCallback onClear;
  final VoidCallback onApply;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.s4,
        right: AppSpacing.s4,
        top: AppSpacing.s3,
        bottom: AppSpacing.s3 +
            MediaQuery.of(context).viewInsets.bottom +
            MediaQuery.of(context).padding.bottom,
      ),
      child: Row(
        children: [
          Semantics(
            label: '選択をクリア',
            button: true,
            child: TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(
                minimumSize: const Size(44, 44),
              ),
              child: const Text('選択をクリア'),
            ),
          ),
          const Spacer(),
          Semantics(
            label: applyLabel,
            button: true,
            child: ElevatedButton(
              onPressed: onApply,
              style: ElevatedButton.styleFrom(
                minimumSize: const Size(44, 44),
              ),
              child: Text(applyLabel),
            ),
          ),
        ],
      ),
    );
  }
}
