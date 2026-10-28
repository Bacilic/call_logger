import 'package:intl/intl.dart';

import '../../../../core/services/lansweeper_text_format.dart';
import '../../../../core/services/lansweeper_ticket_texts.dart';
import '../../../calls/models/call_model.dart';
import '../../models/lansweeper_report_grouping.dart';
import '../../models/lansweeper_sync_state.dart';
import 'lansweeper_call_summary.dart';
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

  /// Το πρόβλημα της κλήσης στη φόρμα — ο κανόνας ζει στις υπηρεσίες, ώστε
  /// η αποστολή να τον διαβάζει από το ίδιο σημείο.
  static String notes(CallModel call) =>
      LansweeperTicketTexts.problemFromIssue(call.issue);

  /// Η Λύση όπως εμφανίζεται στη λίστα — κενή όταν δεν έχει γραφτεί ακόμη.
  ///
  /// Το κενό μένει κενό αντί για παύλα: εδώ σημαίνει «εκκρεμεί», και μια σειρά
  /// από παύλες θα γέμιζε τη λίστα με θόρυβο αντί να ξεχωρίζει τι έχει λυθεί.
  static String solutionSnippet(CallModel call) => (call.solution ?? '').trim();

  /// Ό,τι χρειάζεται ο τίτλος του αιτήματος από κάθε επιλεγμένη κλήση, με τη
  /// σειρά της επιλογής — για τον κοινό κανόνα
  /// [LansweeperSyncService.combinedTicketTitle].
  static List<({String? storedTitle, String category, int? id})> titleEntries(
    List<ReportCallItem> selected,
  ) => [
    for (final item in selected)
      (
        storedTitle: item.call.title,
        category: item.call.category ?? '',
        id: item.call.id,
      ),
  ];

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

  /// Οι λύσεις των επιλεγμένων κλήσεων, όπως ακριβώς αθροίζονται οι περιγραφές.
  ///
  /// Κλήσεις χωρίς λύση **παραλείπονται** αντί να μπουν με παύλα: εδώ το κενό
  /// σημαίνει «δεν γράφτηκε ακόμα λύση», και μια σειρά από παύλες θα ήταν
  /// θόρυβος που θα έφτανε αυτούσιος στο ticket. Όταν καμία δεν έχει λύση, το
  /// πεδίο μένει κενό — έτοιμο να γραφτεί από την αρχή.
  static String combinedSelectedSolutions(List<ReportCallItem> selected) {
    if (selected.isEmpty) return '';
    if (selected.length == 1) {
      return formatInlineSolutionSteps(selected.first.call.solution ?? '');
    }
    final parts = <String>[];
    for (final item in selected) {
      final solution = (item.call.solution ?? '').trim();
      if (solution.isEmpty) continue;
      final date = DateFormat(
        'dd/MM/yyyy HH:mm',
      ).format(_callDateTime(item.call));
      parts.add('[$date] ${item.caller}: $solution');
    }
    return parts.join('\n');
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
      final date = DateFormat(
        'dd/MM/yyyy HH:mm',
      ).format(_callDateTime(item.call));
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

  static const List<String> _weekdays = [
    'Δευτέρα',
    'Τρίτη',
    'Τετάρτη',
    'Πέμπτη',
    'Παρασκευή',
    'Σάββατο',
    'Κυριακή',
  ];

  /// Η επικεφαλίδα μιας ημέρας: «Σήμερα · Τετάρτη 21/10», «Χθες · Τρίτη
  /// 20/10», αλλιώς «Παρασκευή 17/10». Με το έτος μόνο όταν δεν είναι το
  /// τρέχον — στο «Όλο το ιστορικό» δύο 21/10 διαφορετικών ετών αλλιώς θα
  /// έμοιαζαν ίδια.
  static String dayLabel(DateTime day, {required DateTime now}) {
    final date = DateTime(day.year, day.month, day.day);
    final today = DateTime(now.year, now.month, now.day);
    final pattern = date.year == today.year ? 'dd/MM' : 'dd/MM/yyyy';
    final base =
        '${_weekdays[date.weekday - 1]} '
        '${DateFormat(pattern).format(date)}';
    if (date == today) return 'Σήμερα · $base';
    if (date == today.subtract(const Duration(days: 1))) return 'Χθες · $base';
    return base;
  }

  /// Ομάδες ανά ημέρα: η πιο πρόσφατη ημέρα πρώτη, και μέσα σε κάθε ημέρα η
  /// πιο πρόσφατη κλήση πρώτη — ανεξάρτητα από τη σειρά των [items].
  static Map<String, List<ReportCallItem>> groupByDay(
    List<ReportCallItem> items, {
    required DateTime now,
  }) {
    final sorted = [...items]
      ..sort((a, b) => _callDateTime(b.call).compareTo(_callDateTime(a.call)));
    final grouped = <String, List<ReportCallItem>>{};
    for (final item in sorted) {
      final label = dayLabel(_callDateTime(item.call), now: now);
      grouped.putIfAbsent(label, () => <ReportCallItem>[]).add(item);
    }
    return grouped;
  }

  /// Η γραμμή ώρας μιας κάρτας στην προβολή ανά ημέρα: η ημέρα λέγεται ήδη
  /// στην επικεφαλίδα, οπότε η κάρτα κρατά την ώρα — και τον καλούντα με το
  /// τηλέφωνό του, που εδώ δεν τα λέει καμία επικεφαλίδα.
  static String dayRowLabel(ReportCallItem item) {
    final parts = <String>[
      DateFormat('HH:mm').format(_callDateTime(item.call)),
      item.caller,
    ];
    final phone = (item.call.phoneText ?? '').trim();
    if (phone.isNotEmpty) parts.add(phone);
    return parts.join(' · ');
  }

  static LansweeperReportCallRowData toRowData(
    ReportCallItem item, {
    LansweeperReportGrouping grouping = LansweeperReportGrouping.byCaller,
  }) {
    final state = (item.call.lansweeperState ?? LansweeperSyncState.unsent)
        .trim();
    return LansweeperReportCallRowData(
      key: item.key,
      call: item.call,
      dateLabel: grouping == LansweeperReportGrouping.byDay
          ? dayRowLabel(item)
          : LansweeperCallSummary.shortDateLabel(item.call),
      tooltip: LansweeperCallSummary.callTooltip(item.call),
      durationLabel: durationLabel(item.durationSeconds),
      lansweeperState: state,
      ticketId: item.call.lansweeperMainTicketId,
      notes: item.notes,
      solution: solutionSnippet(item.call),
      durationSeconds: item.durationSeconds,
    );
  }

  static Map<String, List<LansweeperReportCallRowData>> groupedRowData(
    Map<String, List<ReportCallItem>> grouped, {
    LansweeperReportGrouping grouping = LansweeperReportGrouping.byCaller,
  }) {
    return grouped.map(
      (label, groupItems) => MapEntry(label, [
        for (final item in groupItems) toRowData(item, grouping: grouping),
      ]),
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
