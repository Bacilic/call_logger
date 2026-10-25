import '../models/windows_events.dart';

/// Αποφασίζει, συμβάν-συμβάν, τι από τα ημερολόγια των Windows μπαίνει στην
/// εξαγωγή — χωρίς να ξέρει πώς διαβάστηκαν.
///
/// Τρεις κατηγορίες, με αυτή τη σειρά προτεραιότητας:
/// 1. **Συμβάντα της εφαρμογής** (κατάρρευση, πάγωμα, αναφορά σφάλματος για
///    το δικό μας εκτελέσιμο): μπαίνουν όλα, **σε κάθε επίπεδο**. Το μόνο
///    τέτοιο συμβάν που βρέθηκε στο σπίτι ήταν επιπέδου «Πληροφορία» — ένα
///    φίλτρο επιπέδου θα το έχανε.
/// 2. **Κύκλος ζωής του υπολογιστή** (κλείσιμο, επανεκκίνηση, διακοπή
///    ρεύματος): μπαίνουν όλα, γιατί εξηγούν το «η εφαρμογή δεν τερμάτισε
///    ομαλά» χωρίς κατάρρευση.
/// 3. **Ύπνος και αφύπνιση** του υπολογιστή: μπαίνουν όλα, γιατί εξηγούν το
///    πάγωμα της εφαρμογής μετά από αδράνεια.
/// 4. **Όλα τα υπόλοιπα των επιλεγμένων επιπέδων**: ομαδοποιούνται ανά είδος.
///    Σε 60 ημέρες ήταν 1.682 συμβάντα αλλά μόνο 24 είδη.
///
/// Το μήνυμα ζητείται ([add]) μόνο όταν χρειάζεται — η μορφοποίησή του από τα
/// Windows είναι το ακριβό κομμάτι της ανάγνωσης.
class WindowsEventCollector {
  WindowsEventCollector({required this.appExecutable, required this.levels});

  /// Το όνομα του δικού μας εκτελέσιμου, π.χ. `call_logger.exe`.
  final String appExecutable;

  final Set<WindowsEventLevel> levels;

  final List<WindowsEventEntry> appEvents = [];
  final List<WindowsEventEntry> computerLifecycle = [];
  final List<WindowsEventEntry> sleepAndWake = [];
  final Map<String, WindowsEventGroup> _groups = {};

  List<WindowsEventGroup> get groups =>
      _groups.values.toList()..sort((a, b) => b.count.compareTo(a.count));

  void add(RawWindowsEvent event, String Function() message) {
    if (isAppEvent(event)) {
      appEvents.add(_entry(event, message()));
      return;
    }
    if (isComputerLifecycle(event)) {
      computerLifecycle.add(_entry(event, message()));
      return;
    }
    if (isSleepOrWake(event)) {
      sleepAndWake.add(_entry(event, message()));
      return;
    }
    if (!levels.contains(event.level)) return;
    final key =
        '${event.log}|${event.provider}|${event.eventId}|${event.level.code}';
    final group = _groups.putIfAbsent(
      key,
      () => WindowsEventGroup(
        log: event.log,
        provider: event.provider,
        eventId: event.eventId,
        level: event.level,
        firstSeen: event.time,
        sampleMessage: message(),
      ),
    );
    group.count++;
    if (event.time.isBefore(group.firstSeen)) group.firstSeen = event.time;
    if (event.time.isAfter(group.lastSeen)) group.lastSeen = event.time;
  }

  bool isAppEvent(RawWindowsEvent event) =>
      event.log == 'Application' &&
      appExecutable.isNotEmpty &&
      event.dataText.toLowerCase().contains(appExecutable.toLowerCase());

  /// Οι πηγές και οι κωδικοί που λένε πότε ο υπολογιστής έκλεισε, άνοιξε ή
  /// έπεσε. Αριθμοί που ζητούνται ρητά και στο ερώτημα προς τα Windows.
  ///
  /// Μόνο όσα λένε κάτι **μόνα τους**: διακοπή ρεύματος (41), απρόσμενο
  /// κλείσιμο (6008), ποιος ζήτησε κλείσιμο ή επανεκκίνηση (1074), εκκίνηση
  /// των Windows (12). Τα «ξεκίνησε/σταμάτησε η υπηρεσία καταγραφής» (6005,
  /// 6006) και το «σταμάτησε το λειτουργικό» (13) επαναλαμβάνουν τα ίδια
  /// γεγονότα — μετρημένα, διπλασίαζαν τις γραμμές.
  static const Map<String, Set<int>> lifecycleEvents = {
    'Microsoft-Windows-Kernel-Power': {41},
    'EventLog': {6008},
    'User32': {1074},
    'Microsoft-Windows-Kernel-General': {12},
  };

  static bool isComputerLifecycle(RawWindowsEvent event) =>
      event.log == 'System' &&
      (lifecycleEvents[event.provider]?.contains(event.eventId) ?? false);

  /// Πότε ο υπολογιστής κοιμήθηκε και πότε ξύπνησε. Ζητούνται κι αυτά ρητά
  /// στο ερώτημα προς τα Windows.
  ///
  /// Ένα πάγωμα της εφαρμογής μετά από ώρα αδράνειας εξηγείται συχνά από τον
  /// ύπνο: η κάρτα δικτύου ξυπνά αργότερα από τον υπολογιστή, και η βάση στο
  /// δίκτυο δεν απαντά στο μεταξύ (PC3569, 02/10 και 06/10/2026).
  ///
  /// Μπαίνει ύπνος (42) και αφύπνιση (Power-Troubleshooter 1 — το μήνυμά της
  /// λέει πόσο κράτησε ο ύπνος και τι τον ξύπνησε), και τα δύο αντίστοιχα της
  /// «σύγχρονης αναμονής» (506/507) των νεότερων υπολογιστών. Η αφύπνιση του
  /// πυρήνα (Kernel-Power 107) επαναλαμβάνει την ίδια στιγμή και μένει έξω.
  static const Map<String, Set<int>> sleepWakeEvents = {
    'Microsoft-Windows-Kernel-Power': {42, 506, 507},
    'Microsoft-Windows-Power-Troubleshooter': {1},
  };

  static bool isSleepOrWake(RawWindowsEvent event) =>
      event.log == 'System' &&
      (sleepWakeEvents[event.provider]?.contains(event.eventId) ?? false);

  /// Ύπνος ή αφύπνιση; Για την ετικέτα της ενότητας και του χρονολογίου.
  static bool isWake(WindowsEventEntry event) =>
      (event.provider == 'Microsoft-Windows-Power-Troubleshooter' &&
          event.eventId == 1) ||
      (event.provider == 'Microsoft-Windows-Kernel-Power' &&
          event.eventId == 507);

  static WindowsEventEntry _entry(RawWindowsEvent event, String message) =>
      WindowsEventEntry(
        log: event.log,
        provider: event.provider,
        eventId: event.eventId,
        level: event.level,
        time: event.time,
        message: message,
      );
}
