/// Πότε υπενθυμίζουμε ότι εκκρεμεί δημοσίευση έκδοσης.
///
/// Κανόνες (απόφαση χρήστη 03/08/2026):
/// 1. **Χωρίς αδημοσίευτες εγγραφές δεν υπάρχει υπενθύμιση** — όσες ημέρες κι
///    αν περάσουν. Ο χρόνος από μόνος του δεν είναι λόγος δημοσίευσης.
/// 2. **Το πλήθος υπερισχύει του χρόνου** — αρκετές αλλαγές υπενθυμίζουν
///    αμέσως, ακόμη και την ίδια ημέρα με την προηγούμενη δημοσίευση· η
///    ημερομηνία δεν μπαίνει ποτέ φρένο.
/// 3. **Ο χρόνος πιάνει τα αργά διαστήματα** — λίγες αλλαγές που κάθονται
///    πολύ καιρό αξίζουν κι αυτές δημοσίευση.
library;

/// Πόσες αδημοσίευτες εγγραφές αρκούν για υπενθύμιση, ανεξάρτητα από χρόνο.
const int kPublishReminderEntryThreshold = 30;

/// Πόσες ημέρες από την τελευταία δημοσίευση αρκούν, εφόσον υπάρχει έστω μία
/// αδημοσίευτη εγγραφή.
const int kPublishReminderDayThreshold = 7;

/// Πάνω από αυτό το πλήθος, το σήμα δείχνει «99+» — δεν χωρούν άλλα ψηφία.
const int kPublishReminderBadgeCap = 99;

/// Κατάσταση υπενθύμισης δημοσίευσης, έτοιμη για προβολή.
class PublishReminderStatus {
  const PublishReminderStatus({
    required this.entryCount,
    required this.daysSinceLastRelease,
    required this.shouldRemind,
    this.lastReleaseVersion,
  });

  /// Ήρεμη κατάσταση — τίποτα δεν εκκρεμεί.
  static const quiet = PublishReminderStatus(
    entryCount: 0,
    daysSinceLastRelease: null,
    shouldRemind: false,
  );

  final int entryCount;

  /// Ημερολογιακές ημέρες από την τελευταία σφραγισμένη έκδοση· `null` όταν
  /// δεν υπάρχει (πρώτη δημοσίευση ή αντίγραφο χωρίς ημερομηνία).
  final int? daysSinceLastRelease;

  final bool shouldRemind;
  final String? lastReleaseVersion;

  /// Κείμενο του σήματος: το πλήθος, κομμένο στο «99+».
  String get badgeLabel => entryCount > kPublishReminderBadgeCap
      ? '$kPublishReminderBadgeCap+'
      : '$entryCount';

  /// Γραμμή υπόδειξης που εξηγεί **γιατί** άναψε το σήμα· `null` όταν δεν
  /// υπάρχει υπενθύμιση.
  String? get reasonLine {
    if (!shouldRemind) return null;
    final changes = entryCount == 1 ? '1 αλλαγή' : '$entryCount αλλαγές';
    final days = daysSinceLastRelease;
    final version = lastReleaseVersion?.trim() ?? '';
    if (days == null || version.isEmpty) {
      return 'Εκκρεμεί δημοσίευση: $changes';
    }
    final age = days == 1 ? '1 ημέρα' : '$days ημέρες';
    return 'Εκκρεμεί δημοσίευση: $changes, $age από την $version';
  }
}

/// Αποφασίζει αν πρέπει να εμφανιστεί υπενθύμιση δημοσίευσης.
///
/// Το [now] είναι υποχρεωτικό ώστε η απόφαση να μένει ελέγξιμη — ένα τεστ που
/// διαβάζει το πραγματικό ρολόι κοκκινίζει μια μέρα τον χρόνο.
PublishReminderStatus evaluatePublishReminder({
  required int unreleasedEntryCount,
  required DateTime now,
  DateTime? lastReleaseDate,
  String? lastReleaseVersion,
  int entryThreshold = kPublishReminderEntryThreshold,
  int dayThreshold = kPublishReminderDayThreshold,
}) {
  if (unreleasedEntryCount <= 0) return PublishReminderStatus.quiet;

  final days = lastReleaseDate == null
      ? null
      : _wholeDaysBetween(lastReleaseDate, now);

  final enoughChanges = unreleasedEntryCount >= entryThreshold;
  final enoughTime = days != null && days >= dayThreshold;

  return PublishReminderStatus(
    entryCount: unreleasedEntryCount,
    daysSinceLastRelease: days,
    shouldRemind: enoughChanges || enoughTime,
    lastReleaseVersion: lastReleaseVersion,
  );
}

/// Ημερολογιακές ημέρες: μετράει αλλαγές ημέρας, όχι ώρες — αλλιώς μια
/// δημοσίευση στις 23:00 θα «γερνούσε» μία ώρα αργότερα.
int _wholeDaysBetween(DateTime from, DateTime to) {
  final start = DateTime(from.year, from.month, from.day);
  final end = DateTime(to.year, to.month, to.day);
  final days = end.difference(start).inDays;
  return days < 0 ? 0 : days;
}
