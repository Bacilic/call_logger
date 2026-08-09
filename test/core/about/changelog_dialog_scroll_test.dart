// ChangelogDialog — κύλιση του ιστορικού αλλαγών.
//
// Ο διάλογος ανακατεύει στην ίδια λίστα μία τεράστια ανοιχτή κάρτα (εκατοντάδες
// pixel κειμένου) με δεκάδες μικροσκοπικές κλειστές κάρτες. Αν ο κύλινδρος
// μαντεύει το συνολικό ύψος από τον μέσο όρο των ορατών στοιχείων, η εκτίμηση
// καταρρέει τη στιγμή που εμφανίζονται οι κλειστές κάρτες — και το σύρσιμο της
// μπάρας κύλισης μεταπηδά απότομα, επειδή αλλάζει ο συντελεστής «θέση μπάρας →
// θέση κειμένου» ενώ ο χρήστης κρατάει πατημένο το ποντίκι.
//
//   flutter test test/core/about/changelog_dialog_scroll_test.dart

import 'dart:math' as math;

import 'package:call_logger/core/about/models/changelog_entry.dart';
import 'package:call_logger/core/about/providers/app_version_provider.dart';
import 'package:call_logger/core/about/providers/changelog_provider.dart';
import 'package:call_logger/core/about/widgets/changelog_dialog.dart';
import 'package:call_logger/core/updates/update_check_result.dart';
import 'package:call_logger/core/updates/update_providers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

const String _firstEntryMarker = 'πρώτη-εγγραφή-δείκτης';
const String _firstHeader = 'v0.30.0 — 2026-07-01';

/// Μία πολύ ψηλή πρώτη έκδοση (ανοιχτή από προεπιλογή) και 29 πολύ κοντές
/// κλειστές — ακριβώς η αναλογία που έχει το πραγματικό ιστορικό.
List<ChangelogEntry> _tallFirstThenShortEntries() => [
  ChangelogEntry(
    version: '0.30.0',
    date: '2026-07-01',
    added: [
      _firstEntryMarker,
      for (var i = 0; i < 40; i++)
        'Εκτενής περιγραφή αλλαγής $i που πιάνει αρκετές γραμμές κειμένου '
            'ώστε η ανοιχτή κάρτα να γίνει πολλαπλάσια σε ύψος από τις κλειστές.',
    ],
    improvements: const [],
    changed: const [],
    fixed: const [],
  ),
  for (var i = 1; i < 30; i++)
    ChangelogEntry(
      version: '0.${30 - i}.0',
      date: '2026-06-01',
      added: const ['Μία σύντομη γραμμή'],
      improvements: const [],
      changed: const [],
      fixed: const [],
    ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> pumpDialog(WidgetTester tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appVersionProvider.overrideWith((ref) async => '0.30.0'),
          changelogProvider.overrideWith(
            (ref) async => _tallFirstThenShortEntries(),
          ),
          updateCheckProvider.overrideWith(
            (ref) async => const UpdateCheckResult.none(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ChangelogDialog())),
      ),
    );
    await tester.pumpAndSettle();
  }

  ScrollPosition scrollPosition(WidgetTester tester) => tester
      .state<ScrollableState>(
        find
            .descendant(
              of: find.byType(ChangelogDialog),
              matching: find.byType(Scrollable),
            )
            .first,
      )
      .position;

  /// Κύλιση ως το τέλος σε μικρά βήματα — έτσι σέρνει ο χρήστης τη μπάρα.
  Future<void> scrollToBottomInSteps(
    WidgetTester tester,
    ScrollPosition position,
  ) async {
    var guard = 0;
    while (position.pixels < position.maxScrollExtent && guard++ < 500) {
      position.jumpTo(
        math.min(position.pixels + 150, position.maxScrollExtent),
      );
      await tester.pump();
    }
  }

  testWidgets('το συνολικό ύψος κύλισης δεν αλλάζει καθώς κυλάμε', (
    tester,
  ) async {
    await pumpDialog(tester);

    final position = scrollPosition(tester);
    final extentAtOpen = position.maxScrollExtent;

    await scrollToBottomInSteps(tester, position);

    expect(
      position.maxScrollExtent,
      moreOrLessEquals(extentAtOpen, epsilon: 1.0),
      reason:
          'Το συνολικό ύψος ήταν εκτίμηση και διορθώθηκε στην πορεία — άρα το '
          'σύρσιμο της μπάρας μεταπηδά όταν περνά από τις ανοιχτές κάρτες '
          'στις κλειστές.',
    );
  });

  testWidgets('κλειστή έκδοση παραμένει κλειστή μετά από κύλιση κάτω και πίσω', (
    tester,
  ) async {
    await pumpDialog(tester);

    // Αρχικά η πρώτη έκδοση είναι ανοιχτή (προεπιλογή).
    expect(find.text(_firstEntryMarker), findsOneWidget);

    // Ο χρήστης την κλείνει.
    await tester.tap(find.text(_firstHeader));
    await tester.pumpAndSettle();
    expect(find.text(_firstEntryMarker), findsNothing);

    final position = scrollPosition(tester);
    await scrollToBottomInSteps(tester, position);
    expect(
      position.pixels,
      greaterThan(0),
      reason: 'Η λίστα δεν κύλισε καθόλου — το σενάριο δεν δοκιμάστηκε.',
    );

    position.jumpTo(0);
    await tester.pumpAndSettle();

    expect(
      find.text(_firstEntryMarker),
      findsNothing,
      reason:
          'Η κατάσταση «κλειστό» χάθηκε στην κύλιση και η προεπιλογή «ανοιχτό» '
          'ξαναεφαρμόστηκε.',
    );
  });
}
