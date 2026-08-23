import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/database/database_helper.dart';
import '../../../core/database/operator_repository.dart';
import '../../../core/models/operator.dart';

/// Τα ενεργά προφίλ χειριστών, με τη σειρά της οθόνης «Χρήστες».
///
/// Τροφοδοτεί το «Ανάθεση σε» της φόρμας και το μενού γρήγορης ανάθεσης.
/// Μόνο τα ενεργά: σε αρχειοθετημένο προφίλ δεν ανατίθεται νέα δουλειά —
/// ό,τι ήδη του ανήκει όμως εξακολουθεί να φαίνεται με το όνομά του.
final activeOperatorsProvider = FutureProvider.autoDispose<List<Operator>>((
  ref,
) async {
  final db = await DatabaseHelper.instance.database;
  final all = await OperatorRepository(db).getAll();
  return [
    for (final operator in all)
      if (operator.isActive) operator,
  ];
});

/// Ονόματα ΟΛΩΝ των προφίλ (και των αρχειοθετημένων) ανά id.
///
/// Για την εμφάνιση — το chip του υπευθύνου στην κάρτα. Περιλαμβάνει και τα
/// αρχειοθετημένα: μια εκκρεμότητα ανατεθειμένη σε προφίλ που μετά
/// αρχειοθετήθηκε πρέπει να συνεχίσει να λέει σε ποιον ανήκει.
final operatorNamesProvider = FutureProvider.autoDispose<Map<int, String>>((
  ref,
) async {
  final db = await DatabaseHelper.instance.database;
  final all = await OperatorRepository(db).getAll();
  return {
    for (final operator in all)
      if (operator.id != null) operator.id!: operator.displayName,
  };
});
