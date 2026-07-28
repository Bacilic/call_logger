// ChangelogDialog — η κατάσταση «κλειστό/ανοιχτό» κάθε έκδοσης πρέπει να
// επιβιώνει την ανακύκλωση του ListView: κλείνεις την πρώτη έκδοση,
// σκρολάρεις κάτω, επιστρέφεις πάνω — δεν επιτρέπεται να τη βρεις ξανά
// ανοιχτή επειδή το στοιχείο ξαναχτίστηκε με την προεπιλογή «ανοιχτό».
//
//   flutter test test/core/about/changelog_dialog_expansion_state_test.dart

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

List<ChangelogEntry> _manyEntries(int count) => [
  for (var i = 0; i < count; i++)
    ChangelogEntry(
      version: '0.${count - i}.0',
      date: '2026-07-01',
      added: i == 0
          ? const [_firstEntryMarker]
          : ['Καταχώρηση $i α', 'Καταχώρηση $i β'],
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
          changelogProvider.overrideWith((ref) async => _manyEntries(30)),
          updateCheckProvider.overrideWith(
            (ref) async => const UpdateCheckResult.none(),
          ),
        ],
        child: const MaterialApp(home: Scaffold(body: ChangelogDialog())),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
    'κλειστή πρώτη έκδοση παραμένει κλειστή μετά από κύλιση έξω και πίσω',
    (tester) async {
      await pumpDialog(tester);

      // Αρχικά η πρώτη έκδοση είναι ανοιχτή (προεπιλογή).
      expect(find.text(_firstEntryMarker), findsOneWidget);

      // Ο χρήστης την κλείνει.
      const firstHeader = 'v0.30.0 — 2026-07-01';
      await tester.tap(find.text(firstHeader));
      await tester.pumpAndSettle();
      expect(find.text(_firstEntryMarker), findsNothing);

      // Κύλιση μακριά (το στοιχείο ανακυκλώνεται/καταστρέφεται)…
      await tester.drag(find.byType(ListView), const Offset(0, -3000));
      await tester.pumpAndSettle();
      expect(find.text(firstHeader), findsNothing);

      // …και επιστροφή στην κορυφή.
      await tester.drag(find.byType(ListView), const Offset(0, 3000));
      await tester.pumpAndSettle();

      // Η πρώτη έκδοση πρέπει να είναι ΑΚΟΜΑ κλειστή.
      expect(
        find.text(_firstEntryMarker),
        findsNothing,
        reason:
            'Η κατάσταση «κλειστό» χάθηκε στην ανακύκλωση και η προεπιλογή '
            '«ανοιχτό» ξαναεφαρμόστηκε.',
      );
    },
  );
}
