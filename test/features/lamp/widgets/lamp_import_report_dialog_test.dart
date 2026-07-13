import 'package:call_logger/core/database/old_database/old_excel_importer.dart';
import 'package:call_logger/features/lamp/widgets/lamp_import_report_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('LampImportReportDialog', () {
    testWidgets('phase A shows progress without dismiss or cancel', (tester) async {
      final progressNotifier = ValueNotifier<LampImportProgressUiState>(
        const LampImportProgressUiState(
          currentMessage: 'Ανάγνωση Excel',
          completedSteps: <String>['Προετοιμασία'],
          done: 1,
          total: 5,
        ),
      );
      final reportNotifier = ValueNotifier<LampImportReportUiState?>(null);
      addTearDown(progressNotifier.dispose);
      addTearDown(reportNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => LampImportReportDialog(
                          progressListenable: progressNotifier,
                          reportListenable: reportNotifier,
                        ),
                      );
                    },
                    child: const Text('Άνοιγμα'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pump();

      expect(find.text('Εισαγωγή Excel στη βάση'), findsOneWidget);
      expect(find.text('Ανάγνωση Excel'), findsOneWidget);
      expect(find.text('Προετοιμασία'), findsOneWidget);
      expect(find.byIcon(Icons.check_circle_outline), findsWidgets);
      expect(find.text('Κλείσιμο'), findsNothing);
      expect(find.text('Ακύρωση'), findsNothing);
    });

    testWidgets('phase B success shows headline and integrity action', (tester) async {
      final progressNotifier = ValueNotifier<LampImportProgressUiState>(
        const LampImportProgressUiState(
          currentMessage: 'Ολοκληρώθηκε',
          completedSteps: <String>['Ανάγνωση Excel'],
        ),
      );
      final reportNotifier = ValueNotifier<LampImportReportUiState?>(
        LampImportReportUiState.success(
          databaseFileName: 'lamp_out.db',
          durationSeconds: 12,
          importedRows: const <String, int>{
            'offices': 5,
            'owners': 10,
            'equipment': 0,
          },
          issueCount: 3,
        ),
      );
      addTearDown(progressNotifier.dispose);
      addTearDown(reportNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      showDialog<LampImportReportCloseAction>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => LampImportReportDialog(
                          progressListenable: progressNotifier,
                          reportListenable: reportNotifier,
                        ),
                      );
                    },
                    child: const Text('Άνοιγμα'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

      expect(
        find.text(lampImportSuccessHeadline('lamp_out.db')),
        findsOneWidget,
      );
      expect(find.text('Εγγραφές που εισήχθησαν'), findsOneWidget);
      expect(find.textContaining('Γραφεία / Τμήματα'), findsOneWidget);
      expect(find.textContaining('0 — ελέγξτε το φύλλο στο Excel'), findsOneWidget);
      expect(find.textContaining('Προβλήματα ETL: 3'), findsOneWidget);
      expect(
        find.textContaining('Συνιστάται πλήρης έλεγχος'),
        findsOneWidget,
      );
      expect(find.text('Κλείσιμο'), findsOneWidget);
      expect(find.text('Έλεγχος για προβλήματα'), findsOneWidget);

      await tester.tap(find.text('Έλεγχος για προβλήματα'));
      await tester.pumpAndSettle();
      expect(
        find.byType(LampImportReportDialog),
        findsNothing,
      );
    });

    testWidgets('phase B failure shows error with copy and only close',
        (tester) async {
      final progressNotifier = ValueNotifier<LampImportProgressUiState>(
        const LampImportProgressUiState(
          currentMessage: 'Ανάγνωση Excel',
          completedSteps: <String>[],
        ),
      );
      final reportNotifier = ValueNotifier<LampImportReportUiState?>(
        LampImportReportUiState.failure(
          errorMessage: 'Σφάλμα δοκιμής import',
        ),
      );
      addTearDown(progressNotifier.dispose);
      addTearDown(reportNotifier.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Builder(
            builder: (context) {
              return Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () {
                      showDialog<void>(
                        context: context,
                        barrierDismissible: false,
                        builder: (_) => LampImportReportDialog(
                          progressListenable: progressNotifier,
                          reportListenable: reportNotifier,
                        ),
                      );
                    },
                    child: const Text('Άνοιγμα'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.tap(find.text('Άνοιγμα'));
      await tester.pumpAndSettle();

      expect(find.text('Η εισαγωγή απέτυχε'), findsOneWidget);
      expect(find.text('Σφάλμα δοκιμής import'), findsOneWidget);
      expect(find.text('Αντιγραφή σφάλματος'), findsOneWidget);
      expect(find.textContaining('ημιτελές'), findsOneWidget);
      expect(find.text('Κλείσιμο'), findsOneWidget);
      expect(find.text('Έλεγχος για προβλήματα'), findsNothing);
    });
  });

  group('lampImportProgressUiStateFromProgress', () {
    test('accumulates completed steps when message changes', () {
      var state = const LampImportProgressUiState(currentMessage: '');
      state = lampImportProgressUiStateFromProgress(
        state,
        const LampImportProgress('Ανάγνωση Excel'),
      );
      state = lampImportProgressUiStateFromProgress(
        state,
        const LampImportProgress('Εισαγωγή offices', done: 1, total: 5),
      );
      expect(state.completedSteps, <String>['Ανάγνωση Excel']);
      expect(state.currentMessage, 'Εισαγωγή offices');
      expect(state.done, 1);
      expect(state.total, 5);
    });
  });
}
