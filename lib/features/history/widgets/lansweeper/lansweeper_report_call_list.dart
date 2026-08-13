import 'package:flutter/material.dart';

import '../../../calls/models/call_model.dart';
import 'lansweeper_call_summary.dart';
import 'lansweeper_report_call_tile.dart';
import 'lansweeper_report_row_metrics.dart';

/// Προ-υπολογισμένα δεδομένα μίας γραμμής κλήσης για την εικονική λίστα.
class LansweeperReportCallRowData {
  const LansweeperReportCallRowData({
    required this.key,
    required this.call,
    required this.dateLabel,
    required this.tooltip,
    required this.durationLabel,
    required this.lansweeperState,
    this.ticketId,
    required this.notes,
    required this.solution,
    required this.durationSeconds,
  });

  final String key;
  final CallModel call;
  final String dateLabel;

  /// Ό,τι δεν χωρά στη στενή κάρτα, ολόκληρο — στην υπόδειξη της χρονοσφραγίδας.
  final String tooltip;

  final String durationLabel;
  final String lansweeperState;
  final String? ticketId;
  final String notes;

  /// Απόσπασμα της Λύσης — κενό όταν η κλήση δεν έχει λυθεί ακόμη.
  final String solution;

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
    required this.phone,
    required this.groupItems,
    required this.subtitleLabel,
  }) : super(_kGroupHeaderExtent);

  final String caller;

  /// Το τηλέφωνο, όταν είναι κοινό σε όλες τις κλήσεις της ομάδας.
  final String? phone;

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
    required this.inlineMeta,
    required this.bodyHeight,
    required double extent,
  }) : super(extent);

  final LansweeperReportCallRowData item;
  final bool isLastInGroup;

  /// Ό,τι δεν κατάφερε να ανέβει στην κεφαλίδα: πάντα ο εξοπλισμός, και το
  /// τμήμα όταν η ομάδα δεν έχει κοινό.
  final String? inlineMeta;

  /// Ο χώρος του κειμένου — ο ίδιος αριθμός που γέννησε το [extent].
  final double bodyHeight;
}

String _flattenCacheKey(
  Map<String, List<LansweeperReportCallRowData>> grouped,
  double width,
) {
  final buffer = StringBuffer()
    // Το πλάτος καθορίζει σε πόσες γραμμές τυλίγεται κάθε κείμενο, άρα και το
    // ύψος κάθε κάρτας: αλλάζοντας μέγεθος το παράθυρο, οι μετρήσεις πρέπει να
    // ξαναγίνουν.
    ..write(width.round())
    ..write('#');
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
        ..write('/')
        ..write(item.notes.length)
        ..write('/')
        ..write(item.solution.length)
        // Τηλέφωνο και τμήμα κρίνουν τι ανεβαίνει στην κεφαλίδα: αν λείπουν από
        // το κλειδί, μια διόρθωση στον Κατάλογο αφήνει μπαγιάτικη κεφαλίδα.
        ..write('/')
        ..write(item.call.phoneText ?? '')
        ..write('/')
        ..write(item.call.departmentText ?? '')
        ..write('/')
        ..write(item.call.equipmentText ?? '')
        ..write(';');
    }
    buffer.write('|');
  }
  return buffer.toString();
}

/// Η μία γραμμή μεταδεδομένων που κρατά η κάρτα, ή `null` όταν δεν έχει τίποτα.
String? _inlineMetaFor(CallModel call, {required bool includeDepartment}) {
  final parts = <String>[];
  final equipment = (call.equipmentText ?? '').trim();
  if (equipment.isNotEmpty) parts.add(equipment);
  if (includeDepartment) {
    final department = (call.departmentText ?? '').trim();
    if (department.isNotEmpty) parts.add(department);
  }
  return parts.isEmpty ? null : parts.join(' · ');
}

/// Πόσο πλάτος μένει στο κείμενο μιας κάρτας μέσα σε λίστα πλάτους [listWidth].
///
/// Αφαιρούνται τα περιθώρια της ομάδας, τα περιθώρια της κάρτας και το πλαίσιο
/// επιλογής. Ο αριθμός τροφοδοτεί τη μέτρηση των γραμμών, οπότε μια απόκλιση
/// εδώ εμφανίζεται ως κάρτα λίγο ψηλότερη ή λίγο κοντύτερη απ' όσο χρειάζεται.
double _textWidthFor(double listWidth) {
  const groupPadding = 8.0 * 2;
  const tilePadding = 4.0 * 2;
  const checkboxWidth = 40.0;
  final width = listWidth - groupPadding - tilePadding - checkboxWidth;
  return width < 0 ? 0 : width;
}

