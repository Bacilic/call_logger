import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/lamp_scientific_serial.dart';
import 'package:call_logger/features/lamp/widgets/lamp_issue_manual_review_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _newValueOption = LampIssueResolutionOption(
  id: 'test_reassign_5001',
  label: 'Δώσε νέα τιμή στο code 5001',
  action: LampIssueResolutionAction.autoFix,
  requiresTextInput: true,
  inputLabel: 'Νέα τιμή',
);

const _testProposal = LampIssueResolutionProposal(
  issueType: LampIssueType.duplicateAssetNo,
  issueIds: <int>[1],
  sheet: 'integrity_scan',
  row: 5001,
  column: 'asset_no',
  originalValue: '12345',
  proposedAction: LampIssueResolutionAction.manualReview,
  confidence: 45,
  notes: 'Δοκιμαστική πρόταση χειροκίνητης επισκόπησης.',
  metadata: <String, Object?>{'confidenceIsNominal': true},
  options: <LampIssueResolutionOption>[_newValueOption],
);

const _scientificSerialOption = LampIssueResolutionOption(
  id: 'scientific_serial_reassign_3100',
  label: 'Καταχώρηση νέου σειριακού',
  action: LampIssueResolutionAction.manualReview,
  requiresTextInput: true,
  inputLabel: 'Νέος σειριακός',
  metadata: <String, Object?>{
    'operation': 'reassign_scientific_serial',
    'targetCode': 3100,
    'cleanDigits': '4928',
    'expectedLength': 12,
    'rawSerial': '4,928E+11',
  },
);

const _scientificSerialProposal = LampIssueResolutionProposal(
  issueType: LampIssueType.scientificSerial,
  issueIds: <int>[99],
  sheet: 'integrity_scan',
  row: 3100,
  column: 'serial_no',
  originalValue: '4,928E+11',
  proposedAction: LampIssueResolutionAction.manualReview,
  confidence: 55,
  notes: 'Σειριακός σε επιστημονική μορφή: 4,928E+11',
  metadata: <String, Object?>{
    'cleanDigits': '4928',
    'expectedLength': 12,
    'rawSerial': '4,928E+11',
    'confidenceIsNominal': true,
  },
  options: <LampIssueResolutionOption>[_scientificSerialOption],
);

LampIssueResolutionOption _duplicateGroupOption({
  required String kind,
  required int code,
  required String operation,
  bool requiresTextInput = false,
}) {
  return LampIssueResolutionOption(
    id: 'duplicate_${kind}_$code',
    label: 'option $kind $code',
    action: LampIssueResolutionAction.autoFix,
    requiresTextInput: requiresTextInput,
    inputLabel: requiresTextInput ? 'Νέο asset_no' : null,
    metadata: <String, Object?>{
      'duplicateActionKind': kind,
      'operation': operation,
      if (kind == 'reassign') 'targetCode': code else 'keepCode': code,
    },
  );
}

