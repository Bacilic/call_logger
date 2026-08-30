import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';

/// ΟΛΑ τα προφίλ χειριστών, με τη σειρά της οθόνης «Χρήστες».
///
/// Η μία ανάγνωση της βάσης που τροφοδοτεί όλες τις λίστες παρακάτω: πριν,
/// κάθε λίστα ρωτούσε μόνη της τα ίδια ακριβώς δεδομένα.
final allOperatorsProvider = FutureProvider.autoDispose<List<Operator>>((
  ref,
) async {
  final db = await DatabaseHelper.instance.database;
  return OperatorRepository(db).getAll();
});

/// Τα ενεργά προφίλ χειριστών.
///
/// Τροφοδοτεί τις λίστες όπου δίνεται **νέα** δουλειά: σε απενεργοποιημένο
/// προφίλ δεν ανατίθεται τίποτα καινούριο. Ό,τι ήδη του ανήκει εξακολουθεί να
/// φαίνεται με το όνομά του — δες `operatorsForAssignment`.
final activeOperatorsProvider = FutureProvider.autoDispose<List<Operator>>((
  ref,
) async {
  final all = await ref.watch(allOperatorsProvider.future);
  return [
    for (final operator in all)
      if (operator.isActive) operator,
  ];
});

/// Ονόματα ΟΛΩΝ των προφίλ (και των απενεργοποιημένων) ανά id.
///
/// Για την εμφάνιση — τα σήματα προσώπου στην κάρτα. Περιλαμβάνει και τα
/// απενεργοποιημένα: μια εκκρεμότητα ανατεθειμένη σε προφίλ που μετά
/// απενεργοποιήθηκε πρέπει να συνεχίσει να λέει σε ποιον ανήκει.
final operatorNamesProvider = FutureProvider.autoDispose<Map<int, String>>((
  ref,
) async {
  final all = await ref.watch(allOperatorsProvider.future);
  return {
    for (final operator in all)
      if (operator.id != null) operator.id!: operator.displayName,
  };
});

/// Το εικονίδιο ΟΛΩΝ των προφίλ ανά id — δίδυμο του [operatorNamesProvider].
///
/// Ζει χωριστά από τα ονόματα επίτηδες: οι οθόνες που δείχνουν μόνο κείμενο
/// (φίλτρα, λίστες επιλογής με στενό χώρο) δεν πληρώνουν τίποτα για κάτι που
/// δεν ζωγραφίζουν. Και οι δύο χάρτες τρέφονται από την **ίδια** ανάγνωση.
final operatorAvatarsProvider = FutureProvider.autoDispose<Map<int, String?>>((
  ref,
) async {
  final all = await ref.watch(allOperatorsProvider.future);
  return {
    for (final operator in all)
      if (operator.id != null) operator.id!: operator.avatarKey,
  };
});

/// Τα ids των προφίλ που έχουν απενεργοποιηθεί.
///
/// Για τις οθόνες που δείχνουν πρόσωπο χωρίς να προσφέρουν επιλογή — τα σήματα
/// της κάρτας. Εκεί το όνομα γράφεται πλάγια, ώστε να μη μοιάζει ζωντανή
/// ανάθεση κάτι που πρέπει να μεταφερθεί σε κάποιον ενεργό.
final disabledOperatorIdsProvider = FutureProvider.autoDispose<Set<int>>((
  ref,
) async {
  final all = await ref.watch(allOperatorsProvider.future);
  return {
    for (final operator in all)
      if (!operator.isActive && operator.id != null) operator.id!,
  };
});

/// Το όνομα του προφίλ [id] μέσα από τον χάρτη του [operatorNamesProvider].
///
/// Όσο ο χάρτης φορτώνει — ή όταν το προφίλ έχει σβηστεί από τη βάση — δεν
/// επιστρέφεται κενό: ο χρήστης που δεν βρίσκεται πια στα προφίλ εξακολουθεί
/// να είναι κάποιος συγκεκριμένος, και το κενό θα διαβαζόταν ως «κανένας».
String operatorDisplayNameFor(Map<int, String>? names, int id) =>
    names?[id] ?? 'Χρήστης #$id';
