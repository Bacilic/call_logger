// Παράθυρο «Επαναφορά ολοκληρώθηκε»: κάθε στοιχείο της αναφοράς αποδίδεται ως
// γραμμή με το σωστό εικονίδιο κατάστασης (η κατάσταση είναι συμπεριφορά),
// μαζί με τη διαδρομή φύλαξης της προηγούμενης βάσης και τις προειδοποιήσεις.
//
//   flutter test test/features/database/widgets/restore_report_dialog_test.dart --timeout 30s

import 'package:call_logger/features/database/services/restore_report.dart';
import 'package:call_logger/features/database/widgets/restore_report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_reporter.dart';

Future<void> _pumpDialog(
  WidgetTester tester, {
  required List<RestoreReportItem> items,
  String? fallbackText,
  String? preRestoreBackupPath,
  List<String> warnings = const <String>[],
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => showRestoreReportDialog(
                context: context,
                items: items,
                fallbackText: fallbackText,
                preRestoreBackupPath: preRestoreBackupPath,
                warnings: warnings,
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('κάθε στοιχείο αποδίδεται με το εικονίδιο της κατάστασής του', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      items: const [
        RestoreReportItem(
          label: 'Βάση',
          detail: 'Επαναφέρθηκε',
          status: RestoreReportStatus.success,
        ),
        RestoreReportItem(
          label: 'Κατόψεις',
          detail: 'Δεν βρέθηκαν στο συμπιεσμένο αρχείο',
          status: RestoreReportStatus.warning,
        ),
        RestoreReportItem(
          label: 'Βάση Λάμπας',
          detail: 'Αποτυχία επαναφοράς',
          status: RestoreReportStatus.failure,
        ),
      ],
      preRestoreBackupPath: r'F:\data\hosp_pre_restore_03-08-2026.db',
    );

    expect(find.textContaining('Βάση: '), findsWidgets);
    expect(
      find.textContaining('Δεν βρέθηκαν στο συμπιεσμένο αρχείο'),
      findsOneWidget,
    );
    expect(
      find.byIcon(Icons.check_circle_rounded),
      findsOneWidget,
      reason: greekExpectMsg('Η επιτυχία σημαίνεται με δικό της εικονίδιο'),
    );
    expect(
      find.byIcon(Icons.warning_amber_rounded),
      findsOneWidget,
      reason: greekExpectMsg(
        'Το «δεν βρέθηκε» είναι προειδοποίηση — όχι επιτυχία, όχι σφάλμα',
      ),
    );
    expect(
      find.byIcon(Icons.error_rounded),
      findsOneWidget,
      reason: greekExpectMsg('Η αποτυχία σημαίνεται ως σφάλμα'),
    );
    expect(
      find.textContaining('Η προηγούμενη βάση φυλάχτηκε στο:'),
      findsOneWidget,
    );
  });

  testWidgets('οι προειδοποιήσεις εμφανίζονται ως λίστα', (tester) async {
    await _pumpDialog(
      tester,
      items: const [
        RestoreReportItem(
          label: 'Βάση',
          detail: 'Επαναφέρθηκε',
          status: RestoreReportStatus.success,
        ),
      ],
      warnings: const ['Αποτυχία αντιγραφής «x.png»: χωρίς δικαιώματα'],
    );

    expect(find.text('Προειδοποιήσεις'), findsOneWidget);
    expect(find.textContaining('x.png'), findsOneWidget);
  });

  testWidgets('χωρίς στοιχεία αναφοράς, δείχνει το εφεδρικό κείμενο', (
    tester,
  ) async {
    await _pumpDialog(
      tester,
      items: const [],
      fallbackText: 'Το αρχείο zip δεν βρέθηκε.',
    );

    expect(find.text('Το αρχείο zip δεν βρέθηκε.'), findsOneWidget);
  });
}
