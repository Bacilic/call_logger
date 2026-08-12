// Πλευρική μπάρα — συμπεριφορά: το κουμπί Ρυθμίσεων ανοίγει την οθόνη του και
// το πλάτος της μπάρας ακολουθεί τα κουμπιά που είναι όντως ορατά.
//
// Πολιτική Ελέγχων (Κ2): εδώ ΔΕΝ ελέγχονται στοιχίσεις, αποστάσεις ή θέσεις
// pixel — αυτά επαληθεύονται οπτικά. Φυλάμε μόνο «πάτησα Χ → άνοιξε Ψ» και
// «έκρυψα κουμπιά → η μπάρα στένεψε».
//
//   flutter test test/core/widgets/main_shell_nav_rail_layout_test.dart

import 'package:call_logger/core/providers/settings_provider.dart';
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
}) async {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });

  await tester.runAsync(() async {
    // Η προτίμηση «ανοιχτή μπάρα» αποθηκεύεται στη βάση: χωρίς μηδενισμό, ένα
    // τεστ που πατά το κουμπί σύμπτυξης αλλάζει την αφετηρία του επόμενου.
    await SettingsService().windowUi.setNavRailShowLabels(true);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          ...callLoggerTestProviderOverrides(showDatabaseNav: showDatabaseNav),
          showLampNavProvider.overrideWith((ref) async => showLampNav),
          enableSpellCheckProvider.overrideWith((ref) async => enableSpellCheck),
        ],
        child: const MyApp(showStartupSplash: false),
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
