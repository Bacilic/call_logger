import 'dart:io';

import 'package:path/path.dart' as p;

import 'crash_log_service.dart';
import 'log_record.dart';

/// Σύνοψη ενός **προβληματικού** κλεισίματος.
///
/// Ο ιχνηλάτης κρατά ίχνος μόνο όταν κάτι πήγε στραβά (δες
/// `ShutdownTraceService`), και το γράφει ως εγγραφή [LogKind.shutdown] στο
/// ημερήσιο αρχείο. Τα στοιχεία της σύνοψης ζουν στα δομημένα δεδομένα της
/// εγγραφής — αυτά διαβάζονται εδώ, ώστε οι Ρυθμίσεις να πουν στον χρήστη τι
/// συνέβη χωρίς να διαβάσουν ολόκληρο το ίχνος.
class ShutdownTraceIncident {
  const ShutdownTraceIncident({
    required this.occurredAt,
    required this.totalMs,
    required this.slowestStepLabel,
    required this.slowestStepMs,
    required this.hadFailure,
    required this.wasInterrupted,
  });

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

  /// Η κατάληξη των προσωρινών ιχνών κλεισίματος (τοπικά αρχεία κειμένου).
  static const String fileNameSuffix = '.log';

  Map<String, Object?> toJson() => {
    'occurred_at': occurredAt.toIso8601String(),
    'total_ms': totalMs,
    'slowest_step': slowestStepLabel,
    'slowest_ms': slowestStepMs,
    'had_failure': hadFailure,
    'was_interrupted': wasInterrupted,
  };

  /// Η εγγραφή που κρατά το περιστατικό στο ημερήσιο αρχείο. Ο σταθμός δεν
  /// μπαίνει εδώ: τον σφραγίζει το ημερολόγιο τη στιγμή της εγγραφής.
  LogRecord toRecord({required String trace}) {
    return LogRecord(
      time: occurredAt,
      kind: LogKind.shutdown,
      severity: hadFailure || wasInterrupted
          ? LogSeverity.nonCritical
          : LogSeverity.warning,
      message: describeEvent(),
      details: trace,
      data: toJson(),
    );
  }

  /// Το περιστατικό μιας εγγραφής κλεισίματος. `null` για κάθε άλλη εγγραφή,
  /// ή όταν τα στοιχεία λείπουν — μια αλλοιωμένη εγγραφή δεν είναι λόγος να
  /// σκάσει η οθόνη Ρυθμίσεων.
  static ShutdownTraceIncident? fromRecord(LogRecord record) {
    if (record.kind != LogKind.shutdown) return null;
    final data = record.data;
    final occurredAt =
        DateTime.tryParse(data['occurred_at']?.toString() ?? '') ?? record.time;
    return ShutdownTraceIncident(
      occurredAt: occurredAt,
      totalMs: _intOf(data['total_ms']),
      slowestStepLabel: data['slowest_step']?.toString() ?? '',
      slowestStepMs: _intOf(data['slowest_ms']),
      hadFailure: data['had_failure'] == true,
      wasInterrupted: data['was_interrupted'] == true,
    );
  }

  static int _intOf(Object? value) => value is int ? value : 0;

  /// Το πιο πρόσφατο περιστατικό **του [station]** στον φάκελο, ή `null`.
  ///
  /// Ο φάκελος είναι κοινός όταν η βάση είναι κοινή: χωρίς το φίλτρο, η
  /// ένδειξη ενός υπολογιστή θα έδειχνε την αργή έξοδο του συναδέλφου σαν
  /// δική του.
  ///
  /// Τα ημερήσια αρχεία φέρουν την ημερομηνία στο όνομά τους, οπότε η
  /// αλφαβητική σειρά είναι και χρονολογική. Μέσα στο αρχείο η αναζήτηση πάει
  /// από το τέλος προς την αρχή: το τελευταίο κλείσιμο είναι προς το τέλος.
  static Future<ShutdownTraceIncident?> findLatest(
    String logsDirectory, {
    required String station,
  }) async {
    try {
      final dir = Directory(logsDirectory);
      if (!await dir.exists()) return null;

      final files = await dir
          .list()
          .where(
            (entity) =>
                entity is File &&
                CrashLogService.isDailyLogFileName(p.basename(entity.path)),
          )
          .cast<File>()
          .toList();
      if (files.isEmpty) return null;

      files.sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));
      for (final file in files) {
        final lines = await file.readAsLines();
        for (final line in lines.reversed) {
          final record = LogRecord.tryParse(line);
          if (record == null || record.station != station) continue;
          final incident = fromRecord(record);
          if (incident != null) return incident;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Το συμβάν όπως το διαβάζει όποιος ξεφυλλίζει το αρχείο — χωρίς το
  /// «προηγούμενο» της ένδειξης, που έχει νόημα μόνο στην επόμενη εκκίνηση.
  String describeEvent() {
    if (wasInterrupted) {
      return 'Το κλείσιμο διακόπηκε στο βήμα «$slowestStepLabel».';
    }
    if (hadFailure) {
      return 'Στο κλείσιμο απέτυχε το βήμα «$slowestStepLabel».';
    }
    return 'Αργό κλείσιμο: ${formatDuration(totalMs)}, το πιο αργό βήμα '
        '«$slowestStepLabel».';
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
