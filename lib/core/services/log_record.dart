import 'dart:convert';

/// Τι είδους συμβάν κατέγραψε η εφαρμογή.
///
/// Το είδος είναι **πεδίο**, όχι λέξη μέσα στο κείμενο: όποιος διαβάζει τα
/// αρχεία (η ένδειξη των Ρυθμίσεων, η εξαγωγή διαγνωστικών) φιλτράρει με αυτό,
/// ώστε μια αλλαγή διατύπωσης να μη χάνει ποτέ εγγραφές.
enum LogKind {
  /// Σφάλμα της εφαρμογής, με τη στοίβα του.
  error,

  /// Η προηγούμενη εκτέλεση χάθηκε χωρίς να κλείσει ομαλά.
  abnormalEnd,

  /// Σύνοψη ενός σφάλματος που επαναλήφθηκε πολλές φορές.
  repeat,

  /// Βήμα ή όριο μιας εκκίνησης.
  startup,

  /// Κλείσιμο που αξίζει καταγραφή (αργό, αποτυχημένο ή διακοπέν).
  shutdown,
}

/// Πόσο σοβαρό είναι ένα συμβάν.
enum LogSeverity { critical, nonCritical, warning, info }

/// Μία εγγραφή του ημερήσιου αρχείου καταγραφής — **μία γραμμή JSON**.
///
/// **Γιατί μία γραμμή.** Ο φάκελος των αρχείων είναι συχνά κοινός για όλους
/// τους υπολογιστές. Μια εγγραφή που πιάνει πολλές γραμμές μπλέκεται με τις
/// γραμμές του διπλανού σταθμού, και κανείς δεν ξέρει πού τελειώνει· μια
/// γραμμή στέκεται μόνη της, και μια μισογραμμένη γραμμή (κατάρρευση, χαμένο
/// δίκτυο) απλώς παραλείπεται χωρίς να χαλάσει τις υπόλοιπες.
///
/// Ο σταθμός και η έκδοση **δεν** δίνονται από όποιον γράφει: τα σφραγίζει
/// ένα σημείο, το ημερολόγιο, ώστε καμία νέα πηγή συμβάντων να μην μπορεί να
/// τα ξεχάσει.
class LogRecord {
  const LogRecord({
    required this.time,
    required this.kind,
    required this.severity,
    required this.message,
    this.details,
    this.data = const {},
    this.station = '',
    this.version = '',
  });

  final DateTime time;
  final LogKind kind;
  final LogSeverity severity;

  /// Η πρόταση που περιγράφει το συμβάν.
  final String message;

  /// Ό,τι συνοδεύει το μήνυμα: στοίβα κλήσεων, διαγνωστικά, ίχνος βημάτων.
  final String? details;

  /// Δομημένα στοιχεία ανά είδος (διάρκειες, πλήθη, φάση εκκίνησης).
  final Map<String, Object?> data;

  /// Ο υπολογιστής που έγραψε την εγγραφή.
  final String station;

  /// Η έκδοση της εφαρμογής που έγραψε την εγγραφή.
  final String version;

  /// Η ίδια εγγραφή με την ταυτότητα του συγγραφέα της.
  LogRecord stamped({required String station, required String version}) {
    return LogRecord(
      time: time,
      kind: kind,
      severity: severity,
      message: message,
      details: details,
      data: data,
      station: station,
      version: version,
    );
  }

  Map<String, Object?> toJson() => {
    'time': time.toIso8601String(),
    'station': station,
    'version': version,
    'kind': kind.name,
    'severity': severity.name,
    'message': message,
    if (details != null && details!.trim().isNotEmpty) 'details': details,
    if (data.isNotEmpty) 'data': data,
  };

  /// Η γραμμή του αρχείου, χωρίς αλλαγή γραμμής στο τέλος.
  String toJsonLine() => jsonEncode(toJson());

  /// `null` για ό,τι δεν είναι έγκυρη εγγραφή: μισογραμμένη γραμμή, κενή
  /// γραμμή, ή είδος που θα προσθέσει μια μελλοντική έκδοση. Ο αναγνώστης
  /// προσπερνά — ποτέ δεν σκάει για μία κακή γραμμή.
  static LogRecord? tryParse(String line) {
    final trimmed = line.trim();
    if (trimmed.isEmpty || !trimmed.startsWith('{')) return null;
    try {
      final decoded = jsonDecode(trimmed);
      if (decoded is! Map<String, Object?>) return null;
      final time = DateTime.tryParse(decoded['time']?.toString() ?? '');
      final kind = _byName(LogKind.values, decoded['kind']);
      final severity = _byName(LogSeverity.values, decoded['severity']);
      final message = decoded['message'];
      if (time == null || kind == null || severity == null) return null;
      if (message is! String) return null;
      final data = decoded['data'];
      return LogRecord(
        time: time,
        kind: kind,
        severity: severity,
        message: message,
        details: decoded['details'] as String?,
        data: data is Map<String, Object?> ? data : const {},
        station: decoded['station']?.toString() ?? '',
        version: decoded['version']?.toString() ?? '',
      );
    } on FormatException {
      return null;
    } on TypeError {
      return null;
    }
  }

  static T? _byName<T extends Enum>(List<T> values, Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return null;
  }
}
