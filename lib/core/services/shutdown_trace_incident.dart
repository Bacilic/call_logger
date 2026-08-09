import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;

/// Σύνοψη ενός **προβληματικού** κλεισίματος.
///
/// Ο ιχνηλάτης κρατά αρχείο μόνο όταν κάτι πήγε στραβά (δες
/// `ShutdownTraceService`). Κάθε τέτοιο αρχείο κλείνει με μία γραμμή
/// `SUMMARY={json}` — αυτή διαβάζεται εδώ, ώστε οι Ρυθμίσεις να μπορούν να
/// πουν στον χρήστη τι συνέβη χωρίς να διαβάσουν ολόκληρο το ίχνος.
class ShutdownTraceIncident {
  const ShutdownTraceIncident({
    required this.filePath,
    required this.occurredAt,
    required this.totalMs,
    required this.slowestStepLabel,
    required this.slowestStepMs,
    required this.hadFailure,
    required this.wasInterrupted,
  });

  /// Πλήρης διαδρομή του αρχείου ιχνηλάτησης.
  final String filePath;

  final DateTime occurredAt;

  /// Συνολικός χρόνος όλων των βημάτων.
  final int totalMs;

  /// Το αργότερο βήμα — αυτό ενδιαφέρει τη διάγνωση.
  final String slowestStepLabel;
  final int slowestStepMs;

  /// Κάποιο βήμα πέταξε σφάλμα.
  final bool hadFailure;

  /// Το κλείσιμο κόπηκε από το όριο ασφαλείας — κολλημένο βήμα.
  final bool wasInterrupted;

  static const String summaryPrefix = 'SUMMARY=';
  static const String fileNamePrefix = 'shutdown_trace_';
  static const String fileNameSuffix = '.log';

  String get fileName => p.basename(filePath);

  Map<String, Object?> toJson() => {
    'occurred_at': occurredAt.toIso8601String(),
    'total_ms': totalMs,
    'slowest_step': slowestStepLabel,
    'slowest_ms': slowestStepMs,
    'had_failure': hadFailure,
    'was_interrupted': wasInterrupted,
  };

  String toSummaryLine() => '$summaryPrefix${jsonEncode(toJson())}';

  /// Διαβάζει τη γραμμή σύνοψης. `null` αν λείπει ή είναι αλλοιωμένη — ένα
  /// μισογραμμένο αρχείο (η εφαρμογή σκοτώθηκε στη μέση) δεν είναι λόγος
  /// να σκάσει η οθόνη Ρυθμίσεων.
  static ShutdownTraceIncident? parseSummaryLine(String line, String filePath) {
    final trimmed = line.trim();
    if (!trimmed.startsWith(summaryPrefix)) return null;
    try {
      final decoded = jsonDecode(trimmed.substring(summaryPrefix.length));
      if (decoded is! Map<String, Object?>) return null;
      final occurredAt = DateTime.tryParse(
        decoded['occurred_at']?.toString() ?? '',
      );
      if (occurredAt == null) return null;
      return ShutdownTraceIncident(
        filePath: filePath,
        occurredAt: occurredAt,
        totalMs: _intOf(decoded['total_ms']),
        slowestStepLabel: decoded['slowest_step']?.toString() ?? '',
        slowestStepMs: _intOf(decoded['slowest_ms']),
        hadFailure: decoded['had_failure'] == true,
        wasInterrupted: decoded['was_interrupted'] == true,
      );
    } on FormatException {
      return null;
    }
  }

  static int _intOf(Object? value) => value is int ? value : 0;

  /// Το πιο πρόσφατο περιστατικό στον φάκελο, ή `null` αν δεν υπάρχει κανένα.
  ///
  /// Τα ονόματα αρχείων φέρουν χρονοσφραγίδα, οπότε η αλφαβητική σειρά είναι
  /// και χρονολογική· διαβάζεται μόνο το τελευταίο αρχείο, όχι όλα.
  static Future<ShutdownTraceIncident?> findLatest(String logsDirectory) async {
    try {
      final dir = Directory(logsDirectory);
      if (!await dir.exists()) return null;

      final files = await dir
          .list()
          .where((entity) => entity is File && isIncidentFile(entity.path))
          .cast<File>()
          .toList();
      if (files.isEmpty) return null;

      files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      for (final file in files) {
        final lines = await file.readAsLines();
        for (final line in lines.reversed) {
          final incident = parseSummaryLine(line, file.path);
          if (incident != null) return incident;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  static bool isIncidentFile(String path) {
    final name = p.basename(path);
    return name.startsWith(fileNamePrefix) && name.endsWith(fileNameSuffix);
  }

  /// Το μήνυμα που διαβάζει ο χρήστης στις Ρυθμίσεις.
  ///
  /// Τρεις περιπτώσεις, από τη σοβαρότερη: κολλημένο βήμα, αποτυχία, απλή
  /// καθυστέρηση. Το βήμα κατονομάζεται πάντα — αυτό ψάχνει όποιος διαγιγνώσκει.
  String describe() {
    if (wasInterrupted) {
      return 'Το προηγούμενο κλείσιμο της εφαρμογής διακόπηκε στο βήμα '
          '«$slowestStepLabel».';
    }
    if (hadFailure) {
      return 'Στο προηγούμενο κλείσιμο της εφαρμογής απέτυχε το βήμα '
          '«$slowestStepLabel».';
    }
    return 'Στο προηγούμενο κλείσιμο της εφαρμογής εντοπίστηκε καθυστέρηση '
        '${formatDuration(totalMs)} στο βήμα «$slowestStepLabel».';
  }

  /// «850 ms» κάτω από το δευτερόλεπτο, «1,2 δευτ.» από εκεί και πάνω —
  /// με ελληνικό υποδιαστολικό κόμμα.
  static String formatDuration(int milliseconds) {
    if (milliseconds < 1000) return '$milliseconds ms';
    final seconds = milliseconds / 1000;
    return '${seconds.toStringAsFixed(1).replaceAll('.', ',')} δευτ.';
  }
}
