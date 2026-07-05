import 'package:intl/intl.dart';

import '../../../calls/models/call_model.dart';
import '../../models/lansweeper_sync_state.dart';
import 'lansweeper_report_call_list.dart';

class ReportCallItem {
  const ReportCallItem({
    required this.key,
    required this.call,
    required this.caller,
    required this.notes,
    required this.details,
    required this.durationSeconds,
  });

  final String key;
  final CallModel call;
  final String caller;
  final String notes;
  final String details;
  final int durationSeconds;
}

abstract final class LansweeperReportItemMapper {
  LansweeperReportItemMapper._();

  static String callerLabel(CallModel call) {
    final value = (call.callerText ?? '').trim();
    return value.isEmpty ? '-' : value;
  }

  static String notes(CallModel call) {
    final issue = (call.issue ?? '').trim();
    if (issue.isNotEmpty) return issue;
    return '-';
  }

  static String selectedKeysSignature(List<ReportCallItem> selected) {
    final keys = selected.map((e) => e.key).toList()..sort();
    return keys.join('|');
  }

  static String combinedSelectedNotes(List<ReportCallItem> selected) {
    if (selected.isEmpty) return '';
    if (selected.length == 1) return selected.first.notes;
    return selected
        .map((e) {
          final date = DateFormat(
            'dd/MM/yyyy HH:mm',
          ).format(_callDateTime(e.call));
          final details = e.details.isNotEmpty ? ' • ${e.details}' : '';
          return '[$date] ${e.caller}: ${e.notes}$details';
        })
        .join('\n');
  }

  static String combinedAiIssue(List<ReportCallItem> selected) {
    if (selected.isEmpty) return '';
    if (selected.length == 1) {
      return (selected.first.call.issue ?? '').trim();
    }
    final parts = <String>[];
    for (final item in selected) {
      final issue = (item.call.issue ?? '').trim();
      if (issue.isEmpty) continue;
      final date = DateFormat('dd/MM/yyyy HH:mm').format(_callDateTime(item.call));
      parts.add('[$date] ${item.caller}: $issue');
    }
    return parts.join('\n');
  }

  static String combinedUniqueCallField(
    List<ReportCallItem> selected,
    String? Function(CallModel call) read,
  ) {
    final values = <String>{};
    for (final item in selected) {
      final value = (read(item.call) ?? '').trim();
      if (value.isNotEmpty) values.add(value);
    }
    return values.join(', ');
  }

  static String details(CallModel call) {
    final parts = <String>[];
    final equipmentCode = (call.equipmentText ?? '').trim();
    final department = (call.departmentText ?? '').trim();
    final problemCategory = (call.category ?? '').trim();

    if (equipmentCode.isNotEmpty) {
      parts.add('Κωδικός εξοπλισμού: $equipmentCode');
    }
    if (department.isNotEmpty) {
      parts.add('Τμήμα: $department');
    }
    if (problemCategory.isNotEmpty) {
      parts.add('Κατηγορία προβλήματος: $problemCategory');
    }

    return parts.join(' • ');
  }

  static String durationLabel(int seconds) {
    final safe = seconds < 0 ? 0 : seconds;
    final h = safe ~/ 3600;
    final m = (safe % 3600) ~/ 60;
    final s = safe % 60;
    if (h > 0) {
      return '${h.toString().padLeft(2, '0')}:${m.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  static String totalDurationLabel(int totalSeconds) {
    final safe = totalSeconds < 0 ? 0 : totalSeconds;
    final totalMinutes = (safe / 60).ceil();
    if (totalMinutes >= 60) {
      final hours = totalMinutes ~/ 60;
      final mins = totalMinutes % 60;
      return '$hours ώρ ${mins.toString().padLeft(2, '0')} λ';
    }
    return '$totalMinutes λ';
  }

  static DateTime _callDateTime(CallModel call) {
    final dateRaw = (call.date ?? '').trim();
    final timeRaw = (call.time ?? '').trim();
    final parsed = DateTime.tryParse('$dateRaw $timeRaw');
    return parsed ?? DateTime.fromMillisecondsSinceEpoch(0);
  }

  static List<ReportCallItem> toItems(List<CallModel> calls) {
    return calls.indexed.map((entry) {
      final i = entry.$1;
      final call = entry.$2;
      final id = call.id;
      final key = id != null ? 'id_$id' : 'idx_$i';
      return ReportCallItem(
        key: key,
        call: call,
        caller: callerLabel(call),
        notes: notes(call),
        details: details(call),
        durationSeconds: call.duration ?? 0,
      );
    }).toList();
  }

  static Map<String, List<ReportCallItem>> groupByCaller(
    List<ReportCallItem> items,
  ) {
    final grouped = <String, List<ReportCallItem>>{};
    for (final item in items) {
      grouped.putIfAbsent(item.caller, () => <ReportCallItem>[]).add(item);
    }
    return grouped;
  }

  static LansweeperReportCallRowData toRowData(ReportCallItem item) {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    return LansweeperReportCallRowData(
      key: item.key,
      call: item.call,
      dateLabel: DateFormat(
        'dd/MM/yyyy HH:mm',
      ).format(_callDateTime(item.call)),
      durationLabel: durationLabel(item.durationSeconds),
      lansweeperState: state,
      ticketId: item.call.lansweeperMainTicketId,
      notes: item.notes,
      details: item.details,
      durationSeconds: item.durationSeconds,
    );
  }

  static Map<String, List<LansweeperReportCallRowData>> groupedRowData(
    Map<String, List<ReportCallItem>> grouped,
  ) {
    return grouped.map(
      (caller, callerItems) =>
          MapEntry(caller, callerItems.map(toRowData).toList()),
    );
  }

  static String normalizedLansweeperState(ReportCallItem item) {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    return state.isEmpty ? LansweeperSyncState.unsent : state;
  }

  static bool isRegisteredCall(ReportCallItem item) =>
      normalizedLansweeperState(item) == LansweeperSyncState.sent;

  static bool isFailedCall(ReportCallItem item) =>
      normalizedLansweeperState(item) == LansweeperSyncState.failed;
}
