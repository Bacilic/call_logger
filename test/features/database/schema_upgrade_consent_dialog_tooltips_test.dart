// Επεξηγήσεις (tooltips) στα κουμπιά του διαλόγου συγκατάθεσης αναβάθμισης.
//
//   flutter test test/features/database/schema_upgrade_consent_dialog_tooltips_test.dart

import 'package:call_logger/features/database/services/database_upgrade_copy_service.dart';
import 'package:call_logger/features/database/widgets/schema_upgrade_consent_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Iterable<String> _tooltipMessages(WidgetTester tester) {
  return tester.widgetList<Tooltip>(find.byType(Tooltip)).map((tooltip) {
    final rich = tooltip.richMessage;
    if (rich is WidgetSpan) {
      final child = rich.child;
      if (child is ConstrainedBox) {
        final text = child.child;
        if (text is Text) return text.data ?? '';
      }
    }
    return tooltip.message ?? '';
  });
}

void main() {
  const dbPath = r'F:\Data Base\Δοκιμές\παλιά_βάση_2023.db';

  testWidgets('τα τρία κουμπιά έχουν κατατοπιστικές επεξηγήσεις', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () => showSchemaUpgradeConsentDialog(
                context: context,
                dbPath: dbPath,
                fileSchemaVersion: 30,
                appSchemaVersion: 36,
              ),
              child: const Text('άνοιγμα'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('άνοιγμα'));
    await tester.pumpAndSettle();

    final messages = _tooltipMessages(tester).toList();

    expect(
      messages.any(
        (m) =>
            m.contains('παλιά_βάση_2023.db') &&
            m.contains('οριστικοποιηθεί') &&
            m.contains('μη αναστρέψιμη'),
      ),
      isTrue,
      reason: 'Το κουμπί του πρωτοτύπου πρέπει να εξηγεί τη μόνιμη αλλαγή',
    );

    final expectedCopyName = upgradeCopyFileName(dbPath);
    expect(
      messages.any(
        (m) => m.contains(expectedCopyName) && m.contains('αντίγραφο'),
      ),
      isTrue,
      reason: 'Το κουμπί του αντιγράφου πρέπει να δείχνει το όνομα αντιγράφου',
    );

    expect(
      messages.any((m) => m.contains('Δεν γίνεται καμία αλλαγή')),
      isTrue,
      reason: 'Το Άκυρο πρέπει να δηλώνει ότι δεν αλλάζει τίποτα',
    );
  });

  test('το προβλεπόμενο όνομα αντιγράφου ακολουθεί το πρότυπο', () {
    final name = upgradeCopyFileName(dbPath, now: DateTime(2026, 7, 25));
    expect(name, 'παλιά_βάση_2023_αναβαθμισμένη_25-07-2026.db');
  });
}
