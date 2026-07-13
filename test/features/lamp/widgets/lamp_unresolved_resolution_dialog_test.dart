import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
// ignore: unnecessary_import
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_models.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:call_logger/features/lamp/widgets/lamp_entity_code_autocomplete.dart';
import 'package:call_logger/features/lamp/widgets/lamp_unresolved_resolution_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;
  late LampIssueResolutionService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-unresolved-dialog-');
    dbPath = p.join(tempDir.path, 'lamp.sqlite');
    service = LampIssueResolutionService();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('offices', <String, Object?>{
        'office': 1,
        'office_name': 'Βασικό Γραφείο',
      });
      await db.insert('offices', <String, Object?>{
        'office': 2,
        'office_name': 'Δευτερεύον Γραφείο',
      });
      await db.insert('model', <String, Object?>{
        'model': 1,
        'model_name': 'Model Base',
      });
      await db.insert('equipment', <String, Object?>{
        'code': 5001,
        'description': 'Εξοπλισμός δοκιμής',
        'model': 1,
        'office_original_text': 'Άγνωστο',
      });
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    if (await tempDir.exists()) {
      await tempDir.delete(recursive: true);
    }
  });

  LampIssueResolutionProposal officeProposal() {
    return LampIssueResolutionProposal(
      issueType: LampIssueType.unknownId,
      issueIds: const <int>[1],
      sheet: 'integrity_scan',
      row: 5001,
      column: 'office',
      originalValue: '999',
      proposedAction: LampIssueResolutionAction.unresolved,
      confidence: 0,
      notes: 'Δεν βρέθηκε έγκυρο γραφείο.',
      metadata: const <String, Object?>{
        'diagnosticEntityType': 'equipment',
        'diagnosticOrigin': 'integrity_scan',
        'diagnosticType': 'fk_resolution_unsupported_column',
      },
    );
  }

  Future<String?> fakeLookup(String column, int targetId) async {
    if (targetId == 1) return 'Βασικό Γραφείο';
    return null;
  }

  Future<List<LampEntityCodeSuggestion>> mockOfficeSearch(
    String column,
    String query,
  ) async {
    return filterEntityCodeSuggestions(
      const <LampEntityCodeSuggestion>[
        LampEntityCodeSuggestion(code: 1, label: 'Βασικό Γραφείο'),
        LampEntityCodeSuggestion(code: 2, label: 'Δευτερεύον Γραφείο'),
      ],
      query,
    );
  }

  Future<void> dismissOpenDialog(WidgetTester tester) async {
    if (find.byType(ListView).evaluate().isNotEmpty) {
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pump();
    }
    if (find.text('Ακύρωση επίλυσης').evaluate().isNotEmpty) {
      final cancel = find.text('Ακύρωση επίλυσης');
      await tester.ensureVisible(cancel);
      await tester.tap(cancel, warnIfMissed: false);
      await tester.pump();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pump();
  }

  Future<void> openDialog(
    WidgetTester tester, {
    required void Function(LampUnresolvedResolutionOutcome?) onResult,
    LampManualFkLookup? manualFkLookup,
    LampEntityCodeSearch? entityCodeSearch,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () async {
                  onResult(
                    await showLampUnresolvedResolutionDialog(
                      context: context,
                      proposal: officeProposal(),
                      databasePath: dbPath,
                      resolutionService: service,
                      manualFkLookup: manualFkLookup,
                      entityCodeSearch: entityCodeSearch,
                    ),
                  );
                },
                child: const Text('Άνοιγμα'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('Άνοιγμα'));
    await tester.pumpAndSettle();
  }

  group('LampUnresolvedResolutionDialog', () {
    test('searchManualFkTargets επιστρέφει γραφείο για μερικό όνομα', () async {
      final results = await service.searchManualFkTargets(
        databasePath: dbPath,
        column: 'office',
        query: 'βασικ',
      );
      expect(results, isNotEmpty);
      expect(results.first.code, 1);
      expect(results.first.label, contains('Βασικό'));
    });

    testWidgets('εμφανίζει τις νέες ενέργειες δίπλα στις υπάρχουσες', (tester) async {
      await openDialog(tester, onResult: (_) {});

      expect(find.text('Ακύρωση επίλυσης'), findsOneWidget);
      expect(find.text('Παράλειψη όλων των ανεπίλυτων'), findsOneWidget);
      expect(find.text('Παράλειψη τρέχουσας'), findsOneWidget);
      expect(find.text('Διόρθωση με κωδικό'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Εκκαθάριση πεδίου'), findsOneWidget);
      expect(find.text('Αναβολή'), findsOneWidget);
      expect(find.text('Αναβολή όλων των ανεπίλυτων'), findsOneWidget);

      await dismissOpenDialog(tester);
    });

    testWidgets('έγκυρος αριθμητικός κωδικός εμφανίζει ετικέτα και ενεργοποιεί εφαρμογή', (
      tester,
    ) async {
      LampUnresolvedResolutionOutcome? captured;
      await openDialog(
        tester,
        manualFkLookup: fakeLookup,
        onResult: (outcome) => captured = outcome,
      );

      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      expect(find.textContaining('Βασικό Γραφείο'), findsOneWidget);

      final applyButton = find.widgetWithText(FilledButton, 'Εφαρμογή κωδικού');
      expect(tester.widget<FilledButton>(applyButton).onPressed, isNotNull);

      await tester.ensureVisible(applyButton);
      await tester.tap(applyButton);
      await tester.pump();

      expect(captured, isA<LampUnresolvedSetFieldManual>());
      expect((captured! as LampUnresolvedSetFieldManual).codeInput, '1');
    });

    testWidgets('ανύπαρκτος κωδικός κρατά απενεργοποιημένη την εφαρμογή', (
      tester,
    ) async {
      await openDialog(
        tester,
        manualFkLookup: fakeLookup,
        onResult: (_) {},
      );

      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '99999');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      final applyButton = find.widgetWithText(FilledButton, 'Εφαρμογή κωδικού');
      expect(tester.widget<FilledButton>(applyButton).onPressed, isNull);

      await dismissOpenDialog(tester);
    });

    testWidgets('Εκκαθάριση πεδίου επιστρέφει LampUnresolvedClearField', (
      tester,
    ) async {
      LampUnresolvedResolutionOutcome? captured;
      await openDialog(
        tester,
        onResult: (outcome) => captured = outcome,
      );

      final clearButton = find.widgetWithText(OutlinedButton, 'Εκκαθάριση πεδίου');
      await tester.ensureVisible(clearButton);
      await tester.tap(clearButton);
      await tester.pump();

      expect(captured, isA<LampUnresolvedClearField>());
    });

    testWidgets('Αναβολή επιστρέφει LampUnresolvedDeferCurrent', (tester) async {
      LampUnresolvedResolutionOutcome? captured;
      await openDialog(
        tester,
        onResult: (outcome) => captured = outcome,
      );

      await tester.tap(find.text('Αναβολή'));
      await tester.pump();

      expect(captured, isA<LampUnresolvedDeferCurrent>());
    });

    testWidgets('Αναβολή όλων επιστρέφει LampUnresolvedDeferAll', (tester) async {
      LampUnresolvedResolutionOutcome? captured;
      await openDialog(
        tester,
        onResult: (outcome) => captured = outcome,
      );

      await tester.tap(find.text('Αναβολή όλων των ανεπίλυτων'));
      await tester.pump();

      expect(captured, isA<LampUnresolvedDeferAll>());
    });

    testWidgets('η διόρθωση με κωδικό χρησιμοποιεί autocomplete πεδίο', (
      tester,
    ) async {
      await openDialog(tester, onResult: (_) {});

      expect(find.byType(LampEntityCodeAutocomplete), findsOneWidget);
      expect(find.text('Κωδικός ή όνομα γραφείο'), findsOneWidget);

      await dismissOpenDialog(tester);
    });

    testWidgets('entityCodeSearch καλείται κατά την πληκτρολόγηση στο πεδίο', (
      tester,
    ) async {
      var searchCalled = false;
      await openDialog(
        tester,
        entityCodeSearch: (column, query) async {
          searchCalled = true;
          expect(column, 'office');
          return mockOfficeSearch(column, query);
        },
        onResult: (_) {},
      );

      final field = find.byType(TextField);
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'βασικ');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(searchCalled, isTrue);

      await dismissOpenDialog(tester);
    });

    testWidgets('απευθείας πληκτρολόγηση κωδικού συνεχίζει να λειτουργεί', (
      tester,
    ) async {
      LampUnresolvedResolutionOutcome? captured;
      await openDialog(
        tester,
        manualFkLookup: fakeLookup,
        onResult: (outcome) => captured = outcome,
      );

      await tester.ensureVisible(find.byType(TextField));
      await tester.enterText(find.byType(TextField), '1');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.pump();

      final applyButton = find.widgetWithText(FilledButton, 'Εφαρμογή κωδικού');
      expect(tester.widget<FilledButton>(applyButton).onPressed, isNotNull);

      await tester.ensureVisible(applyButton);
      await tester.tap(applyButton);
      await tester.pump();

      expect(captured, isA<LampUnresolvedSetFieldManual>());
      expect((captured! as LampUnresolvedSetFieldManual).codeInput, '1');
    });
  });
}
