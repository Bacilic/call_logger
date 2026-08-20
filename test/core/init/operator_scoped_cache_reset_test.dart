// Φάση 2 — Πακέτο Γ: η «Αλλαγή χρήστη» ανανεώνει ΚΑΘΕ οθόνη που δείχνει
// προσωπική ρύθμιση, όπου κι αν βρίσκεται ο χρήστης εκείνη τη στιγμή.
//
// Χωρίς αυτό, η πλευρική μπάρα κρατούσε τους προορισμούς του προηγούμενου
// χρήστη μέχρι να μπει και να βγει από τις Ρυθμίσεις (αναφορά 20/08/2026).
//
// Οι providers δίνονται με υποκατάστατα: το ζητούμενο εδώ είναι **ότι
// ξαναϋπολογίζονται**, όχι τι διαβάζουν από τη βάση — και ένα πραγματικό
// άνοιγμα βάσης μέσα σε testWidgets δεν προχωρά ποτέ (παγωμένο ρολόι).
//
//   flutter test test/core/init/operator_scoped_cache_reset_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/operators/widgets/operator_change_refresh_listener.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

Operator _operator(int id) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  createdAt: DateTime(2026, 8, 20),
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(CurrentOperator.reset);
  tearDown(CurrentOperator.reset);

  /// Στήνει το δέντρο με τον ακροατή μέσα, όπως ζει στο κύριο κέλυφος, και
  /// μετρά πόσες φορές υπολογίστηκε η ρύθμιση της μπάρας.
  Future<({ProviderContainer container, int Function() builds})> pump(
    WidgetTester tester,
  ) async {
    var builds = 0;
    final container = ProviderContainer(
      overrides: [
        showLampNavProvider.overrideWith((ref) async {
          builds++;
          return true;
        }),
      ],
    );
    addTearDown(container.dispose);
    await tester.pumpWidget(
      UncontrolledProviderScope(
        container: container,
        child: const MaterialApp(
          home: Scaffold(body: OperatorChangeRefreshListener()),
        ),
      ),
    );
    return (container: container, builds: () => builds);
  }

  testWidgets('η αλλαγή χρήστη ξαναϋπολογίζει τη ρύθμιση της μπάρας', (
    tester,
  ) async {
    final harness = await pump(tester);

    CurrentOperator.activate(_operator(1));
    harness.container.listen(showLampNavProvider, (_, _) {});
    await tester.pumpAndSettle();
    expect(harness.builds(), 1);

    CurrentOperator.activate(_operator(2));
    await tester.pumpAndSettle();

    expect(
      harness.builds(),
      2,
      reason:
          'Ο νέος χρήστης πρέπει να δει τη ΔΙΚΗ ΤΟΥ μπάρα αμέσως — χωρίς να '
          'μπει και να βγει από τις Ρυθμίσεις.',
    );
  });

  testWidgets('η αποσύνδεση (καμία ταυτότητα) ανανεώνει επίσης', (
    tester,
  ) async {
    final harness = await pump(tester);

    CurrentOperator.activate(_operator(1));
    harness.container.listen(showLampNavProvider, (_, _) {});
    await tester.pumpAndSettle();
    expect(harness.builds(), 1);

    CurrentOperator.reset();
    await tester.pumpAndSettle();

    expect(harness.builds(), 2);
  });

  testWidgets('χωρίς αλλαγή ταυτότητας δεν ξαναϋπολογίζεται τίποτα', (
    tester,
  ) async {
    final harness = await pump(tester);

    CurrentOperator.activate(_operator(1));
    harness.container.listen(showLampNavProvider, (_, _) {});
    await tester.pumpAndSettle();

    // Ενεργοποίηση του ΙΔΙΟΥ αντικειμένου: καμία αλλαγή, καμία ανανέωση.
    await tester.pumpAndSettle();
    expect(harness.builds(), 1);
  });

  testWidgets('μετά το ξήλωμα του δέντρου, η αλλαγή δεν αγγίζει τίποτα', (
    tester,
  ) async {
    final harness = await pump(tester);
    harness.container.listen(showLampNavProvider, (_, _) {});
    await tester.pumpAndSettle();
    final before = harness.builds();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pumpAndSettle();

    // Ο ακροατής αποσυνδέθηκε στο dispose: μια αλλαγή τώρα δεν επιτρέπεται να
    // αγγίξει ακυρωμένο ref (θα έσκαγε) ούτε να προκαλέσει επανυπολογισμό.
    CurrentOperator.activate(_operator(3));
    await tester.pumpAndSettle();

    expect(harness.builds(), before);
  });
}