final _duplicateGroupProposal = LampIssueResolutionProposal(
  issueType: LampIssueType.duplicateAssetNo,
  issueIds: <int>[1, 2, 3],
  sheet: 'integrity_scan',
  row: 2666,
  column: 'asset_no',
  originalValue: 'ASSET-123',
  proposedAction: LampIssueResolutionAction.manualReview,
  confidence: 45,
  notes: 'Ομάδα διπλότυπων (3 εγγραφές)',
  metadata: <String, Object?>{
    'confidenceIsNominal': true,
    'rows': <Map<String, Object?>>[
      <String, Object?>{'code': 2666, 'description': 'Windows 7 Pro 32bit'},
      <String, Object?>{'code': 2667, 'description': 'Windows 7 Pro 64bit'},
      <String, Object?>{'code': 2668, 'description': 'Windows 10'},
    ],
  },
  options: <LampIssueResolutionOption>[
    _duplicateGroupOption(
      kind: 'clear',
      code: 2666,
      operation: 'clear_duplicate_asset_others',
    ),
    _duplicateGroupOption(
      kind: 'clear',
      code: 2667,
      operation: 'clear_duplicate_asset_others',
    ),
    _duplicateGroupOption(
      kind: 'clear',
      code: 2668,
      operation: 'clear_duplicate_asset_others',
    ),
    _duplicateGroupOption(
      kind: 'delete',
      code: 2666,
      operation: 'delete_duplicate_asset_others',
    ),
    _duplicateGroupOption(
      kind: 'delete',
      code: 2667,
      operation: 'delete_duplicate_asset_others',
    ),
    _duplicateGroupOption(
      kind: 'delete',
      code: 2668,
      operation: 'delete_duplicate_asset_others',
    ),
    _duplicateGroupOption(
      kind: 'reassign',
      code: 2666,
      operation: 'reassign_asset',
      requiresTextInput: true,
    ),
    _duplicateGroupOption(
      kind: 'reassign',
      code: 2667,
      operation: 'reassign_asset',
      requiresTextInput: true,
    ),
    _duplicateGroupOption(
      kind: 'reassign',
      code: 2668,
      operation: 'reassign_asset',
      requiresTextInput: true,
    ),
  ],
);

