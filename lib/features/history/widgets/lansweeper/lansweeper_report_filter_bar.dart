import 'package:flutter/material.dart';

import 'lansweeper_report_filter.dart';

class LansweeperReportFilterBar extends StatelessWidget {
  const LansweeperReportFilterBar({
    super.key,
    required this.selected,
    required this.counts,
    required this.hasAnyCallsInRange,
    required this.reportRangeTitle,
    required this.onSelect,
  });

  final LansweeperReportFilter selected;
  final LansweeperReportCategoryCounts? counts;
  final bool hasAnyCallsInRange;
  final String reportRangeTitle;
  final ValueChanged<LansweeperReportFilter> onSelect;

  static const String _noCallsInRangeFilterTooltip =
      'Δεν υπάρχουν κλήσεις στο τρέχον εύρος ημερομηνιών';

  String _labelWithCount(String baseLabel, LansweeperReportFilter filter) {
    final suffix =
        counts == null ? '' : ' (${counts!.forFilter(filter)})';
    return '$baseLabel$suffix';
  }

  bool _isCategoryChipActive(LansweeperReportFilter filter) {
    return hasAnyCallsInRange &&
        (counts == null || counts!.forFilter(filter) > 0);
  }

  Widget _reportFilterChip({
    required String label,
    required String tooltip,
    required bool selected,
    VoidCallback? onSelect,
  }) {
    return Tooltip(
      message: tooltip,
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: onSelect == null ? null : (_) => onSelect(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final disabledTooltip =
        '$_noCallsInRangeFilterTooltip («$reportRangeTitle»).';

    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        _reportFilterChip(
          label: _labelWithCount('Ακαταχώρητες', LansweeperReportFilter.unsentOnly),
          tooltip: hasAnyCallsInRange
              ? 'Οι κλήσεις που δεν έχουν καταχωρηθεί στο Lansweeper.'
              : disabledTooltip,
          selected: hasAnyCallsInRange &&
              selected == LansweeperReportFilter.unsentOnly,
          onSelect: _isCategoryChipActive(LansweeperReportFilter.unsentOnly)
              ? () => onSelect(LansweeperReportFilter.unsentOnly)
              : null,
        ),
        _reportFilterChip(
          label: _labelWithCount('Καταχωρημένες', LansweeperReportFilter.sentOnly),
          tooltip: hasAnyCallsInRange
              ? 'Οι κλήσεις που έχουν καταχωρηθεί στο Lansweeper. '
                    'Δεν είναι υποχρεωτικό αλλά επιθυμητό το αναγνωριστικό αιτήματος (ticket id).'
              : disabledTooltip,
          selected: hasAnyCallsInRange &&
              selected == LansweeperReportFilter.sentOnly,
          onSelect: _isCategoryChipActive(LansweeperReportFilter.sentOnly)
              ? () => onSelect(LansweeperReportFilter.sentOnly)
              : null,
        ),
        _reportFilterChip(
          label: _labelWithCount('Εξαιρεμένες', LansweeperReportFilter.excludedOnly),
          tooltip: hasAnyCallsInRange
              ? 'Οι κλήσεις που δεν υπάρχει λόγος να καταχωρηθούν στο Lansweeper.'
              : disabledTooltip,
          selected: hasAnyCallsInRange &&
              selected == LansweeperReportFilter.excludedOnly,
          onSelect: _isCategoryChipActive(LansweeperReportFilter.excludedOnly)
              ? () => onSelect(LansweeperReportFilter.excludedOnly)
              : null,
        ),
        _reportFilterChip(
          label: _labelWithCount('Αποτυχημένες', LansweeperReportFilter.failedOnly),
          tooltip: hasAnyCallsInRange
              ? 'Οι κλήσεις που απέτυχαν να καταχωρηθούν στο Lansweeper '
                    'με αυτόματο τρόπο.'
              : disabledTooltip,
          selected: hasAnyCallsInRange &&
              selected == LansweeperReportFilter.failedOnly,
          onSelect: _isCategoryChipActive(LansweeperReportFilter.failedOnly)
              ? () => onSelect(LansweeperReportFilter.failedOnly)
              : null,
        ),
        _reportFilterChip(
          label: _labelWithCount('Όλες', LansweeperReportFilter.all),
          tooltip: hasAnyCallsInRange
              ? 'Εμφάνιση όλων των κλήσεων.'
              : 'Εμφάνιση όλων των κλήσεων στο εύρος «$reportRangeTitle» (κενό).',
          selected: !hasAnyCallsInRange ||
              selected == LansweeperReportFilter.all,
          onSelect: hasAnyCallsInRange
              ? () => onSelect(LansweeperReportFilter.all)
              : null,
        ),
      ],
    );
  }
}
