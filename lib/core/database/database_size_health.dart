/// Πόσο μεγάλη έχει γίνει η βάση, και πόσο καιρό έχει ως το επόμενο όριο.
///
/// **Τα κατώφλια ΔΕΝ βγαίνουν από την τεκμηρίωση της SQLite.** Η επίσημη θέση
/// είναι ότι το μέγιστο μέγεθος είναι 281 terabyte και ότι «για λιγότερο από
/// ένα terabyte η SQLite είναι σχεδόν πάντα η καλύτερη λύση» — δηλαδή τίποτα
/// που να μας αφορά: είμαστε εκατομμύρια φορές πιο κάτω, και **κανένα μέγεθος
/// δεν πρόκειται να σπάσει τη βάση**.
///
/// **Αυτό που μας αφορά είναι ο χρόνος αναμονής.** Η ίδια τεκμηρίωση
/// προειδοποιεί ρητά ότι πάνω από δίκτυο «η απόδοση δεν θα είναι καλή», και το
/// αντίγραφο ασφαλείας διαβάζει **ολόκληρο** το αρχείο κάθε φορά. Άρα το
/// μέγεθος πληρώνεται σε δευτερόλεπτα αναμονής, πολλές φορές την ημέρα.
///
/// Τα κατώφλια είναι μετρημένα πάνω σε αυτό:
///
/// | Μέγεθος | Αργό δίκτυο (~11 MB/s) | Γρήγορο με φόρτο (~40 MB/s) |
/// |---|---|---|
/// | 50 MB  | 4,5 δλ  | 1,2 δλ |
/// | 200 MB | 18,2 δλ | 5,0 δλ |
///
/// **Οι ενδείξεις είναι συμβουλευτικές.** Δεν εμποδίζουν τίποτα και δεν
/// ενεργοποιούν τίποτα μόνες τους.
library;

/// Πόσο μεγάλη είναι η βάση σε σχέση με το τι κοστίζει να αντιγράφεται.
enum DatabaseSizeLevel {
  /// Το αντίγραφο κρατά λίγα δευτερόλεπτα ακόμη και σε αργό δίκτυο.
  comfortable,

  /// Αισθητό αλλά ανεκτό. Αξίζει να ξέρεις ότι μεγαλώνει.
  watch,

  /// Κάθε αντίγραφο κοστίζει πάνω από ένα τέταρτο του λεπτού σε αργό δίκτυο.
  crowded,
}

/// Κάτω από αυτό το μέγεθος δεν υπάρχει τίποτα να σκεφτείς.
const int kDatabaseSizeWatchBytes = 50 * 1024 * 1024;

/// Πάνω από αυτό, το αντίγραφο γίνεται αισθητή αναμονή σε κάθε εκτέλεση.
const int kDatabaseSizeCrowdedBytes = 200 * 1024 * 1024;

/// Πόσο διαβάζει ένα αργό δίκτυο ανά δευτερόλεπτο — συντηρητική τιμή για SMB
/// πάνω από 100 Mbps, όπου το πρωτόκολλο χάνει πολύ σε καθυστέρηση.
const double kSlowNetworkBytesPerSecond = 11 * 1024 * 1024;

/// Η ετυμηγορία για μια συγκεκριμένη βάση.
class DatabaseSizeVerdict {
  const DatabaseSizeVerdict({
    required this.level,
    required this.sizeBytes,
    this.bytesPerDay,
    this.daysUntilNextLevel,
    this.nextLevelBytes,
  });

  final DatabaseSizeLevel level;
  final int sizeBytes;

  /// Πόσο μεγαλώνει η βάση κάθε μέρα· `null` όταν δεν υπάρχει αρκετή ιστορία.
  final double? bytesPerDay;

  /// Σε πόσες μέρες φτάνει στο επόμενο κατώφλι· `null` όταν δεν υπολογίζεται
  /// (άγνωστος ρυθμός, ή είναι ήδη στο τελευταίο επίπεδο).
  final int? daysUntilNextLevel;

  /// Ποιο είναι το επόμενο κατώφλι.
  final int? nextLevelBytes;

  /// Πόσα δευτερόλεπτα κρατά ένα αντίγραφο σε αργό δίκτυο.
  double get backupSecondsOnSlowNetwork =>
      sizeBytes / kSlowNetworkBytesPerSecond;
}