void main() {
  Future<void> pumpManualReviewDialog(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showLampIssueManualReviewDialog(
                    context: context,
                    issueType: LampIssueType.duplicateAssetNo,
                    proposals: const [_testProposal],
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpDuplicateGroupDialog(
    WidgetTester tester, {
    void Function(List<LampIssueResolutionDecision>?)? onResult,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () async {
                  final result = await showLampIssueManualReviewDialog(
                    context: context,
                    issueType: LampIssueType.duplicateAssetNo,
                    proposals: [_duplicateGroupProposal],
                  );
                  onResult?.call(result);
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> pumpScientificSerialDialog(
    WidgetTester tester, {
    required LampSerialExistsChecker serialExistsChecker,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showLampIssueManualReviewDialog(
                    context: context,
                    issueType: LampIssueType.scientificSerial,
                    proposals: const [_scientificSerialProposal],
                    serialExistsChecker: serialExistsChecker,
                  );
                },
                child: const Text('Open'),
              );
            },
          ),
        ),
      ),
    );
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
  }

  Future<void> tearDownDialog(WidgetTester tester) async {
    if (find.text('Άκυρο').evaluate().isNotEmpty) {
      await tester.tap(find.text('Άκυρο'));
      await tester.pumpAndSettle();
    }
    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  }

  testWidgets(
    'η κεφαλίδα κάρτας έχει αντιγράψιμο κωδικό και πεδίο',
    (tester) async {
      await pumpManualReviewDialog(tester);

      expect(
        find.widgetWithText(SelectableText, 'Κωδικός εξοπλισμού: 5001'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(SelectableText, 'Πεδίο: αριθμός παγίου'),
        findsOneWidget,
      );

      await tearDownDialog(tester);
    },
  );

  testWidgets(
    'κρύβει τη βεβαιότητα όταν είναι ονομαστική (confidenceIsNominal)',
    (tester) async {
      await pumpManualReviewDialog(tester);

      expect(find.textContaining('Βεβαιότητα'), findsNothing);

      await tearDownDialog(tester);
    },
  );

  group('ομάδα διπλοτύπων — δομημένη επιλογή', () {
    testWidgets(
      'εμφανίζει dropdown εγγραφής και ακριβώς 4 ραδιοκουμπιά ενέργειας',
      (tester) async {
        await pumpDuplicateGroupDialog(tester);

        expect(find.byType(DropdownButtonFormField<int>), findsOneWidget);
        expect(find.byType(RadioListTile<String?>), findsNWidgets(4));

        await tearDownDialog(tester);
      },
    );

    testWidgets(
      'δεύτερη εγγραφή + διαγραφή → option με delete operation και keepCode',
      (tester) async {
        List<LampIssueResolutionDecision>? captured;
        await pumpDuplicateGroupDialog(
          tester,
          onResult: (result) => captured = result,
        );

        await tester.tap(find.byType(DropdownButtonFormField<int>));
        await tester.pumpAndSettle();
        await tester.tap(find.text('2667 (Windows 7 Pro 64bit)').last);
        await tester.pumpAndSettle();
        await tester.tap(
          find.text('Κράτα την και διέγραψε τις άλλες εγγραφές'),
        );
        await tester.pump();
        await tester.tap(find.widgetWithText(FilledButton, 'Εφαρμογή επιλεγμένων'));
        await tester.pumpAndSettle();

        expect(captured, isNotNull);
        expect(captured!, hasLength(1));
        expect(
          captured!.single.option?.metadata['operation'],
          'delete_duplicate_asset_others',
        );
        expect(captured!.single.option?.metadata['keepCode'], 2667);

        await tearDownDialog(tester);
      },
    );

    testWidgets(
      '«Δώσε νέα τιμή σε αυτή την εγγραφή» εμφανίζει πεδίο εισαγωγής',
      (tester) async {
        await pumpDuplicateGroupDialog(tester);

        expect(find.byType(TextField), findsNothing);
        await tester.tap(find.text('Δώσε νέα τιμή σε αυτή την εγγραφή'));
        await tester.pump();
        expect(find.byType(TextField), findsOneWidget);

        await tearDownDialog(tester);
      },
    );

    testWidgets(
      'κλασική FK πρόταση χωρίς duplicateActionKind → παλιά λίστα, χωρίς dropdown',
      (tester) async {
        await pumpManualReviewDialog(tester);

        expect(find.byType(DropdownButtonFormField<int>), findsNothing);
        expect(find.byType(RadioListTile<LampIssueResolutionOption?>), findsNWidgets(2));

        await tearDownDialog(tester);
      },
    );
  });

  testWidgets(
    'πριν επιλεγεί ενέργεια με τιμή δεν εμφανίζεται πεδίο κειμένου',
    (tester) async {
      await pumpManualReviewDialog(tester);

      expect(find.byType(TextField), findsNothing);

      await tearDownDialog(tester);
    },
  );

  testWidgets(
    'το πεδίο «Νέα τιμή» εστιάζεται αυτόματα μόλις εμφανιστεί',
    (tester) async {
      await pumpManualReviewDialog(tester);

      await tester.tap(find.text('Δώσε νέα τιμή στο code 5001'));
      await tester.pump();

      expect(find.byType(TextField), findsOneWidget);
      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byType(TextField),
          matching: find.byType(EditableText),
        ),
      );
      expect(
        editable.widget.focusNode.hasPrimaryFocus,
        isTrue,
        reason: 'Μόλις εμφανιστεί το πεδίο νέας τιμής, ο χρήστης πρέπει να '
            'μπορεί να πληκτρολογήσει χωρίς κλικ.',
      );

      await tearDownDialog(tester);
    },
  );

  testWidgets(
    'scientificSerial: με checker true εμφανίζεται προειδοποίηση διπλότυπου',
    (tester) async {
      await pumpScientificSerialDialog(
        tester,
        serialExistsChecker: (_, _) async => true,
      );

      await tester.tap(find.text('Καταχώρηση νέου σειριακού'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '492800000001');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(scientificSerialDuplicateWarning), findsOneWidget);

      await tearDownDialog(tester);
    },
  );

  testWidgets(
    'scientificSerial: με checker false ΔΕΝ εμφανίζεται προειδοποίηση διπλότυπου',
    (tester) async {
      await pumpScientificSerialDialog(
        tester,
        serialExistsChecker: (_, _) async => false,
      );

      await tester.tap(find.text('Καταχώρηση νέου σειριακού'));
      await tester.pump();
      await tester.enterText(find.byType(TextField), '492800000001');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text(scientificSerialDuplicateWarning), findsNothing);

      await tearDownDialog(tester);
    },
  );
}
