import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';
import 'package:table_calendar/table_calendar.dart';

import '../core/providers.dart';
import '../models/event.dart';
import '../theme/app_theme.dart';
import '../widgets/empty_state.dart';

// ---------------------------------------------------------------------------
// Debounce duration for search input (spec: 200ms)
// ---------------------------------------------------------------------------
const _kSearchDebounce = Duration(milliseconds: 200);

class EventListScreen extends ConsumerStatefulWidget {
  const EventListScreen({super.key});

  @override
  ConsumerState<EventListScreen> createState() => _EventListScreenState();
}

class _EventListScreenState extends ConsumerState<EventListScreen> {
  final _searchController = TextEditingController();
  Timer? _debounce;
  String _query = '';
  bool _showCalendar = false;
  DateTime _focusedDay = DateTime.now();
  DateTime? _selectedDay;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(_kSearchDebounce, () {
      if (mounted) setState(() => _query = value);
    });
  }

  void _clearSearch() {
    _searchController.clear();
    setState(() => _query = '');
  }

  List<Event> _applyFilter(List<Event> all) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty) return all;
    return all
        .where((e) => e.name.toLowerCase().contains(q))
        .toList(growable: false);
  }

  List<Event> _eventsForDay(List<Event> filtered, DateTime day) {
    return filtered
        .where((e) => e.date != null && isSameDay(e.date!, day))
        .toList(growable: false);
  }

  // ── Navigation helpers ────────────────────────────────────────────────────

  Future<void> _goToEditNew() async {
    final result = await Navigator.of(context).pushNamed('/event/edit');
    if (result != null) ref.invalidate(eventListProvider);
  }

  void _goToDetail(String id) {
    Navigator.of(context).pushNamed('/event', arguments: id);
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(eventListProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('イベント'),
        actions: [
          _ViewToggle(
            showCalendar: _showCalendar,
            onToggle: (v) => setState(() {
              _showCalendar = v;
              _selectedDay = null;
            }),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _goToEditNew,
        tooltip: 'イベントを追加',
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          _SearchBar(
            controller: _searchController,
            onChanged: _onSearchChanged,
            onClear: _clearSearch,
          ),
          Expanded(
            child: async.when(
              loading: () =>
                  const Center(child: CircularProgressIndicator()),
              error: (e, _) => Center(child: Text('エラー: $e')),
              data: (all) {
                final filtered = _applyFilter(all);
                if (_showCalendar) {
                  return _CalendarView(
                    events: filtered,
                    focusedDay: _focusedDay,
                    selectedDay: _selectedDay,
                    onDaySelected: (s, f) => setState(() {
                      _selectedDay = s;
                      _focusedDay = f;
                    }),
                    onFocusedDayChanged: (f) =>
                        setState(() => _focusedDay = f),
                    eventsForDay: (day) => _eventsForDay(filtered, day),
                    onEventTap: (e) => _goToDetail(e.id),
                  );
                }
                return _ListView(
                  events: filtered,
                  allEmpty: all.isEmpty,
                  onTap: (e) => _goToDetail(e.id),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Search bar
// ---------------------------------------------------------------------------

class _SearchBar extends StatelessWidget {
  const _SearchBar({
    required this.controller,
    required this.onChanged,
    required this.onClear,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.s4,
        vertical: AppSpacing.s2,
      ),
      child: SizedBox(
        height: 48,
        child: TextField(
          controller: controller,
          onChanged: onChanged,
          textAlignVertical: TextAlignVertical.center,
          decoration: InputDecoration(
            hintText: 'イベント名を検索',
            prefixIcon: const Icon(Icons.search),
            suffixIcon: ListenableBuilder(
              listenable: controller,
              builder: (ctx, _) => controller.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.close),
                      tooltip: 'クリア',
                      onPressed: onClear,
                    )
                  : const SizedBox.shrink(),
            ),
            filled: true,
            fillColor: theme.colorScheme.surfaceContainerHighest,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(AppRadius.md),
              borderSide: BorderSide.none,
            ),
            contentPadding: EdgeInsets.zero,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Toggle buttons
// ---------------------------------------------------------------------------

class _ViewToggle extends StatelessWidget {
  const _ViewToggle({required this.showCalendar, required this.onToggle});

  final bool showCalendar;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          label: 'リスト表示',
          child: IconButton(
            icon: Icon(
              showCalendar ? Icons.list_outlined : Icons.list,
            ),
            onPressed: () => onToggle(false),
          ),
        ),
        Semantics(
          label: 'カレンダー表示',
          child: IconButton(
            icon: Icon(
              showCalendar
                  ? Icons.calendar_month
                  : Icons.calendar_month_outlined,
            ),
            onPressed: () => onToggle(true),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// List view
// ---------------------------------------------------------------------------

class _ListView extends StatelessWidget {
  const _ListView({
    required this.events,
    required this.allEmpty,
    required this.onTap,
  });

  final List<Event> events;
  final bool allEmpty;
  final ValueChanged<Event> onTap;

  @override
  Widget build(BuildContext context) {
    if (allEmpty) {
      return const EmptyState(
        icon: Icons.event_outlined,
        message: 'まだイベントがありません',
        hint: 'カード保存時にイベントを紐付けられます',
      );
    }
    if (events.isEmpty) {
      return const EmptyState(
        icon: Icons.search_off,
        message: '該当するイベントがありません',
      );
    }
    final dateFmt = DateFormat.yMd('ja');
    return ListView.separated(
      padding: const EdgeInsets.all(AppSpacing.s4),
      itemCount: events.length,
      separatorBuilder: (context, index) => const Divider(),
      itemBuilder: (context, i) {
        final e = events[i];
        return ListTile(
          title: Text(e.name, style: Theme.of(context).textTheme.titleLarge),
          subtitle: e.date == null
              ? null
              : Text(
                  dateFmt.format(e.date!),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => onTap(e),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Calendar view
// ---------------------------------------------------------------------------

class _CalendarView extends StatelessWidget {
  const _CalendarView({
    required this.events,
    required this.focusedDay,
    required this.selectedDay,
    required this.onDaySelected,
    required this.onFocusedDayChanged,
    required this.eventsForDay,
    required this.onEventTap,
  });

  final List<Event> events;
  final DateTime focusedDay;
  final DateTime? selectedDay;
  final void Function(DateTime, DateTime) onDaySelected;
  final ValueChanged<DateTime> onFocusedDayChanged;
  final List<Event> Function(DateTime) eventsForDay;
  final ValueChanged<Event> onEventTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat.yMd('ja');

    final dayEvents =
        selectedDay != null ? eventsForDay(selectedDay!) : <Event>[];
    final hasAnyThisMonth = events.any((e) =>
        e.date != null &&
        e.date!.year == focusedDay.year &&
        e.date!.month == focusedDay.month);

    return Column(
      children: [
        TableCalendar<Event>(
          firstDay: DateTime.utc(2020, 1, 1),
          lastDay: DateTime.utc(2030, 12, 31),
          focusedDay: focusedDay,
          calendarFormat: CalendarFormat.month,
          availableCalendarFormats: const {CalendarFormat.month: '月'},
          selectedDayPredicate: (d) =>
              selectedDay != null && isSameDay(d, selectedDay!),
          eventLoader: eventsForDay,
          onDaySelected: onDaySelected,
          onPageChanged: onFocusedDayChanged,
          calendarStyle: CalendarStyle(
            markerDecoration: BoxDecoration(
              color: theme.colorScheme.primary,
              shape: BoxShape.circle,
            ),
          ),
          headerStyle: const HeaderStyle(
            formatButtonVisible: false,
            titleCentered: true,
          ),
        ),
        if (!hasAnyThisMonth)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.s4),
            child: Text(
              'この月にはイベントがありません',
              style: theme.textTheme.bodySmall,
            ),
          ),
        if (selectedDay != null && dayEvents.isNotEmpty)
          Expanded(
            child: ListView.separated(
              padding: const EdgeInsets.all(AppSpacing.s4),
              itemCount: dayEvents.length,
              separatorBuilder: (context, index) => const Divider(),
              itemBuilder: (context, i) {
                final e = dayEvents[i];
                return ListTile(
                  title: Text(
                    e.name,
                    style: theme.textTheme.titleLarge,
                  ),
                  subtitle: e.date != null
                      ? Text(
                          dateFmt.format(e.date!),
                          style: theme.textTheme.bodySmall,
                        )
                      : null,
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => onEventTap(e),
                );
              },
            ),
          ),
      ],
    );
  }
}
