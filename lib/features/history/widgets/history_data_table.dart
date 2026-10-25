import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../../core/utils/call_duration_format.dart';
import '../../../core/utils/history_entity_display_utils.dart';
import '../../../core/widgets/compact_tooltip.dart';
import '../../../core/widgets/ellipsis_tooltip_text.dart';
import '../../../core/widgets/keyboard_row_navigation.dart';
import '../../../core/widgets/row_navigation_logic.dart';
import '../../calls/models/call_refined_source.dart';
import '../models/lansweeper_sync_state.dart';
import '../providers/history_provider.dart';
import '../providers/history_table_zoom_provider.dart';
import '../services/lansweeper_state_actions.dart';
import '../utils/history_call_row_sort.dart';
import 'call_delete_dialog.dart';
import 'call_edit_dialog.dart';
import 'call_provenance_icon.dart';
import 'history_deleted_entity_text.dart';

/// Πίνακας γραμμών ιστορικού (ημ/νία & ώρα, καλούντας, τηλέφωνο, τμήμα, εξοπλισμός, κατηγορία, σημειώσεις, διάρκεια).
class HistoryDataTable extends ConsumerStatefulWidget {
  const HistoryDataTable({super.key, required this.rows});

  final List<Map<String, dynamic>> rows;

  @override
  ConsumerState<HistoryDataTable> createState() => _HistoryDataTableState();
}

class _HistoryDataTableState extends ConsumerState<HistoryDataTable> {
  /// Βασικά πλάτη στηλών (checkbox, ημ/νία, καλούντας, τηλέφωνο, τμήμα,
  /// εξοπλισμός, κατηγορία, σημειώσεις, διάρκεια, συνδέσεις, ενέργειες).
  static const List<double> _baseColumnWidths = [
    50,
    130,
    160,
    110,
    140,
    130,
    140,
    220,
    90,
    80,
    // Τρία χειριστήρια πλέον: κατάσταση Lansweeper, επεξεργασία, διαγραφή.
    150,
  ];

  static const List<String> _dataColumnLabels = [
    'Ημ/νία & Ώρα',
    'Καλούντας',
    'Τηλέφωνο',
    'Τμήμα',
    'Εξοπλισμός',
    'Κατηγορία',
    'Περιγραφή',
    'Διάρκεια',
    'Συνδέσεις',
  ];

  /// Δείκτης της στήλης ενεργειών — τελευταία, μετά τις στήλες δεδομένων.
  static const int _actionsColumnIndex = 10;

  late final ScrollController _horizontalScrollController;
  late final ScrollController _verticalScrollController;
  int? _hoveredRowIndex;

  /// Η κλήση που ακούει τα πλήκτρα. Κρατιέται ως id και όχι ως θέση, ώστε να
  /// μένει στην ίδια κλήση όταν αλλάζει η ταξινόμηση ή ανανεώνεται η λίστα.
  int? _focusedCallId;

  int? _rowId(Map<String, dynamic> row) => row['id'] as int?;

  void _toggleSelection(int callId, bool selected) {
    final current = ref.read(historySelectedCallIdsProvider);
    final next = <int>{...current};
    if (selected) {
      next.add(callId);
    } else {
      next.remove(callId);
    }
    ref.read(historySelectedCallIdsProvider.notifier).setAll(next);
  }

  /// Φέρνει τη γραμμή [index] στο ορατό τμήμα. Οι γραμμές έχουν όλες το ίδιο
  /// ύψος, άρα η θέση τους υπολογίζεται χωρίς να είναι χτισμένες.
  void _revealRow(int index, double rowExtent) {
    if (!_verticalScrollController.hasClients) return;
    final position = _verticalScrollController.position;
    final target = scrollOffsetRevealingRow(
      index: index,
      rowExtent: rowExtent,
      viewportExtent: position.viewportDimension,
      currentOffset: position.pixels,
    ).clamp(position.minScrollExtent, position.maxScrollExtent);
    if (target != position.pixels) _verticalScrollController.jumpTo(target);
  }

