// Οι προσωπικές ρυθμίσεις του διαλόγου εκκρεμοτήτων: τι μετράει ως αλλαγή.
//
//   flutter test test/features/tasks/task_personal_settings_test.dart

import 'package:call_logger/features/tasks/models/task_personal_settings.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const initial = TaskPersonalSettings(
    notifyHandovers: true,
    showBadge: true,
    printPreview: true,
  );

  test('χωρίς αλλαγή, τίποτα προς αποθήκευση', () {
    expect(initial.copyWith().changesFrom(initial), isEmpty);
  });

  test('κάθε διακόπτης που άλλαξε αναφέρεται με το όνομά του', () {
    final changes = initial
        .copyWith(showBadge: false, printPreview: false)
        .changesFrom(initial);

    expect(changes, [
      'Μετρητής στο μενού Εκκρεμοτήτων: Ναι -> Όχι',
      'Προεπισκόπηση πριν την εκτύπωση: Ναι -> Όχι',
    ]);
  });

  test('διακόπτης που γύρισε πίσω στην αρχική τιμή δεν είναι αλλαγή', () {
    final back = initial
        .copyWith(notifyHandovers: false)
        .copyWith(notifyHandovers: true);
    expect(back.changesFrom(initial), isEmpty);
  });
}
