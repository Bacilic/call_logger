/// Τι πρόκειται να συμβεί σε μια εκκαθάριση — **πριν** συμβεί.
///
/// **Γιατί υπάρχει:** η διαγραφή Ιστορικού είναι οριστική και κοινή για όλους
/// τους σταθμούς. Κανείς δεν πρέπει να την εγκρίνει διαβάζοντας «θα
/// εφαρμοστούν τα όρια» — πρέπει να δει **πόσες** γραμμές φεύγουν, **τι
/// είδους** είναι, και **τι μένει**.
///
/// Καθαρά δεδομένα: κανένα ερώτημα, καμία διαγραφή. Το σχέδιο το γεμίζει ο
/// υπολογιστής του, και το ίδιο σχέδιο εκτελείται αυτούσιο — ώστε να μην
/// μπορεί να αποκλίνει αυτό που εγκρίθηκε από αυτό που έγινε.
library;

import '../config/audit_retention_class.dart';

/// Μία γραμμή του σχεδίου: τι θα γίνει σε μία κλάση.
class AuditRetentionClassPlan {
  const AuditRetentionClassPlan({
    required this.retentionClass,
    required this.totalRows,
    required this.rowsToDelete,
    required this.cutoff,
  });

  final AuditRetentionClass retentionClass;

  /// Πόσες γραμμές αυτής της κλάσης υπάρχουν συνολικά.
  final int totalRows;

  /// Πόσες από αυτές θα σβηστούν.
  final int rowsToDelete;

  /// Το όριο ηλικίας που εφαρμόζεται· `null` όταν η κλάση δεν αγγίζεται.
  final DateTime? cutoff;

  int get rowsRemaining => totalRows - rowsToDelete;
  bool get touchesAnything => rowsToDelete > 0;
}

/// Γιατί μια εκκαθάριση δεν σβήνει ό,τι θα έσβηνε από τα σκέτα όρια.
enum AuditRetentionLimitReason {
  /// Κανένας περιορισμός δεν μπήκε στη μέση.
  none,

  /// Το πάτωμα γραμμών κράτησε πίσω μέρος της διαγραφής.
  floorReached,
}

/// Το πλήρες σχέδιο.
class AuditRetentionPlan {
  const AuditRetentionPlan({
    required this.classPlans,
    required this.rowsToCompact,
    required this.compactCutoff,
    required this.totalRowsBefore,
    required this.trimRows,
    this.limitReason = AuditRetentionLimitReason.none,
  });

  static const AuditRetentionPlan empty = AuditRetentionPlan(
    classPlans: <AuditRetentionClassPlan>[],
    rowsToCompact: 0,
    compactCutoff: null,
    totalRowsBefore: 0,
    trimRows: 0,
  );

  final List<AuditRetentionClassPlan> classPlans;

  /// Επίπεδο 1: πόσες γραμμές θα πετάξουν το κείμενο αναζήτησής τους.
  final int rowsToCompact;
  final DateTime? compactCutoff;

  final int totalRowsBefore;

  /// Πόσες γραμμές φεύγουν επιπλέον από το όριο πλήθους.
  final int trimRows;

  final AuditRetentionLimitReason limitReason;

  /// Συνολικές οριστικές διαγραφές.
  int get totalRowsToDelete =>
      classPlans.fold<int>(0, (sum, p) => sum + p.rowsToDelete) + trimRows;

  /// Τίποτα δεν πρόκειται να συμβεί.
  bool get isNoOp => totalRowsToDelete == 0 && rowsToCompact == 0;

  /// Πόσες γραμμές μένουν μετά.
  int get rowsRemaining => totalRowsBefore - totalRowsToDelete;

  /// Οι μόνιμες εγγραφές, που δεν αγγίζονται ποτέ — το πιο καθησυχαστικό
  /// νούμερο του διαλόγου.
  int get permanentRows => classPlans
      .where((p) => p.retentionClass == AuditRetentionClass.permanent)
      .fold<int>(0, (sum, p) => sum + p.totalRows);
}
