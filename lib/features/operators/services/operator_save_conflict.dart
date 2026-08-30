import '../../../core/models/operator.dart';

/// Η καρτέλα χρήστη άλλαξε από άλλον, μετά την ανάγνωσή της.
///
/// Το προφίλ γράφεται **ολόκληρο** σε κάθε αποθήκευση — μαζί με τα δικαιώματα
/// και τη σήμανση διαχειριστή. Χωρίς αυτόν τον έλεγχο, ο δεύτερος διαχειριστής
/// που πατά «Αποθήκευση» σβήνει ό,τι έδωσε ο πρώτος, και η απώλεια μένει
/// αόρατη: τα δικαιώματα είναι ακριβώς το πράγμα που κανείς δεν ξανακοιτάζει.
class OperatorSaveConflict {
  const OperatorSaveConflict({
    required this.expected,
    required this.fresh,
    required this.attempted,
    this.changedBy,
    this.changedAt,
  });

  /// Η εικόνα που είχε φορτώσει η φόρμα — η αφετηρία.
  final Operator expected;

  /// Το προφίλ όπως είναι **τώρα** στη βάση.
  final Operator fresh;

  /// Το προφίλ που πήγε να γραφτεί.
  final Operator attempted;

  /// Ποιος έκανε την ξένη αλλαγή, από το Ιστορικό· `null` όταν δεν βρεθεί.
  final String? changedBy;

  /// Πότε έγινε η ξένη αλλαγή, από το Ιστορικό.
  final DateTime? changedAt;

  /// Τι άγγιξε ο άλλος, με τα λόγια της οθόνης.
  ///
  /// Συγκρίνεται η **αφετηρία** με τη βάση, όχι η πρόθεσή μου με τη βάση:
  /// αλλιώς οι δικές μου αλλαγές θα εμφανίζονταν ως ξένες.
  List<String> get changedFields {
    final changes = <String>[];
    if (expected.displayName.trim() != fresh.displayName.trim()) {
      changes.add('όνομα');
    }
    if (expected.windowsAccount != fresh.windowsAccount) {
      changes.add('λογαριασμός Windows');
    }
    if (expected.isAdmin != fresh.isAdmin) {
      changes.add('σήμανση διαχειριστή');
    }
    if (expected.isActive != fresh.isActive) {
      changes.add('κατάσταση προφίλ');
    }
    if (expected.avatarKey != fresh.avatarKey) {
      changes.add('εικονίδιο');
    }
    if (!_samePermissions(
      expected.permissionOverrides,
      fresh.permissionOverrides,
    )) {
      changes.add('δικαιώματα');
    }
    return changes;
  }

  /// Άλλαξε κάτι που η αποθήκευσή μου θα έγραφε από πάνω;
  bool get hasChanges => changedFields.isNotEmpty;

  /// «Ο χρήστης «Βασίλης» άλλαξε την καρτέλα του Βλάση στις 18:00.»
  ///
  /// Η ώρα γράφεται σκέτη για σήμερα και με ημερομηνία για παλιότερα: το «στις
  /// 18:00» για κάτι που έγινε προχθές είναι παραπλανητικό.
  String headline({DateTime? now}) {
    final moment = now ?? DateTime.now();
    final who = (changedBy == null || changedBy!.trim().isEmpty)
        ? 'Κάποιος άλλος'
        : 'Ο χρήστης «${changedBy!.trim()}»';
    final when = changedAt == null ? '' : ' στις ${_stamp(changedAt!, moment)}';
    return '$who άλλαξε την καρτέλα «${fresh.displayName}»$when.';
  }

  /// Τι χάνεται αν κρατήσω τη δική μου εικόνα.
  String get overwriteWarning {
    final fields = changedFields;
    if (fields.isEmpty) {
      return 'Αν κρατήσετε τη δική σας εικόνα, η ξένη αλλαγή θα αντικατασταθεί.';
    }
    return 'Αν κρατήσετε τη δική σας εικόνα, θα χαθεί ό,τι άλλαξε: '
        '${fields.join(', ')}.';
  }

  static String _stamp(DateTime moment, DateTime now) {
    String two(int v) => v.toString().padLeft(2, '0');
    final time = '${two(moment.hour)}:${two(moment.minute)}';
    final sameDay =
        moment.year == now.year &&
        moment.month == now.month &&
        moment.day == now.day;
    return sameDay ? time : '${two(moment.day)}/${two(moment.month)} $time';
  }

  static bool _samePermissions(Map<String, bool> a, Map<String, bool> b) {
    if (a.length != b.length) return false;
    for (final entry in a.entries) {
      if (b[entry.key] != entry.value) return false;
    }
    return true;
  }
}

/// Πετάγεται από το repository **πριν** γραφτεί τίποτα.
class OperatorStaleException implements Exception {
  const OperatorStaleException(this.conflict);

  final OperatorSaveConflict conflict;

  @override
  String toString() =>
      'Η καρτέλα χρήστη άλλαξε από άλλον χρήστη μετά την ανάγνωσή της.';
}
