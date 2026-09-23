// Όταν η βάση μένει κλειδωμένη (π.χ. αντίγραφο ασφαλείας από άλλον σταθμό),
// η ανάγνωση των χρηστών αποτυγχάνει. Οι κάρτες έδειχναν τότε «Χρήστης #2»
// αντί για το όνομα — ενώ το όνομα το ξέραμε ήδη από την προηγούμενη
// ανάγνωση. Ένα όνομα δεν αλλάζει επειδή η βάση άργησε.
//
//   flutter test test/features/operators/operator_names_survive_failed_read_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/operators/providers/operator_directory_providers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final vasilis = Operator(
    id: 2,
    displayName: 'Βασίλης',
    createdAt: DateTime(2026, 9, 1),
  );

  setUp(LastKnownOperatorNames.resetForTest);

  test('αποτυχημένη ανάγνωση: μένουν τα ονόματα που ξέραμε', () async {
    var failing = false;
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        allOperatorsProvider.overrideWith((ref) async {
          if (failing) throw Exception('database is locked');
          return [vasilis];
        }),
      ],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(operatorNamesProvider, (_, _) {});
    addTearDown(keepAlive.close);

    expect(await container.read(operatorNamesProvider.future), {2: 'Βασίλης'});

    failing = true;
    container.invalidate(allOperatorsProvider);

    expect(await container.read(operatorNamesProvider.future), {2: 'Βασίλης'});
  });

  test('χωρίς προηγούμενη επιτυχία, η αποτυχία δεν κρύβεται', () async {
    // Δεν υπάρχει γνώση να σώσουμε — ένας κενός χάρτης θα έλεγε ψέματα ότι
    // «δεν υπάρχει κανείς».
    final container = ProviderContainer(
      retry: (_, _) => null,
      overrides: [
        allOperatorsProvider.overrideWith(
          (ref) async => throw Exception('database is locked'),
        ),
      ],
    );
    addTearDown(container.dispose);
    final keepAlive = container.listen(operatorNamesProvider, (_, _) {});
    addTearDown(keepAlive.close);

    await expectLater(
      container.read(operatorNamesProvider.future),
      throwsA(isA<Exception>()),
    );
  });

  test('ονόματα άλλης βάσης δεν δανείζονται ποτέ', () {
    LastKnownOperatorNames.remember(r'\\A\vasi.db', {2: 'Βασίλης'});

    expect(LastKnownOperatorNames.forDatabase(r'\\B\alli.db'), isNull);
    expect(LastKnownOperatorNames.forDatabase(r'\\A\vasi.db'), {2: 'Βασίλης'});
  });
}
