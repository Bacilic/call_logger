import '../../../core/database/audit_diff_helper.dart';
import '../../../core/utils/conflict_actor_text.dart';

/// Η καρτέλα Καταλόγου άλλαξε από άλλον, μετά την ανάγνωσή της.
///
/// Οι τρεις καρτέλες —υπάλληλος, τμήμα, εξοπλισμός— γράφονται **ολόκληρες**
/// από την εικόνα που φόρτωσε η φόρμα. Ένας συνάδελφος που άλλαξε τμήμα ή
/// πρόσθεσε τηλέφωνο στην ίδια εγγραφή χάνει τη δουλειά του χωρίς να το μάθει
/// κανείς — και σε αντίθεση με τις κλήσεις, εδώ δεν υπάρχει ιστορικό
/// συνδέσμων να τη θυμάται· μόνο το Ιστορικό Εφαρμογής.
///
/// **Μία κλάση για τις τρεις οντότητες επίτηδες:** ρωτούν το ίδιο πράγμα και
/// οι ετικέτες των πεδίων έρχονται ήδη από τον κοινό κατάλογο του Ιστορικού.
/// Τρία αντίγραφα θα απέκλιναν στην πρώτη διόρθωση διατύπωσης.
class DirectorySaveConflict {
  const DirectorySaveConflict({
    required this.entityType,
    required this.expected,
    required this.fresh,
    required this.attempted,
    this.changedBy,
    this.changedAt,
  });

  /// `AuditEntityTypes.user` / `.department` / `.equipment` — δίνει τις ετικέτες.
  final String entityType;

  /// Η εγγραφή όπως τη φόρτωσε η φόρμα — η αφετηρία.
  final Map<String, Object?> expected;

  /// Η εγγραφή όπως είναι **τώρα** στη βάση.
  final Map<String, Object?> fresh;

  /// Ό,τι πάει να γραφτεί· καθορίζει και **ποια** πεδία κινδυνεύουν.
  final Map<String, Object?> attempted;

  /// Ποιος έκανε την ξένη αλλαγή, από το Ιστορικό· `null` όταν δεν βρεθεί.
  final String? changedBy;

  /// Πότε έγινε η ξένη αλλαγή, από το Ιστορικό.
  final DateTime? changedAt;

  /// Η ίδια διένεξη, ντυμένη με το «ποιος και πότε».
  DirectorySaveConflict describedBy({String? who, DateTime? at}) =>
      DirectorySaveConflict(
        entityType: entityType,
        expected: expected,
        fresh: fresh,
        attempted: attempted,
        changedBy: who,
        changedAt: at,
      );

  static String _text(Object? value) => value?.toString().trim() ?? '';

  /// Τα πεδία που άγγιξε ο άλλος **και** θα τα ξαναγράψει η εγγραφή μου.
  ///
  /// Κρίνεται μόνο ό,τι περνά η δική μου εγγραφή: πεδίο που δεν το πειράζω
  /// δεν κινδυνεύει, όσο κι αν άλλαξε. Η σύγκριση είναι **αφετηρία προς βάση**,
  /// όχι πρόθεσή μου προς βάση — αλλιώς οι δικές μου αλλαγές θα εμφανίζονταν
  /// ως ξένες.
  List<String> get changedKeys => [
    for (final key in attempted.keys)
      if (key != 'id' &&
          !AuditDiffHelper.excludedFields.contains(key) &&
          expected.containsKey(key) &&
          _text(expected[key]) != _text(fresh[key]))
        key,
  ];

  /// Τι άγγιξε ο άλλος, με τις ετικέτες που ήδη χρησιμοποιεί το Ιστορικό.
  List<String> get changedFields {
    final labels = <String>[];
    for (final key in changedKeys) {
      final label = AuditDiffHelper.fieldTitleLabel(entityType, key);
      if (!labels.contains(label)) labels.add(label);
    }
    return labels;
  }

  bool get hasChanges => changedKeys.isNotEmpty;

  /// «Ο χρήστης «Βασίλης» άλλαξε αυτή την εγγραφή στις 13:10.»
  String headline({DateTime? now}) {
    final moment = now ?? DateTime.now();
    return '${conflictActorName(changedBy)} άλλαξε αυτή την εγγραφή'
        '${conflictMomentSuffix(changedAt, now: moment)}.';
  }

  /// Τι χάνεται αν επιμείνω στη δική μου εικόνα.
  String get overwriteWarning {
    final fields = changedFields;
    if (fields.isEmpty) {
      return 'Αν κρατήσετε τη δική σας εικόνα, η ξένη αλλαγή θα αντικατασταθεί.';
    }
    return 'Αν κρατήσετε τη δική σας εικόνα, θα χαθεί ό,τι άλλαξε: '
        '${fields.join(', ')}.';
  }

  /// Η διένεξη ή `null` όταν δεν υπάρχει λόγος να σταματήσει η εγγραφή.
  static DirectorySaveConflict? between({
    required String entityType,
    required Map<String, Object?>? expected,
    required Map<String, Object?>? fresh,
    required Map<String, Object?> attempted,
  }) {
    // Χωρίς αφετηρία (fail-open) ή χωρίς γραμμή στη βάση δεν υπάρχει τι να
    // συγκριθεί: η εγγραφή περνά, όπως και στις υπόλοιπες οντότητες.
    if (expected == null || fresh == null) return null;
    final conflict = DirectorySaveConflict(
      entityType: entityType,
      expected: expected,
      fresh: fresh,
      attempted: attempted,
    );
    return conflict.hasChanges ? conflict : null;
  }
}

/// Πετάγεται από το repository **πριν** γραφτεί τίποτα.
class DirectoryStaleException implements Exception {
  const DirectoryStaleException(this.conflict);

  final DirectorySaveConflict conflict;

  @override
  String toString() =>
      'Η εγγραφή Καταλόγου άλλαξε από άλλον χρήστη μετά την ανάγνωσή της.';
}
