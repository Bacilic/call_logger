import '../../database/services/database_stats_service.dart';

/// Η γραμμή σύνοψης πάνω από τα αποτελέσματα αναζήτησης της Λάμπας.
///
/// Δύο σκέλη — εξοπλισμός και οντότητες χωρίς εξοπλισμό — γιατί είναι δύο
/// διαφορετικά είδη ευρήματος: ένα ενιαίο άθροισμα θα έκρυβε ότι το ένα
/// ταίριασμα δεν είναι καν εξοπλισμός.
///
/// Ο ενικός/πληθυντικός υπολογίζεται **χωριστά ανά σκέλος** (και το ρήμα από
/// το πρώτο ορατό σκέλος): «Βρέθηκε 1 εξοπλισμός και 4 οντότητες…» είναι
/// λάθος ελληνικά μόνο αν το γράψει πρόγραμμα — άνθρωπος γράφει «Βρέθηκαν».
String? lampSearchOutcomeMessage({
  required int equipmentTotal,
  required int equipmentShown,
  required int unlinkedTotal,
  required int unlinkedShown,
}) {
  if (equipmentTotal <= 0 && unlinkedTotal <= 0) return null;

  String el(int n) => DatabaseStatsService.formatIntegerEl(n);
  String equipmentNoun(int n) => n == 1 ? 'εξοπλισμός' : 'εξοπλισμοί';
  String unlinkedNoun(int n) => n == 1 ? 'οντότητα' : 'οντότητες';

  final parts = <String>[];

  if (equipmentTotal > 0 && unlinkedTotal > 0) {
    final verb = equipmentTotal == 1 && unlinkedTotal == 1
        ? 'Βρέθηκε'
        : 'Βρέθηκαν';
    parts.add(
      '$verb ${el(equipmentTotal)} ${equipmentNoun(equipmentTotal)} και '
      '${el(unlinkedTotal)} ${unlinkedNoun(unlinkedTotal)} χωρίς εξοπλισμό.',
    );
  } else if (equipmentTotal > 0) {
    final verb = equipmentTotal == 1 ? 'Βρέθηκε' : 'Βρέθηκαν';
    parts.add(
      '$verb ${el(equipmentTotal)} ${equipmentNoun(equipmentTotal)}.',
    );
  } else {
    final verb = unlinkedTotal == 1 ? 'Βρέθηκε' : 'Βρέθηκαν';
    parts.add(
      '$verb ${el(unlinkedTotal)} ${unlinkedNoun(unlinkedTotal)} χωρίς '
      'εξοπλισμό. Κανένας εξοπλισμός.',
    );
  }

  if (equipmentShown < equipmentTotal) {
    parts.add('Εμφανίζονται οι πρώτοι ${el(equipmentShown)} εξοπλισμοί.');
  }
  if (unlinkedShown < unlinkedTotal) {
    parts.add('Εμφανίζονται οι πρώτες ${el(unlinkedShown)} οντότητες.');
  }

  return parts.join(' ');
}
