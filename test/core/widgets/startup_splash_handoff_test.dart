// Η παράδοση της σκυτάλης από την κάρτα εκκίνησης στο κέλυφος.
//
// Το συμβόλαιο: η κάρτα ανοίγει σε παράθυρο μικρότερο από το ελάχιστο για το
// οποίο είναι σχεδιασμένη η διεπαφή. Αν το κέλυφος χτιστεί όσο το παράθυρο
// είναι ακόμη στο μέγεθος της κάρτας, η διεπαφή ζωγραφίζεται σε ύψος που δεν
// της φτάνει και ξεχειλίζει. Άρα: πρώτα επανέρχεται το παράθυρο, μετά φεύγει η
// κάρτα — ποτέ ανάποδα.
//
// Η σειρά φαινόταν μόνο σε αργό μηχάνημα, όπου η επαναφορά κρατά αρκετά καρέ.
// Γι' αυτό ελέγχεται εδώ ρητά και δεν αφήνεται στην τύχη του χρονισμού.
//
//   flutter test test/core/widgets/startup_splash_handoff_test.dart

import 'dart:async';

import 'package:call_logger/core/init/startup_journal.dart';
import 'package:call_logger/core/widgets/app_init_wrapper.dart';
import 'package:call_logger/core/widgets/startup_splash_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

/// Αφήνει την κάρτα να πει τα βήματά της και να περάσει η ελάχιστη διάρκειά της.
///
/// Με μικρά βήματα επίτηδες: ο ρυθμιστής της κάρτας είναι περιοδικός και ένα
/// μεγάλο άλμα του χρόνου δεν τον χτυπά όσες φορές χρειάζεται.
Future<void> _letSplashFinishSpeaking(WidgetTester tester) async {
  for (var i = 0; i < 60; i++) {
    await tester.pump(const Duration(milliseconds: 120));
  }
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUp(() => StartupJournal.instance.reset());

  testWidgets('η κάρτα μένει όσο το παράθυρο δεν έχει επανέλθει', (
    tester,
  ) async {
    StartupJournal.instance.begin('Άνοιγμα βάσης δεδομένων').ok();

    final windowRestored = Completer<void>();
    var restoreRequested = false;

    await tester.pumpWidget(
      ProviderScope(
        overrides: callLoggerTestProviderOverrides(),
        child: MaterialApp(
          home: AppInitWrapper(
            windowRestorer: () {
              restoreRequested = true;
              return windowRestored.future;
            },
          ),
        ),
      ),
    );

    await _letSplashFinishSpeaking(tester);

    expect(
      restoreRequested,
      isTrue,
      reason: 'η κάρτα οφείλει να ζητήσει επαναφορά παραθύρου πριν αποσυρθεί',
    );
    expect(
      find.byType(StartupSplashScreen),
      findsOneWidget,
      reason: 'το κέλυφος δεν χτίζεται όσο το παράθυρο είναι στο μέγεθος '
          'της κάρτας',
    );

    windowRestored.complete();
    await tester.pump();
    await tester.pump();

    expect(
      find.byType(StartupSplashScreen),
      findsNothing,
      reason: 'μόλις επανέλθει το παράθυρο, η κάρτα παραδίδει τη σκυτάλη',
    );

    await tester.pump(const Duration(seconds: 11));
  }, semanticsEnabled: false);

  testWidgets('αποτυχία επαναφοράς δεν κρατά την πόρτα κλειστή', (
    tester,
  ) async {
    StartupJournal.instance.begin('Άνοιγμα βάσης δεδομένων').ok();

    await tester.pumpWidget(
      ProviderScope(
        overrides: callLoggerTestProviderOverrides(),
        child: MaterialApp(
          home: AppInitWrapper(
            windowRestorer: () async {
              throw StateError('το λειτουργικό αρνήθηκε την αλλαγή μεγέθους');
            },
          ),
        ),
      ),
    );

    await _letSplashFinishSpeaking(tester);
    await tester.pump();

    expect(
      find.byType(StartupSplashScreen),
      findsNothing,
      reason: 'μια εφαρμογή που δεν ανοίγει είναι χειρότερη από μια που '
          'ξεχειλίζει',
    );

    await tester.pump(const Duration(seconds: 11));
  }, semanticsEnabled: false);
}
