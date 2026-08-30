// Η «Απόκρυψη Βάσης Γνώσης» κρύβει το εικονίδιο από την πλευρική μπάρα.
//
// Γιατί εδώ και όχι σε τεστ της λίστας προορισμών: ένα τεστ που ρωτά τον
// κανόνα αποδεικνύει μόνο ότι ο κανόνας είναι σωστός. Δεν αποδεικνύει ότι η
// μπάρα τον ρωτάει — και η Βάση Γνώσης ήταν ακριβώς ο προορισμός που έμπαινε
// ΧΩΡΙΣ όρο. Εδώ ρωτάμε την ίδια τη μπάρα: υπάρχει το εικονίδιο ή όχι;
//
//   flutter test test/core/widgets/knowledge_nav_hidden_test.dart

import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  required bool showKnowledgeNav,
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.runAsync(() async {
    await SettingsService().windowUi.setNavRailShowLabels(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...callLoggerTestProviderOverrides(),
          showKnowledgeNavProvider.overrideWith(
            (ref) async => showKnowledgeNav,
          ),
          showLampNavProvider.overrideWith((ref) async => false),
        ],
        child: const MyApp(showStartupScreens: false),
      ),
    );
    await tester.pump();
    await pumpUntilSettledLong(tester);
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(lookupServiceProvider.future);
  });
  await pumpUntilSettled(tester);
}

/// Το τσιρότο της μπάρας — επιλεγμένο επίτηδες ώστε να μη μοιάζει με το βιβλίο
/// του Λεξικού.
Finder knowledgeNavIcon() => find.byKey(const ValueKey('nav_rail_knowledge'));

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUpAll(() async {
    LookupService.instance.resetForReload();
    await LookupService.instance.loadFromDatabase();
  });

  group('Απόκρυψη Βάσης Γνώσης από την πλευρική μπάρα', () {
    testWidgets('θετικός μάρτυρας: χωρίς απόκρυψη το εικονίδιο είναι εκεί', (
      tester,
    ) async {
      // Χωρίς αυτόν, ο επόμενος έλεγχος θα περνούσε ακόμη κι αν το εικονίδιο
      // έλειπε για εντελώς άλλον λόγο.
      await _pumpShell(tester, showKnowledgeNav: true);

      expect(knowledgeNavIcon(), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('με απόκρυψη το εικονίδιο φεύγει', (tester) async {
      await _pumpShell(tester, showKnowledgeNav: false);

      expect(
        knowledgeNavIcon(),
        findsNothing,
        reason:
            'Ο προορισμός έμπαινε χωρίς όρο, σε αντίθεση με τη Λάμπα, τη Βάση '
            'Δεδομένων και το Λεξικό που έχουν ο καθένας τον δικό του.',
      );
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('η ετικέτα «Βάση Γνώσης» φεύγει μαζί με το εικονίδιο', (
      tester,
    ) async {
      await _pumpShell(tester, showKnowledgeNav: false);

      expect(
        find.text('Βάση Γνώσης'),
        findsNothing,
        reason:
            'Η μπάρα δείχνει ετικέτες: ένα κρυμμένο εικονίδιο με ορατό όνομα '
            'θα ήταν μισή απόκρυψη.',
      );
      await tester.pump(const Duration(seconds: 11));
    });
  });
}