/// Κρίνει τη βάση από το μέγεθός της και τον ρυθμό που μεγαλώνει.
///
/// Ο ρυθμός βγαίνει από το πόσο καιρό ζει η βάση: μέγεθος διά ημέρες ζωής.
/// Είναι χονδρική προσέγγιση και **επίτηδες** — η ακρίβεια εδώ δεν προσθέτει
/// τίποτα, γιατί η απάντηση χρησιμεύει ως «χρόνια» και όχι ως ημερομηνία.
///
/// Κάτω από [minimumDaysForRate] ημέρες ζωής δεν βγαίνει εκτίμηση: μια βάση
/// δύο ημερών θα έδινε ρυθμό που δεν σημαίνει τίποτα.
DatabaseSizeVerdict judgeDatabaseSize({
  required int sizeBytes,
  required DateTime? oldestRecordAt,
  required DateTime now,
  int minimumDaysForRate = 14,
}) {
  final level = sizeBytes >= kDatabaseSizeCrowdedBytes
      ? DatabaseSizeLevel.crowded
      : (sizeBytes >= kDatabaseSizeWatchBytes
            ? DatabaseSizeLevel.watch
            : DatabaseSizeLevel.comfortable);

  final nextLevelBytes = switch (level) {
    DatabaseSizeLevel.comfortable => kDatabaseSizeWatchBytes,
    DatabaseSizeLevel.watch => kDatabaseSizeCrowdedBytes,
    DatabaseSizeLevel.crowded => null,
  };

  if (oldestRecordAt == null) {
    return DatabaseSizeVerdict(
      level: level,
      sizeBytes: sizeBytes,
      nextLevelBytes: nextLevelBytes,
    );
  }

  final lifetimeDays = now.difference(oldestRecordAt).inDays;
  if (lifetimeDays < minimumDaysForRate || sizeBytes <= 0) {
    return DatabaseSizeVerdict(
      level: level,
      sizeBytes: sizeBytes,
      nextLevelBytes: nextLevelBytes,
    );
  }

  final bytesPerDay = sizeBytes / lifetimeDays;
  int? days;
  if (nextLevelBytes != null && bytesPerDay > 0) {
    final remaining = nextLevelBytes - sizeBytes;
    days = remaining <= 0 ? 0 : (remaining / bytesPerDay).ceil();
  }

  return DatabaseSizeVerdict(
    level: level,
    sizeBytes: sizeBytes,
    bytesPerDay: bytesPerDay,
    daysUntilNextLevel: days,
    nextLevelBytes: nextLevelBytes,
  );
}

/// «σε 4 χρόνια», «σε 7 μήνες», «σε 20 μέρες» — όπως θα το έλεγε άνθρωπος.
///
/// Στρογγυλεύει επίτηδες: η εκτίμηση στηρίζεται σε χονδρικό ρυθμό, και ένα
/// «σε 1.522 ημέρες» θα υπόσχονταν ακρίβεια που δεν υπάρχει.
String formatDaysAhead(int days) {
  if (days <= 0) return 'τώρα';
  if (days < 45) return 'σε $days μέρες';
  if (days < 365) {
    final months = (days / 30).round();
    return months == 1 ? 'σε έναν μήνα' : 'σε $months μήνες';
  }
  final years = days / 365;
  if (years < 1.5) return 'σε έναν χρόνο περίπου';
  if (years < 10) return 'σε ${years.round()} χρόνια περίπου';
  return 'σε πάνω από 10 χρόνια';
}

/// Η συμβουλή που πάει δίπλα στην ένδειξη — μία πρόταση, χωρίς προστακτική.
String databaseSizeAdvice(DatabaseSizeLevel level) {
  switch (level) {
    case DatabaseSizeLevel.comfortable:
      return 'Δεν χρειάζεται εκκαθάριση.';
    case DatabaseSizeLevel.watch:
      return 'Δεν χρειάζεται ακόμη — αλλά αξίζει να το έχετε υπόψη.';
    case DatabaseSizeLevel.crowded:
      return 'Αξίζει να ενεργοποιηθεί εκκαθάριση.';
  }
}
