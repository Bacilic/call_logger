/// Επίπεδο σοβαρότητας ενός συμβάντος των Windows.
enum WindowsEventLevel {
  critical(1, 'Κρίσιμο'),
  error(2, 'Σφάλμα'),
  warning(3, 'Προειδοποίηση'),
  information(4, 'Πληροφορία'),
  verbose(5, 'Λεπτομερής');

  const WindowsEventLevel(this.code, this.label);

  /// Ο αριθμός που γράφουν τα Windows στο πεδίο `Level`.
  final int code;
  final String label;

  /// Το επίπεδο 0 («πάντα καταγραφή») εμφανίζεται ως πληροφορία, όπως και στην
  /// Προβολή συμβάντων.
  static WindowsEventLevel ofCode(int code) => switch (code) {
    1 => critical,
    2 => error,
    3 => warning,
    5 => verbose,
    _ => information,
  };

  /// Τα επίπεδα που προσφέρει ο οδηγός.
  static const selectable = [critical, error, warning];
}

/// Ένα συμβάν όπως το διαβάσαμε από τα Windows, πριν αποφασιστεί αν αξίζει.
class RawWindowsEvent {
  const RawWindowsEvent({
    required this.log,
    required this.provider,
    required this.eventId,
    required this.level,
    required this.time,
    required this.dataText,
  });

  /// `Application` ή `System`.
  final String log;
  final String provider;
  final int eventId;
  final WindowsEventLevel level;
  final DateTime time;

  /// Οι τιμές των δεδομένων του συμβάντος — εκεί γράφουν τα Windows ποια
  /// εφαρμογή κατέρρευσε ή πάγωσε.
  final String dataText;
}

/// Ένα συμβάν που μπαίνει μόνο του στην εξαγωγή, με το μήνυμά του.
class WindowsEventEntry {
  const WindowsEventEntry({
    required this.log,
    required this.provider,
    required this.eventId,
    required this.level,
    required this.time,
    required this.message,
  });

  final String log;
  final String provider;
  final int eventId;
  final WindowsEventLevel level;
  final DateTime time;
  final String message;
}

/// Όλες οι εμφανίσεις ενός είδους συμβάντος (ίδιο ημερολόγιο, πηγή, κωδικός,
/// επίπεδο).
class WindowsEventGroup {
  WindowsEventGroup({
    required this.log,
    required this.provider,
    required this.eventId,
    required this.level,
    required this.firstSeen,
    required this.sampleMessage,
  }) : lastSeen = firstSeen;

  final String log;
  final String provider;
  final int eventId;
  final WindowsEventLevel level;
  DateTime firstSeen;
  DateTime lastSeen;
  int count = 0;

  /// Το μήνυμα μίας εμφάνισης — αρκεί για να αναγνωριστεί το είδος.
  final String sampleMessage;
}

/// Τι βρέθηκε στα ημερολόγια των Windows για μια εξαγωγή.
class WindowsEventsReport {
  const WindowsEventsReport({
    required this.station,
    required this.from,
    required this.to,
    required this.levels,
    required this.appEvents,
    required this.computerLifecycle,
    required this.groups,
    required this.oldestByLog,
    this.failure,
  });

  final String station;
  final DateTime from;
  final DateTime to;
  final Set<WindowsEventLevel> levels;

  /// Συμβάντα που αφορούν την ίδια την εφαρμογή — σε κάθε επίπεδο.
  final List<WindowsEventEntry> appEvents;

  /// Κλεισίματα, εκκινήσεις και διακοπές ρεύματος του υπολογιστή.
  final List<WindowsEventEntry> computerLifecycle;

  /// Τα υπόλοιπα συμβάντα των επιλεγμένων επιπέδων, ομαδοποιημένα.
  final List<WindowsEventGroup> groups;

  /// Το παλαιότερο συμβάν που κρατούν ακόμη τα Windows, ανά ημερολόγιο —
  /// `null` όταν το ημερολόγιο δεν διαβάστηκε.
  final Map<String, DateTime?> oldestByLog;

  /// Γιατί δεν διαβάστηκαν τα συμβάντα, αν δεν διαβάστηκαν.
  final String? failure;
}
