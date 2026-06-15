import 'package:flutter/material.dart';

import '../../../calls/models/call_model.dart';
import 'lansweeper_report_call_tile.dart';

/// Προ-υπολογισμένα δεδομένα μίας γραμμής κλήσης για την εικονική λίστα.
class LansweeperReportCallRowData {
  const LansweeperReportCallRowData({
    required this.key,
    required this.call,
    required this.dateLabel,
    required this.durationLabel,
    required this.lansweeperState,
    this.ticketId,
    required this.notes,
    this.details,
    required this.durationSeconds,
  });

  final String key;
  final CallModel call;
  final String dateLabel;
  final String durationLabel;
  final String lansweeperState;
  final String? ticketId;
  final String notes;
  final String? details;
  final int durationSeconds;
}

sealed class _LansweeperReportListEntry {
  const _LansweeperReportListEntry(this.extent);

  final double extent;
}

final class _GroupGapEntry extends _LansweeperReportListEntry {
  const _GroupGapEntry() : super(12);
}

final class _GroupHeaderEntry extends _LansweeperReportListEntry {
  const _GroupHeaderEntry({
    required this.caller,
    required this.groupItems,
    required this.subtitleLabel,
  }) : super(_kGroupHeaderExtent);

  final String caller;
  final List<LansweeperReportCallRowData> groupItems;
  final String subtitleLabel;

  static const double _kGroupHeaderExtent = 64;
}

final class _GroupDividerEntry extends _LansweeperReportListEntry {
  const _GroupDividerEntry() : super(9);
}

final class _CallEntry extends _LansweeperReportListEntry {
  const _CallEntry({
    required this.item,
    required this.isLastInGroup,
  }) : super(isLastInGroup ? _kCallRowExtent + _kGroupBottomExtent : _kCallRowExtent);

  final LansweeperReportCallRowData item;
  final bool isLastInGroup;

  // 4 pad + ~28 meta + 2 gap + 42 σημειώσεις + ~4 rounding ≈ 80· buffer για badge/ticket.
  static const double _kCallRowExtent = 90;
  static const double _kGroupBottomExtent = 16;
}

String _flattenCacheKey(Map<String, List<LansweeperReportCallRowData>> grouped) {
  final buffer = StringBuffer();
  for (final entry in grouped.entries) {
    buffer.write(entry.key);
    buffer.write(':');
    for (final item in entry.value) {
      buffer
        ..write(item.key)
        ..write('/')
        ..write(item.lansweeperState)
        ..write('/')
        ..write(item.ticketId ?? '')
        ..write(';');
    }
    buffer.write('|');
  }
  return buffer.toString();
}

List<_LansweeperReportListEntry> _flattenGroupedCalls(
  Map<String, List<LansweeperReportCallRowData>> grouped,
  String Function(int totalSeconds) totalDurationLabel,
) {
  final entries = <_LansweeperReportListEntry>[];
  var groupIndex = 0;
  for (final entry in grouped.entries) {
    if (groupIndex > 0) {
      entries.add(const _GroupGapEntry());
    }
    final groupItems = entry.value;
    final groupSeconds = groupItems.fold<int>(
      0,
      (sum, item) => sum + item.durationSeconds,
    );
    entries.add(
      _GroupHeaderEntry(
        caller: entry.key,
        groupItems: groupItems,
        subtitleLabel:
            '${groupItems.length} κλήσεις • ${totalDurationLabel(groupSeconds)}',
      ),
    );
    entries.add(const _GroupDividerEntry());
    for (var i = 0; i < groupItems.length; i++) {
      entries.add(
        _CallEntry(
          item: groupItems[i],
          isLastInGroup: i == groupItems.length - 1,
        ),
      );
    }
    groupIndex++;
  }
  return entries;
}

/// Εικονικοποιημένη λίστα κλήσεων αναφοράς Lansweeper (ομαδοποίηση ανά καλούντα).
class LansweeperReportCallList extends StatefulWidget {
  const LansweeperReportCallList({
    required this.grouped,
    required this.selectedKeys,
    required this.totalDurationLabel,
    required this.ticketViewUrlTemplate,
    required this.isSyncLoading,
    required this.ticketLinkEnabled,
    required this.onToggleGroup,
    required this.onToggleItem,
    required this.onBadgePressed,
    super.key,
  });

