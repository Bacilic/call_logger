// Ποια προφίλ προσφέρονται όταν αλλάζει η ανάθεση μιας εκκρεμότητας.
//
// Καθαρή λογική, χωρίς οθόνη: η απενεργοποίηση σταματά τη ΝΕΑ δουλειά, αλλά ο
// σημερινός υπεύθυνος πρέπει να φαίνεται πάντα — αλλιώς η εκκρεμότητα μοιάζει
// αδέσποτη ενώ ανήκει σε συγκεκριμένο πρόσωπο.
//
//   flutter test test/features/operators/assignable_operators_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/operators/utils/assignable_operators.dart';
import 'package:flutter_test/flutter_test.dart';

Operator _operator({
  required int id,
  required String name,
  bool isActive = true,
}) => Operator(
  id: id,
  displayName: name,
  isActive: isActive,
  createdAt: DateTime(2026, 1, 1),
);

void main() {
  final vasilis = _operator(id: 11, name: 'Βασίλης');
  final vlasis = _operator(id: 22, name: 'Βλάσης', isActive: false);
  final maria = _operator(id: 33, name: 'Μαρία');
  final all = [vasilis, vlasis, maria];

  group('operatorsForAssignment', () {
    test('χωρίς υπεύθυνο επιστρέφει μόνο τα ενεργά', () {
      expect(operatorsForAssignment(all, null), [vasilis, maria]);
    });

    test('ο απενεργοποιημένος υπεύθυνος μπαίνει στη λίστα', () {
      expect(operatorsForAssignment(all, 22), [vasilis, vlasis, maria]);
    });

    test('η σειρά της οθόνης «Χρήστες» διατηρείται', () {
      final result = operatorsForAssignment(all, 22);
      expect(
        result.map((o) => o.id),
        [11, 22, 33],
        reason:
            'Ο υπεύθυνος δεν προωθείται στην κορυφή: το μάτι ξέρει πού είναι '
            'ο καθένας και δεν ξαναψάχνει επειδή κάποιος μετακινήθηκε.',
      );
    });

    test('ενεργός υπεύθυνος δεν διπλασιάζεται', () {
      expect(operatorsForAssignment(all, 11), [vasilis, maria]);
    });

    test('υπεύθυνος που δεν υπάρχει στα προφίλ δεν προσθέτει τίποτα', () {
      expect(operatorsForAssignment(all, 99), [vasilis, maria]);
    });
  });

  group('operatorChoiceLabel', () {
    test('το ενεργό προφίλ γράφεται σκέτο', () {
      expect(operatorChoiceLabel(vasilis), 'Βασίλης');
    });

    test('το απενεργοποιημένο σημειώνεται', () {
      expect(operatorChoiceLabel(vlasis), 'Βλάσης (απενεργοποιημένος)');
    });

    test('το επίθημα δεν διπλασιάζεται', () {
      final already = _operator(
        id: 44,
        name: 'Βλάσης (απενεργοποιημένος)',
        isActive: false,
      );
      expect(operatorChoiceLabel(already), 'Βλάσης (απενεργοποιημένος)');
    });
  });
}