  /// Delete: με τικ, η μαζική διαγραφή των τσεκαρισμένων· χωρίς τικ, ο
  /// διάλογος διαγραφής της γραμμής που ακούει τα πλήκτρα. Επιβεβαίωση πάντα,
  /// όπως με τα κουμπιά.
  void _deleteFromKeyboard(
    Map<String, dynamic>? focusedRow,
    Set<int> visibleSelectedIds,
  ) {
    if (visibleSelectedIds.isNotEmpty) {
      showCallBulkDeleteDialog(context, callIds: visibleSelectedIds.toList());
      return;
    }
    final callId = focusedRow == null ? null : _rowId(focusedRow);
    if (focusedRow == null || callId == null) return;
    showCallDeleteDialog(
      context,
      callId: callId,
      callerId: focusedRow['caller_id'] as int?,
      equipmentCode: historyRowText(focusedRow['equipment_code']),
    );
  }

  @override
  void initState() {
    super.initState();
    _horizontalScrollController = ScrollController();
    _verticalScrollController = ScrollController();
  }

  @override
  void dispose() {
    _horizontalScrollController.dispose();
    _verticalScrollController.dispose();
    super.dispose();
  }

  static final DateFormat _callDateTimeDisplay = DateFormat('dd-MM-yyyy HH:mm');

  /// Εμφάνιση ως "ηη-μμ-εεεε ωω:λλ" (dd-MM-yyyy HH:mm).
  String _formatCallDateTimeDisplay(Map<String, dynamic> row) {
    final dt = parseHistoryCallDateTime(row);
    if (dt != null) {
      return _callDateTimeDisplay.format(dt);
    }
    final raw = '${historyRowText(row['date'])} ${historyRowText(row['time'])}'
        .trim();
    return raw.isEmpty ? '—' : raw;
  }

  String _formatDuration(dynamic duration) =>
      formatCallDurationSeconds(duration);

  List<double> _scaledColumnWidths(double zoomLevel) =>
      _baseColumnWidths.map((w) => w * zoomLevel).toList();

  double _totalTableWidth(double zoomLevel) =>
      _scaledColumnWidths(zoomLevel).fold(0.0, (a, b) => a + b);

  void _onSortHeaderTap(HistorySortColumn column) =>
      ref.read(historySortProvider.notifier).toggle(column);