List<_LansweeperReportListEntry> _flattenGroupedCalls(
  Map<String, List<LansweeperReportCallRowData>> grouped,
  String Function(int totalSeconds) totalDurationLabel,
  double textWidth,
  TextStyle bodyStyle,
  TextScaler textScaler,
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
    final calls = groupItems.map((row) => row.call);
    final phone = LansweeperCallSummary.sharedValue(
      calls,
      (call) => call.phoneText,
    );
    final department = LansweeperCallSummary.sharedValue(
      calls,
      (call) => call.departmentText,
    );
    final countLabel =
        '${groupItems.length} κλήσεις • ${totalDurationLabel(groupSeconds)}';
    entries.add(
      _GroupHeaderEntry(
        caller: entry.key,
        phone: phone,
        groupItems: groupItems,
        subtitleLabel: department == null
            ? countLabel
            : '$department · $countLabel',
      ),
    );
    entries.add(const _GroupDividerEntry());
    for (var i = 0; i < groupItems.length; i++) {
      final row = groupItems[i];
      final isLast = i == groupItems.length - 1;
      final bodyHeight = LansweeperReportRowMetrics.bodyHeight(
        issue: row.notes,
        solution: row.solution,
        style: bodyStyle,
        maxWidth: textWidth,
        textScaler: textScaler,
      );
      entries.add(
        _CallEntry(
          item: row,
          isLastInGroup: isLast,
          // Το τμήμα κατεβαίνει στην κάρτα μόνο όταν η ομάδα δεν έχει κοινό —
          // αλλιώς θα λεγόταν δύο φορές, δύο γραμμές πιο κάτω.
          inlineMeta: _inlineMetaFor(
            row.call,
            includeDepartment: department == null,
          ),
          bodyHeight: bodyHeight,
          extent: LansweeperReportRowMetrics.rowExtent(
            bodyHeight: bodyHeight,
            isLastInGroup: isLast,
          ),
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

  List<_LansweeperReportListEntry> _flatEntries(
    BuildContext context,
    double listWidth,
  ) {
    final cacheKey = _flattenCacheKey(widget.grouped, listWidth);
    if (_cachedFlatKey == cacheKey && _cachedFlatEntries != null) {
      return _cachedFlatEntries!;
    }
    // Το ίδιο στυλ που χρησιμοποιεί η κάρτα για το κείμενό της — αλλιώς η
    // μέτρηση θα αφορούσε άλλα γράμματα από αυτά που θα ζωγραφιστούν.
    final bodyStyle =
        Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.25) ??
        const TextStyle(height: 1.25);
    final entries = _flattenGroupedCalls(
      widget.grouped,
      widget.totalDurationLabel,
      _textWidthFor(listWidth),
      bodyStyle,
      MediaQuery.textScalerOf(context),
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
        :final phone,
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
              title: Row(
                children: [
                  Flexible(
                    child: Text(
                      caller,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  ),
                  if (phone != null) ...[
                    const SizedBox(width: 8),
                    Icon(
                      Icons.call_outlined,
                      size: 13,
                      color: theme.textTheme.bodySmall?.color,
                    ),
                    const SizedBox(width: 3),
                    Text(phone, style: theme.textTheme.bodySmall),
                  ],
                ],
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
      _CallEntry(
        :final item,
        :final isLastInGroup,
        :final inlineMeta,
        :final bodyHeight,
      ) =>
        _groupSurface(
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
              tooltip: item.tooltip,
              inlineMeta: inlineMeta,
              durationLabel: item.durationLabel,
              lansweeperState: item.lansweeperState,
              ticketId: item.ticketId,
              ticketViewUrlTemplate: widget.ticketViewUrlTemplate,
              notes: item.notes,
              solution: item.solution,
              isSyncLoading: widget.isSyncLoading,
              ticketLinkEnabled: widget.ticketLinkEnabled,
              bodyHeight: bodyHeight,
              onBadgePressed: () => widget.onBadgePressed(item),
            ),
          ),
        ),
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final entries = _flatEntries(context, constraints.maxWidth);
        return Scrollbar(
          controller: _scrollController,
          thumbVisibility: true,
          trackVisibility: true,
          child: ListView.builder(
            controller: _scrollController,
            itemCount: entries.length,
            addAutomaticKeepAlives: false,
            addRepaintBoundaries: false,
            // Το ύψος κάθε στοιχείου δίνεται **πριν** χτιστεί, ώστε ο κύλινδρος
            // να ξέρει από το πρώτο καρέ πόσο μακρύ είναι το περιεχόμενο. Χωρίς
            // αυτό, ανόμοια ύψη σε τεμπέλικη λίστα κάνουν τη μπάρα κύλισης να
            // μεταπηδά στο σύρσιμο, γιατί το συνολικό μήκος μαντεύεται από τον
            // μέσο όρο όσων έχουν ήδη εμφανιστεί.
            itemExtentBuilder: (index, dimensions) => entries[index].extent,
            itemBuilder: (context, index) =>
                ClipRect(child: _buildEntry(entries[index])),
          ),
        );
      },
    );
  }
}
