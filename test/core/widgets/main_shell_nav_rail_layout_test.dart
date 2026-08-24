// Πλευρική μπάρα — συμπεριφορά: το κουμπί Ρυθμίσεων ανοίγει την οθόνη του και
// το πλάτος της μπάρας ακολουθεί τα κουμπιά που είναι όντως ορατά.
//
// Πολιτική Ελέγχων (Κ2): εδώ ΔΕΝ ελέγχονται στοιχίσεις, αποστάσεις ή θέσεις
// pixel — αυτά επαληθεύονται οπτικά. Φυλάμε μόνο «πάτησα Χ → άνοιξε Ψ» και
// «έκρυψα κουμπιά → η μπάρα στένεψε».
//
//   flutter test test/core/widgets/main_shell_nav_rail_layout_test.dart

import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/providers/settings_provider.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/widgets/main_nav_destination.dart';
import 'package:call_logger/core/widgets/main_nav_rail_metrics.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/settings/screens/settings_screen.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<void> _pumpShell(
  WidgetTester tester, {
  required bool showLampNav,
  required bool showDatabaseNav,
  required bool enableSpellCheck,
  Size size = const Size(1600, 900),
  bool showLabels = true,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.runAsync(() async {
    // Η προτίμηση «ανοιχτή μπάρα» αποθηκεύεται στη βάση: χωρίς μηδενισμό, ένα
    // τεστ που πατά το κουμπί σύμπτυξης αλλάζει την αφετηρία του επόμενου.
    await SettingsService().windowUi.setNavRailShowLabels(showLabels);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...callLoggerTestProviderOverrides(showDatabaseNav: showDatabaseNav),
          showLampNavProvider.overrideWith((ref) async => showLampNav),
          enableSpellCheckProvider.overrideWith(
            (ref) async => enableSpellCheck,
          ),
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

double _dividerLeft(WidgetTester tester) =>
    tester.getRect(find.byType(VerticalDivider).first).left;

Future<void> _flushSqfliteLockTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
}

Future<void> _openSettings(WidgetTester tester) async {
  await tester.tap(find.byKey(const ValueKey('nav_rail_settings')));
  await pumpUntilSettled(tester);
  expect(find.byType(SettingsScreen), findsOneWidget);
}

/// Κλείσιμο ώστε να μη μείνει ανοιχτή διαδρομή στο τέλος του ελέγχου.
Future<void> _closeSettings(WidgetTester tester) async {
  Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
  await pumpUntilSettled(tester);
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUpAll(() async {
    LookupService.instance.resetForReload();
    await LookupService.instance.loadFromDatabase();
  });

  group('πλευρική μπάρα — συμπεριφορά', () {
    testWidgets('το κουμπί Ρυθμίσεων ανοίγει την οθόνη Ρυθμίσεων', (
      tester,
    ) async {
      await _pumpShell(
        tester,
        showLampNav: true,
        showDatabaseNav: true,
        enableSpellCheck: true,
      );

      await tester.tap(find.byKey(const ValueKey('nav_rail_settings')));
      await pumpUntilSettled(tester);

      expect(find.byType(SettingsScreen), findsOneWidget);

      // Κλείσιμο της οθόνης ώστε να μη μείνει ανοιχτή διαδρομή στο τέλος.
      Navigator.of(tester.element(find.byType(SettingsScreen))).pop();
      await pumpUntilSettled(tester);

      await _flushSqfliteLockTimers(tester);
    });

    testWidgets('η ρύθμιση απόκρυψης της Βάσης υπάρχει όταν επιτρέπεται', (
      tester,
    ) async {
      // Θετικός μάρτυρας: χωρίς αυτόν, ο επόμενος έλεγχος θα περνούσε ακόμη κι
      // αν η γραμμή έλειπε για εντελώς άλλον λόγο.
      await _pumpShell(
        tester,
        showLampNav: true,
        showDatabaseNav: true,
        enableSpellCheck: true,
      );

      await _openSettings(tester);
      expect(find.text('Απόκρυψη Βάσης Δεδομένων'), findsOneWidget);

      await _closeSettings(tester);
      await _flushSqfliteLockTimers(tester);
    });

    testWidgets('χωρίς το δικαίωμα λείπει και η ρύθμιση που το αφορά', (
      tester,
    ) async {
      CurrentOperator.activate(
        Operator(
          id: 77,
          displayName: 'Δοκιμαστικός',
          permissionOverrides: {AppPermission.browseDatabase.key: false},
          createdAt: DateTime(2026, 8, 21),
        ),
      );
      addTearDown(CurrentOperator.reset);

      await _pumpShell(
        tester,
        showLampNav: true,
        showDatabaseNav: true,
        enableSpellCheck: true,
      );

      await _openSettings(tester);
      expect(
        find.text('Απόκρυψη Βάσης Δεδομένων'),
        findsNothing,
        reason:
            'Ο προορισμός είναι ήδη κρυμμένος από το δικαίωμα, οπότε ο '
            'διακόπτης δεν αλλάζει τίποτα σε καμία θέση. Ρύθμιση που δεν κάνει '
            'τίποτα κάνει τον χρήστη να νομίζει ότι κάτι χάλασε.',
      );

      await _closeSettings(tester);
      await _flushSqfliteLockTimers(tester);
    });

    testWidgets('χαμηλό παράθυρο: η μπάρα κυλά αντί να ξεχειλίζει', (
      tester,
    ) async {
      // Πραγματικό σφάλμα χρήστη, 24/08/2026: εννέα κουμπιά σε συμπτυγμένη
      // μπάρα ξεχείλιζαν κατά 9 pixel σε κάθε αλλαγή οθόνης. Η NavigationRail
      // δεν κυλά μόνη της· την τυλίγουμε εμείς.
      //
      // **Το ύψος εδώ ΔΕΝ είναι το ύψος του χρήστη.** Στο δικό του μηχάνημα
      // έπαιζε ρόλο και η κλίμακα οθόνης των Windows, που δεν αναπαράγεται
      // εύκολα σε τεστ. Αυτό που φυλάγεται δεν είναι ένας αριθμός αλλά ο
      // κανόνας: **όταν δεν χωρά, κυλά** — γι' αυτό το ύψος διαλέγεται τόσο
      // χαμηλό ώστε να μη χωρά με βεβαιότητα, και η δεύτερη προσδοκία το
      // επιβεβαιώνει αντί να το υποθέτει.
      //
      // Η μπάρα στήνεται **συμπτυγμένη επίτηδες**: εκεί κάθε κουμπί πιάνει
      // περισσότερο ύψος από ό,τι με λεζάντες.
      await _pumpShell(
        tester,
        showLampNav: true,
        showDatabaseNav: true,
        enableSpellCheck: true,
        showLabels: false,
        size: const Size(1290, 420),
      );

      expect(
        tester.takeException(),
        isNull,
        reason:
            'Χαμηλό παράθυρο: η πλευρική μπάρα οφείλει να κυλά, όχι να '
            'ξεχειλίζει.',
      );

      // Απόδειξη ότι ο έλεγχος φυλάει κάτι: σε αυτό το ύψος το περιεχόμενο
      // ΟΝΤΩΣ δεν χωρά. Χωρίς αυτό, το τεστ θα έμενε πράσινο ακόμη κι αν το
      // παράθυρο μεγάλωνε τόσο που να μη στενεύει ποτέ τίποτα.
      final position = tester
          .state<ScrollableState>(
            find
                .ancestor(
                  of: find.byType(NavigationRail),
                  matching: find.byType(Scrollable),
                )
                .first,
          )
          .position;
      expect(
        position.maxScrollExtent,
        greaterThan(0),
        reason:
            'Αν χωρούσε, το τεστ δεν θα δοκίμαζε τίποτα — ανέβασε τα κουμπιά ή '
            'χαμήλωσε το παράθυρο.',
      );

      await _flushSqfliteLockTimers(tester);
    });

    testWidgets('με κρυμμένα κουμπιά η μπάρα στενεύει', (tester) async {
      await _pumpShell(
        tester,
        showLampNav: false,
        showDatabaseNav: false,
        enableSpellCheck: false,
      );

      expect(find.byKey(const ValueKey('nav_rail_database')), findsNothing);
      expect(find.byKey(const ValueKey('nav_rail_dictionary')), findsNothing);
      expect(find.byKey(const ValueKey('nav_rail_lamp')), findsNothing);

      // Το πλάτος που θα είχε η μπάρα αν ήταν όλα τα κουμπιά ορατά — η ορατή
      // μπάρα οφείλει να είναι στενότερη, αφού λείπουν οι μεγάλες λεζάντες.
      final railLabelStyle =
          Theme.of(
            tester.element(find.byType(NavigationRail)),
          ).textTheme.labelMedium ??
          const TextStyle();
      final widthWithEverything = mainNavRailExtendedWidth(
        labels: [
          for (final d in MainNavDestination.values) d.label,
          kMainNavSettingsLabel,
        ],
        style: railLabelStyle,
      );

      expect(_dividerLeft(tester), lessThan(widthWithEverything));

      await _flushSqfliteLockTimers(tester);
    });
  });
}
