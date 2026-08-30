// Η «Απόκρυψη Λεξικού» κρύβει το εικονίδιο — ΚΑΙ όταν φοράει θαυμαστικό.
//
// Γιατί εδώ και όχι σε τεστ της συνάρτησης ορατότητας: ένα τεστ που ρωτά τον
// κανόνα αποδεικνύει μόνο ότι ο κανόνας είναι σωστός. Δεν αποδεικνύει ότι η
// μπάρα τον ρωτάει. Αν κάποτε μπει δεύτερη πύλη που ξαναδείχνει το εικονίδιο,
// το τεστ του κανόνα θα μείνει πράσινο και το σφάλμα θα επιστρέψει. Εδώ
// ρωτάμε την ίδια την μπάρα: υπάρχει το εικονίδιο ή όχι;
//
// Εμβέλεια: **χωρίς φορτωμένο λεξικό-πυρήνας**. Είναι η μόνη κατάσταση που
// στήνει αξιόπιστα το περιβάλλον ελέγχου — και είναι ακριβώς η κατάσταση όπου
// η ρύθμιση αγνοούνταν. Η περίπτωση «φορτωμένος πυρήνας» δούλευε ούτως ή
// άλλως και τη φυλάει το τεστ του κανόνα.
//
//   flutter test test/core/widgets/dictionary_nav_hidden_test.dart

import 'package:call_logger/core/providers/core_lexicon_provider.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/widgets/main_shell_nav_icons.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  required bool showDictionaryNav,
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
          ...callLoggerTestProviderOverrides(
            showDictionaryNav: showDictionaryNav,
            coreLexiconLoaded: false,
          ),
          showLampNavProvider.overrideWith((ref) async => false),
          enableSpellCheckProvider.overrideWith((ref) async => true),
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

  // Η προϋπόθεση αποδεικνύεται, δεν υποτίθεται: αν η εκκίνηση ξαναφορτώσει τον
  // πυρήνα και ακυρώσει την παράκαμψη, το τεστ πρέπει να το πει — αλλιώς θα
  // περνούσε δηλώνοντας κάτι που δεν ισχύει.
  final container = ProviderScope.containerOf(
    tester.element(find.byType(MaterialApp)),
  );
  expect(
    container.read(coreLexiconLoadedProvider),
    isFalse,
    reason: 'Ο έλεγχος αφορά τη ΜΗ φορτωμένη κατάσταση — εδώ φορτώθηκε.',
  );
}

Finder dictionaryNavIcon() => find.byType(DictionaryNavigationIcon);

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUpAll(() async {
    LookupService.instance.resetForReload();
    await LookupService.instance.loadFromDatabase();
  });

  group('Απόκρυψη Λεξικού από την πλευρική μπάρα', () {
    testWidgets('θετικός μάρτυρας: χωρίς απόκρυψη το εικονίδιο είναι εκεί', (
      tester,
    ) async {
      // Χωρίς αυτόν, ο επόμενος έλεγχος θα περνούσε ακόμη κι αν το εικονίδιο
      // έλειπε για εντελώς άλλον λόγο.
      await _pumpShell(tester, showDictionaryNav: true);

      expect(dictionaryNavIcon(), findsOneWidget);
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('με απόκρυψη το εικονίδιο φεύγει, παρότι λείπει ο πυρήνας', (
      tester,
    ) async {
      await _pumpShell(tester, showDictionaryNav: false);

      expect(
        dictionaryNavIcon(),
        findsNothing,
        reason:
            'Ο χρήστης ζήτησε να φύγει. Το θαυμαστικό δεν είναι άδεια '
            'παραμονής — η προειδοποίηση ζει στις Ρυθμίσεις.',
      );
      await tester.pump(const Duration(seconds: 11));
    });
  });
}