  final Map<String, List<LansweeperReportCallRowData>> grouped;
  final Set<String> selectedKeys;
  final String Function(int totalSeconds) totalDurationLabel;
  final String ticketViewUrlTemplate;
  final bool isSyncLoading;
  final bool ticketLinkEnabled;
  final void Function(
    List<LansweeperReportCallRowData> groupItems,
    bool? checked,
  )
  onToggleGroup;
  final void Function(LansweeperReportCallRowData item, bool? checked)
  onToggleItem;
  final void Function(LansweeperReportCallRowData item) onBadgePressed;

  @override
  State<LansweeperReportCallList> createState() =>
      _LansweeperReportCallListState();
}

class _LansweeperReportCallListState extends State<LansweeperReportCallList> {
  final ScrollController _scrollController = ScrollController();
  String? _cachedFlatKey;
  List<_LansweeperReportListEntry>? _cachedFlatEntries;

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  List<_LansweeperReportListEntry> _flatEntries() {
    final cacheKey = _flattenCacheKey(widget.grouped);
    if (_cachedFlatKey == cacheKey && _cachedFlatEntries != null) {
      return _cachedFlatEntries!;
    }
    final entries = _flattenGroupedCalls(
      widget.grouped,
      widget.totalDurationLabel,
    );
    _cachedFlatKey = cacheKey;
    _cachedFlatEntries = entries;
    return entries;
  }

  bool? _groupCheckedValue(List<LansweeperReportCallRowData> items) {
    if (items.isEmpty) return false;
    final selectedCount = items
        .where((e) => widget.selectedKeys.contains(e.key))
        .length;
    if (selectedCount == 0) return false;
    if (selectedCount == items.length) return true;
    return null;
  }

  Widget _groupSurface({
    required ThemeData theme,
    required bool top,
    required bool bottom,
    required Widget child,
  }) {
    return Material(
      color: theme.cardColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: top ? const Radius.circular(12) : Radius.zero,
          bottom: bottom ? const Radius.circular(12) : Radius.zero,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );
  }

  Widget _buildEntry(_LansweeperReportListEntry entry) {
    final theme = Theme.of(context);
    return switch (entry) {
      _GroupGapEntry() => const SizedBox.shrink(),
      _GroupHeaderEntry(
        :final caller,
        :final groupItems,
        :final subtitleLabel,
      ) =>
        _groupSurface(
          theme: theme,
          top: true,
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
            child: CheckboxListTile(
              tristate: true,
              dense: true,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              value: _groupCheckedValue(groupItems),
              onChanged: (value) => widget.onToggleGroup(groupItems, value),
              title: Text(
                caller,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
              subtitle: Text(
                subtitleLabel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ),
      _GroupDividerEntry() => _groupSurface(
        theme: theme,
        top: false,
        bottom: false,
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 8),
          child: Divider(height: 8),
        ),
      ),
      _CallEntry(:final item, :final isLastInGroup) => _groupSurface(
        theme: theme,
        top: false,
        bottom: isLastInGroup,
        child: Padding(
          padding: EdgeInsets.fromLTRB(8, 0, 8, isLastInGroup ? 10 : 0),
          child: RepaintBoundary(
            child: LansweeperReportCallTile(
              checked: widget.selectedKeys.contains(item.key),
              onCheckedChanged: (value) => widget.onToggleItem(item, value),
              dateLabel: item.dateLabel,
              durationLabel: item.durationLabel,
              lansweeperState: item.lansweeperState,
              ticketId: item.ticketId,
              ticketViewUrlTemplate: widget.ticketViewUrlTemplate,
              notes: item.notes,
              details: item.details,
              isSyncLoading: widget.isSyncLoading,
              ticketLinkEnabled: widget.ticketLinkEnabled,
              fixedNotesHeight: true,
              onBadgePressed: () => widget.onBadgePressed(item),
            ),
          ),
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final entries = _flatEntries();
    return Scrollbar(
      controller: _scrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: ListView.builder(
        controller: _scrollController,
        itemCount: entries.length,
        addAutomaticKeepAlives: false,
        addRepaintBoundaries: false,
        itemBuilder: (context, index) {
          final entry = entries[index];
          return SizedBox(
            height: entry.extent,
            child: ClipRect(child: _buildEntry(entry)),
          );
        },
      ),
    );
  }
}