  Widget _headerCell({
    required double width,
    required double horizontalPadding,
    required Widget child,
    VoidCallback? onTap,
  }) {
    final theme = Theme.of(context);
    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
      child: child,
    );
    if (onTap == null) {
      return SizedBox(width: width, child: content);
    }
    return SizedBox(
      width: width,
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          onTap: onTap,
          hoverColor: theme.colorScheme.onSurface.withValues(alpha: 0.04),
          child: content,
        ),
      ),
    );
  }

  Widget _buildHeaderRow({
    required ThemeData theme,
    required double zoomLevel,
    required List<double> columnWidths,
    required double headingRowHeight,
    required double horizontalPadding,
    required bool allVisibleSelected,
    required Set<int> visibleIds,
    required Set<int> selectedCallIds,
    required HistorySortModel sort,
  }) {
    final headingStyle = theme.textTheme.titleSmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: theme.colorScheme.onSurface,
    );

    Widget sortableLabel(HistorySortColumn column, String label) {
      final isActive = sort.column == column;
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Flexible(
            child: Text(
              label,
              style: headingStyle,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (isActive) ...[
            const SizedBox(width: 4),
            Icon(
              sort.ascending ? Icons.arrow_upward : Icons.arrow_downward,
              size: 16 * zoomLevel,
              color: theme.colorScheme.primary,
            ),
          ],
        ],
      );
    }

    final cells = <Widget>[
      _headerCell(
        width: columnWidths[0],
        horizontalPadding: horizontalPadding,
        child: Transform.scale(
          scale: zoomLevel.clamp(0.85, 1.4),
          child: Checkbox(
            value: allVisibleSelected,
            onChanged: (v) {
              final target = v == true;
              final next = <int>{...selectedCallIds};
              if (target) {
                next.addAll(visibleIds);
              } else {
                next.removeAll(visibleIds);
              }
              ref.read(historySelectedCallIdsProvider.notifier).setAll(next);
            },
          ),
        ),
      ),
      for (var i = 0; i < _dataColumnLabels.length; i++)
        _headerCell(
          width: columnWidths[i + 1],
          horizontalPadding: horizontalPadding,
          onTap: () => _onSortHeaderTap(HistorySortColumn.values[i]),
          child: sortableLabel(
            HistorySortColumn.values[i],
            _dataColumnLabels[i],
          ),
        ),
      _headerCell(
        width: columnWidths[_actionsColumnIndex],
        horizontalPadding: horizontalPadding,
        child: Text('Ενέργειες', style: headingStyle),
      ),
    ];

    return Container(
      height: headingRowHeight,
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
        border: Border(
          bottom: BorderSide(color: theme.dividerColor.withValues(alpha: 0.6)),
        ),
      ),
      child: Row(children: cells),
    );
  }

  Widget _dataCell({
    required double width,
    required double horizontalPadding,
    required Widget child,
  }) {
    return SizedBox(
      width: width,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: horizontalPadding),
        child: Align(alignment: Alignment.centerLeft, child: child),
      ),
    );
  }

  Widget _buildDataRow({
    required Map<String, dynamic> row,
    required int rowIndex,
    required ThemeData theme,
    required double zoomLevel,
    required List<double> columnWidths,
    required double dataRowHeight,
    required double horizontalPadding,
    required Set<int> selectedCallIds,
  }) {
    final callId = _rowId(row);
    final isSelected = callId != null && selectedCallIds.contains(callId);
    final isHovered = _hoveredRowIndex == rowIndex;
    final isFocused = callId != null && callId == _focusedCallId;

    Color? rowColor;
    if (isFocused) {
      rowColor = keyboardFocusedRowColor(context);
    } else if (isSelected) {
      rowColor = theme.colorScheme.primaryContainer.withValues(alpha: 0.35);
    } else if (isHovered) {
      rowColor = theme.colorScheme.surfaceContainerHighest.withValues(
        alpha: 0.45,
      );
    }

    final dateTime = _formatCallDateTimeDisplay(row);
    final user = historyCallerDisplay(row);
    final callerDeleted = historyEntityIsDeleted(row['caller_is_deleted']);
    final phone = row['user_phone']?.toString().trim() ?? '—';
    final department = historyRowText(row['user_department']);
    final equipment = historyRowText(row['equipment_code']);
    final equipmentDeleted = historyEntityIsDeleted(
      row['equipment_is_deleted'],
    );
    final category = historyRowText(row['category']);
    final categoryDeleted = historyEntityIsDeleted(row['category_is_deleted']);
    final issue = historyRowText(row['issue']);
    final provenance = CallRefinedSource.provenanceLabel(
      source: row['refined_source'] as String?,
      refinedAt: row['refined_at'] as String?,
    );
    final durationStr = _formatDuration(row['duration']);

    final bodyStyle = theme.textTheme.bodyMedium;

    return MouseRegion(
      onEnter: (_) => setState(() => _hoveredRowIndex = rowIndex),
      onExit: (_) {
        if (_hoveredRowIndex == rowIndex) {
          setState(() => _hoveredRowIndex = null);
        }
      },
      child: GestureDetector(
        // Ένα κλικ στη γραμμή τη δίνει στα πλήκτρα· τα τικ και τα κουμπιά της
        // κρατούν τη δική τους δουλειά.
        onTap: callId == null
            ? null
            : () => setState(() => _focusedCallId = callId),
        child: Container(
          height: dataRowHeight,
          decoration: BoxDecoration(
            color: rowColor,
            border: Border(
              bottom: BorderSide(
                color: theme.dividerColor.withValues(alpha: 0.35),
              ),
            ),
          ),
          // Η λωρίδα της εστίασης ζωγραφίζεται από πάνω: ως περίγραμμα θα
          // έτρωγε πλάτος από τις στήλες, που έχουν σταθερό φάρδος.
          foregroundDecoration: isFocused
              ? BoxDecoration(
                  border: Border(
                    left: BorderSide(
                      color: theme.colorScheme.primary,
                      width: 3,
                    ),
                  ),
                )
              : null,
          child: Row(
            children: [
              _dataCell(
                width: columnWidths[0],
                horizontalPadding: horizontalPadding,
                child: Transform.scale(
                  scale: zoomLevel.clamp(0.85, 1.4),
                  child: Checkbox(
                    value: isSelected,
                    onChanged: callId == null
                        ? null
                        : (value) => _toggleSelection(callId, value == true),
                  ),
                ),
              ),
              _dataCell(
                width: columnWidths[1],
                horizontalPadding: horizontalPadding,
                child: Text(dateTime, style: bodyStyle),
              ),
              _dataCell(
                width: columnWidths[2],
                horizontalPadding: horizontalPadding,
                child: HistoryDeletedEntityText(
                  text: user,
                  isDeleted: callerDeleted && user != '—',
                  style: bodyStyle,
                ),
              ),
              _dataCell(
                width: columnWidths[3],
                horizontalPadding: horizontalPadding,
                child: Text(phone.isEmpty ? '—' : phone, style: bodyStyle),
              ),
              _dataCell(
                width: columnWidths[4],
                horizontalPadding: horizontalPadding,
                child: EllipsisTooltipText(
                  text: department.isEmpty ? '—' : department,
                  style: bodyStyle,
                ),
              ),
              _dataCell(
                width: columnWidths[5],
                horizontalPadding: horizontalPadding,
                child: HistoryDeletedEntityText(
                  text: equipment.isEmpty ? '—' : equipment,
                  isDeleted: equipmentDeleted && equipment.isNotEmpty,
                  style: bodyStyle,
                ),
              ),
              _dataCell(
                width: columnWidths[6],
                horizontalPadding: horizontalPadding,
                child: HistoryDeletedEntityText(
                  text: category.isEmpty ? '—' : category,
                  isDeleted: categoryDeleted && category.isNotEmpty,
                  style: bodyStyle,
                ),
              ),
              _dataCell(
                width: columnWidths[7],
                horizontalPadding: horizontalPadding,
                // Το σχήμα του εικονιδίου λέει ποιανού είναι τα λόγια —
                // χειρόγραφο, από ΤΝ, ή από ΤΝ και πειραγμένο — και το tooltip
                // τα ίδια με λόγια, μαζί με το πότε.
                child: provenance.isEmpty
                    ? EllipsisTooltipText(
                        text: issue.isEmpty ? '—' : issue,
                        style: bodyStyle,
                      )
                    : Row(
                        children: [
                          Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Tooltip(
                              message: provenance,
                              child: CallProvenanceIcon(
                                source: row['refined_source'] as String?,
                              ),
                            ),
                          ),
                          Expanded(
                            child: EllipsisTooltipText(
                              text: issue.isEmpty ? '—' : issue,
                              style: bodyStyle,
                            ),
                          ),
                        ],
                      ),
              ),
              _dataCell(
                width: columnWidths[8],
                horizontalPadding: horizontalPadding,
                child: Text(durationStr, style: bodyStyle),
              ),
              _dataCell(
                width: columnWidths[9],
                horizontalPadding: horizontalPadding,
                child: _CallLinkBadges(
                  hasTask: historyFlagIsSet(row['has_open_task']),
                  lansweeperState: historyRowText(row['lansweeper_state']),
                  ticketId: historyRowText(row['lansweeper_ticket_id']),
                ),
              ),
              _dataCell(
                width: columnWidths[_actionsColumnIndex],
                horizontalPadding: horizontalPadding,
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _LansweeperRowMenu(
                        callId: callId,
                        currentState: historyRowText(row['lansweeper_state']),
                        ticketId: historyRowText(row['lansweeper_ticket_id']),
                      ),
                      IconButton(
                        tooltip: 'Επεξεργασία',
                        visualDensity: VisualDensity.compact,
                        onPressed: callId == null
                            ? null
                            : () => showCallEditDialog(context, callId: callId),
                        icon: const Icon(Icons.edit_outlined),
                      ),
                      IconButton(
                        tooltip: 'Διαγραφή',
                        visualDensity: VisualDensity.compact,
                        onPressed: callId == null
                            ? null
                            : () => showCallDeleteDialog(
                                context,
                                callId: callId,
                                callerId: row['caller_id'] as int?,
                                equipmentCode: historyRowText(
                                  row['equipment_code'],
                                ),
                              ),
                        icon: Icon(
                          Icons.delete_outline,
                          color: theme.colorScheme.error,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zoomLevel = ref.watch(historyTableZoomProvider);
    final selectedCallIds = ref.watch(historySelectedCallIdsProvider);
    final sort = ref.watch(historySortProvider);
    final rowsToShow = sort.column != null
        ? sortHistoryCallRows(widget.rows, sort.column!.index, sort.ascending)
        : widget.rows;
    final visibleIds = rowsToShow.map(_rowId).whereType<int>().toSet();
    final allVisibleSelected =
        visibleIds.isNotEmpty && visibleIds.every(selectedCallIds.contains);

    final columnWidths = _scaledColumnWidths(zoomLevel);
    final tableWidth = _totalTableWidth(zoomLevel);
    final headingRowHeight = 56.0 * zoomLevel;
    final dataRowHeight = 48.0 * zoomLevel;
    final horizontalPadding = 12.0 * zoomLevel;

    final focusedIndex = rowsToShow.indexWhere(
      (row) => _focusedCallId != null && _rowId(row) == _focusedCallId,
    );
    final focusedRow = focusedIndex < 0 ? null : rowsToShow[focusedIndex];
    final visibleSelectedIds = selectedCallIds
        .where(visibleIds.contains)
        .toSet();

    return LayoutBuilder(
      builder: (context, constraints) => KeyboardRowNavigation(
        rowCount: rowsToShow.length,
        focusedRowIndex: focusedIndex < 0 ? null : focusedIndex,
        onFocusRow: (i) =>
            setState(() => _focusedCallId = _rowId(rowsToShow[i])),
        pageStep: rowsFittingViewport(
          viewportExtent: constraints.maxHeight - headingRowHeight,
          rowExtent: dataRowHeight,
        ),
        onRevealRow: (i, {required movingDown}) => _revealRow(i, dataRowHeight),
        onOpen: (_) {
          final callId = focusedRow == null ? null : _rowId(focusedRow);
          if (callId != null) showCallEditDialog(context, callId: callId);
        },
        onToggleRow: (i) {
          final callId = _rowId(rowsToShow[i]);
          if (callId != null) {
            _toggleSelection(callId, !selectedCallIds.contains(callId));
          }
        },
        onDelete: (_) => _deleteFromKeyboard(focusedRow, visibleSelectedIds),
        child: _buildTable(
          theme: theme,
          zoomLevel: zoomLevel,
          rowsToShow: rowsToShow,
          columnWidths: columnWidths,
          tableWidth: tableWidth,
          headingRowHeight: headingRowHeight,
          dataRowHeight: dataRowHeight,
          horizontalPadding: horizontalPadding,
          allVisibleSelected: allVisibleSelected,
          visibleIds: visibleIds,
          selectedCallIds: selectedCallIds,
          sort: sort,
        ),
      ),
    );
  }

  Widget _buildTable({
    required ThemeData theme,
    required double zoomLevel,
    required List<Map<String, dynamic>> rowsToShow,
    required List<double> columnWidths,
    required double tableWidth,
    required double headingRowHeight,
    required double dataRowHeight,
    required double horizontalPadding,
    required bool allVisibleSelected,
    required Set<int> visibleIds,
    required Set<int> selectedCallIds,
    required HistorySortModel sort,
  }) {
    return Scrollbar(
      controller: _horizontalScrollController,
      thumbVisibility: true,
      trackVisibility: true,
      child: SingleChildScrollView(
        controller: _horizontalScrollController,
        scrollDirection: Axis.horizontal,
        child: SizedBox(
          width: tableWidth,
          child: MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(zoomLevel)),
            child: IconTheme(
              data: IconThemeData(size: 24.0 * zoomLevel),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeaderRow(
                    theme: theme,
                    zoomLevel: zoomLevel,
                    columnWidths: columnWidths,
                    headingRowHeight: headingRowHeight,
                    horizontalPadding: horizontalPadding,
                    allVisibleSelected: allVisibleSelected,
                    visibleIds: visibleIds,
                    selectedCallIds: selectedCallIds,
                    sort: sort,
                  ),
                  Expanded(
                    child: Scrollbar(
                      controller: _verticalScrollController,
                      thumbVisibility: true,
                      trackVisibility: true,
                      child: ListView.builder(
                        controller: _verticalScrollController,
                        itemCount: rowsToShow.length,
                        itemExtent: dataRowHeight,
                        itemBuilder: (context, index) => _buildDataRow(
                          row: rowsToShow[index],
                          rowIndex: index,
                          theme: theme,
                          zoomLevel: zoomLevel,
                          columnWidths: columnWidths,
                          dataRowHeight: dataRowHeight,
                          horizontalPadding: horizontalPadding,
                          selectedCallIds: selectedCallIds,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Μενού αλλαγής κατάστασης Lansweeper, στη στήλη ενεργειών της γραμμής.
///
/// Αφορά **μόνο τη δική του κλήση**, ακόμη κι όταν υπάρχουν πολλές επιλεγμένες
/// — ίδια συμπεριφορά με την επεξεργασία και την ατομική διαγραφή δίπλα του.
/// Μαζική αλλαγή γίνεται από τη μπάρα των επιλεγμένων, όχι από τη γραμμή.
class _LansweeperRowMenu extends ConsumerWidget {
  const _LansweeperRowMenu({
    required this.callId,
    required this.currentState,
    required this.ticketId,
  });

  final int? callId;
  final String currentState;
  final String ticketId;

  Future<void> _apply(
    BuildContext context,
    WidgetRef ref,
    String targetState,
  ) async {
    final id = callId;
    if (id == null) return;
    // Ο messenger κρατιέται ΠΡΙΝ από τα await: οι διάλογοι που ακολουθούν
    // μπορεί να αφήσουν πίσω τους νεκρό context.
    final messenger = ScaffoldMessenger.of(context);
    final message = await LansweeperStateActions.apply(
      context,
      ref,
      callId: id,
      currentState: currentState,
      storedTicketId: ticketId,
      targetState: targetState,
    );
    // `null` σημαίνει πλέον ΜΟΝΟ «ακύρωσε ο χρήστης». Η αποτυχία έρχεται με
    // μήνυμα και τεχνική αναφορά, όπως και στην Αναφορά Lansweeper — όσο τα
    // δύο μοιράζονταν το ίδιο `null`, μια αποτυχημένη εγγραφή περνούσε χωρίς
    // να το μάθει ποτέ κανείς.
    if (message == null) return;
    messenger.showSnackBar(
      SnackBar(
        content: Text(message.text),
        duration: Duration(seconds: message.isFailure ? 8 : 4),
        // Το μήνυμα φεύγει μόνο του: χωρίς ρητή δήλωση, το Flutter βαφτίζει
        // «μόνιμο» κάθε SnackBar με κουμπί — και μπλοκάρει την ουρά, οπότε
        // κανένα επόμενο μήνυμα δεν εμφανίζεται ποτέ.
        persist: false,
        action: message.isFailure
            ? SnackBarAction(
                label: 'Αντιγραφή',
                onPressed: () => unawaited(
                  Clipboard.setData(
                    ClipboardData(text: message.failureReport ?? message.text),
                  ),
                ),
              )
            : null,
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final targets = LansweeperStateActions.availableTargets(currentState);
    // Η υπόδειξη περνά από το CompactTooltip (πρότυπο)· το ενσωματωμένο
    // tooltip του PopupMenuButton σιγεί με κενό κείμενο.
    return CompactTooltip(
      message:
          'Lansweeper: ${LansweeperSyncState.label(currentState)} — '
          'αλλαγή κατάστασης',
      child: PopupMenuButton<String>(
        enabled: callId != null && targets.isNotEmpty,
        tooltip: '',
        icon: const Icon(Icons.confirmation_number_outlined),
        iconSize: 20,
        padding: EdgeInsets.zero,
        onSelected: (target) => unawaited(_apply(context, ref, target)),
        itemBuilder: (context) => [
          for (final target in targets)
            PopupMenuItem(
              value: target,
              child: Text(LansweeperStateActions.actionLabel(target)),
            ),
        ],
      ),
    );
  }
}

/// Ενδείξεις «ουράς» μιας κλήσης: συνδεδεμένη εκκρεμότητα ή κατάσταση
/// Lansweeper.
///
/// Είναι σήματα, όχι κουμπιά: απαντούν «τι άφησε πίσω της αυτή η κλήση» με μια
/// ματιά στη λίστα. Οι αλλαγές γίνονται από το μενού της στήλης ενεργειών.
///
/// Η ακαταχώρητη δεν παίρνει εικονίδιο επίτηδες: είναι η αφετηρία κάθε κλήσης
/// και η πλειοψηφία της λίστας — ένα σήμα σε κάθε γραμμή δεν θα σήμαινε τίποτα.
class _CallLinkBadges extends StatelessWidget {
  const _CallLinkBadges({
    required this.hasTask,
    required this.lansweeperState,
    required this.ticketId,
  });

  final bool hasTask;
  final String lansweeperState;
  final String ticketId;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final state = LansweeperSyncState.normalize(lansweeperState);
    final showsState = state != LansweeperSyncState.unsent;

    if (!hasTask && !showsState) {
      return Text(
        '—',
        style: theme.textTheme.bodySmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      );
    }

    final (icon, color) = switch (state) {
      LansweeperSyncState.sent => (
        Icons.confirmation_number,
        theme.colorScheme.tertiary,
      ),
      LansweeperSyncState.excluded => (
        Icons.remove_circle_outline,
        theme.colorScheme.onSurfaceVariant,
      ),
      LansweeperSyncState.failed => (
        Icons.error_outline,
        theme.colorScheme.error,
      ),
      _ => (Icons.confirmation_number_outlined, theme.colorScheme.tertiary),
    };
    final ticket = ticketId.trim();
    final stateMessage = ticket.isEmpty
        ? 'Lansweeper: ${LansweeperSyncState.label(state)}'
        : 'Lansweeper: ${LansweeperSyncState.label(state)} — αίτημα #$ticket';

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (hasTask)
          CompactTooltip(
            message: 'Συνδεδεμένη εκκρεμότητα',
            child: Icon(
              Icons.task_alt,
              size: 18,
              color: theme.colorScheme.primary,
            ),
          ),
        if (hasTask && showsState) const SizedBox(width: 6),
        if (showsState)
          CompactTooltip(
            message: stateMessage,
            child: Icon(icon, size: 18, color: color),
          ),
      ],
    );
  }
}
