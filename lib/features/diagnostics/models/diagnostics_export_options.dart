import '../../../core/services/log_record.dart';
import 'windows_events.dart';

/// Τι ζητείται από τα ημερολόγια των Windows **αυτού** του υπολογιστή.
class WindowsEventsOptions {
  const WindowsEventsOptions({required this.levels, this.ownDays});

  /// Τα επίπεδα των γενικών συμβάντων. Τα συμβάντα της εφαρμογής και του
  /// κύκλου ζωής του υπολογιστή μπαίνουν πάντα, ανεξάρτητα από αυτά.
  final Set<WindowsEventLevel> levels;

  /// Οι τελευταίες τόσες ημέρες· `null` = η ίδια περίοδος με της εφαρμογής.
  /// Τα Windows κρατούν συχνά περισσότερο ιστορικό από τα αρχεία μας.
  final int? ownDays;

  static const int defaultOwnDays = 60;
}

/// Τι περιεχόμενο της εφαρμογής μπαίνει σε μια εξαγωγή διαγνωστικών.
enum DiagnosticsContent {
  /// Κρίσιμα σφάλματα, μαζί με τις εκτελέσεις που χάθηκαν απότομα.
  criticalErrors,

  /// Μη κρίσιμα σφάλματα, μαζί με τις συνόψεις επαναλήψεων.
  nonCriticalErrors,

  /// Εκκινήσεις της εφαρμογής.
  startups,

  /// Προβληματικά κλεισίματα (αργά, αποτυχημένα, διακοπέντα).
  shutdowns;

  /// Σε ποιο περιεχόμενο ανήκει μια εγγραφή του ημερολογίου.
  static DiagnosticsContent of(LogRecord record) => switch (record.kind) {
    LogKind.abnormalEnd => criticalErrors,
    LogKind.error =>
      record.severity == LogSeverity.critical
          ? criticalErrors
          : nonCriticalErrors,
    LogKind.repeat => nonCriticalErrors,
    LogKind.startup => startups,
    LogKind.shutdown => shutdowns,
  };

  String get label => switch (this) {
    criticalErrors => 'Κρίσιμα σφάλματα',
    nonCriticalErrors => 'Μη κρίσιμα σφάλματα',
    startups => 'Εκκινήσεις',
    shutdowns => 'Κλεισίματα',
  };
}

/// Τα φίλτρα μιας εξαγωγής διαγνωστικών, όπως τα διάλεξε ο χρήστης.
class DiagnosticsExportOptions {
  DiagnosticsExportOptions({
    required DateTime from,
    required DateTime to,
    required this.stations,
    required this.contents,
    this.windows,
  }) : from = _dayOf(from),
       to = _dayOf(to);

  /// `null` όταν δεν ζητήθηκαν συμβάντα των Windows.
  final WindowsEventsOptions? windows;

  /// Η περίοδος των συμβάντων των Windows — η ίδια ή δική τους.
  (DateTime, DateTime) windowsPeriod(DateTime today) {
    final days = windows?.ownDays;
    if (days == null) return (from, to);
    return lastDays(days, today);
  }

  /// Η πρώτη ημέρα της περιόδου (ολόκληρη).
  final DateTime from;

  /// Η τελευταία ημέρα της περιόδου (ολόκληρη).
  final DateTime to;

  /// Οι υπολογιστές που μπαίνουν στην εξαγωγή.
  final Set<String> stations;

  final Set<DiagnosticsContent> contents;

  /// Οι τελευταίες [days] ημέρες, με τελευταία το [today].
  static (DateTime, DateTime) lastDays(int days, DateTime today) {
    final end = _dayOf(today);
    return (end.subtract(Duration(days: days - 1)), end);
  }

  /// Αληθές όταν η εγγραφή περνά και τα τρία φίλτρα.
  bool includes(LogRecord record) {
    if (!stations.contains(record.station)) return false;
    if (!contents.contains(DiagnosticsContent.of(record))) return false;
    return coversDay(record.time);
  }

  /// Αληθές όταν η ημέρα της [moment] είναι μέσα στην περίοδο.
  bool coversDay(DateTime moment) {
    final day = _dayOf(moment);
    return !day.isBefore(from) && !day.isAfter(to);
  }

  static DateTime _dayOf(DateTime moment) =>
      DateTime(moment.year, moment.month, moment.day);
}
