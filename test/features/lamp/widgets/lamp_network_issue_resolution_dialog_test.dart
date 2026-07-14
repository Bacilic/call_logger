import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_models.dart';
import 'package:call_logger/core/database/old_database/lamp_network_issue_resolution_service.dart';
import 'package:call_logger/features/lamp/widgets/lamp_entity_code_autocomplete.dart';
import 'package:call_logger/features/lamp/widgets/lamp_network_issue_resolution_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _parsedNetworkIssue = ParsedNetworkIssueRow(
  node: 'NODE-A',
  ip: '10.10.212.23',
  equipmentCode: '5001',
  description: 'Test description',
  mac: 'AA:BB:CC:DD:EE:FF',
  vlan: '100',
  hostname: 'PC-TEST',
  workgroup: 'WORKGROUP',
  internet: 'yes',
  comments: 'Some comment',
);

const _stubEquipmentSuggestions = <LampEntityCodeSuggestion>[
  LampEntityCodeSuggestion(code: 5001, label: 'Εκτυπωτής'),
  LampEntityCodeSuggestion(code: 6002, label: 'Laptop Dell · SN999'),
];

Future<List<LampEntityCodeSuggestion>> _stubSearchEquipment(String query) async {
  return filterEntityCodeSuggestions(_stubEquipmentSuggestions, query);
}

Future<String?> _stubEquipmentPreview(int code) async {
  if (code == 5001) return 'Εκτυπωτής · SN123 · Λογιστήριο';
  return null;
}

class _FakeNetworkIssueResolutionService
    extends LampNetworkIssueResolutionService {
  _FakeNetworkIssueResolutionService()
      : super(databaseProvider: LampDatabaseProvider.instance);

  bool deleteIssueCalled = false;

  @override
  ParsedNetworkIssueRow? parseNetworkIssueRawValue(String rawValue) {
    return _parsedNetworkIssue;
  }

  @override
  Future<bool> deleteIssue({
    required String databasePath,
    required int issueId,
  }) async {
    deleteIssueCalled = true;
    return true;
  }
}

class _FakeScanNetworkIssueResolutionService
    extends LampNetworkIssueResolutionService {
  _FakeScanNetworkIssueResolutionService()
      : super(databaseProvider: LampDatabaseProvider.instance);

  String? lastFixColumn;
  String? lastFixNewValue;
  int? lastFixEquipmentCode;
  bool returnInvalidIpError = false;
  int? lastAcceptIssueId;
  String? lastAcceptReason;

  @override
  ParsedNetworkIssueRow? parseNetworkIssueRawValue(String rawValue) => null;

  @override
  Future<bool> acceptIssue({
    required String databasePath,
    required int issueId,
    required String reason,
  }) async {
    lastAcceptIssueId = issueId;
    lastAcceptReason = reason;
    return true;
  }

  @override
  Future<NetworkIssueMatchResult> fixEquipmentNetworkField({
    required String databasePath,
    required int issueId,
    required int equipmentCode,
    required String column,
    required String newValue,
  }) async {
    lastFixColumn = column;
    lastFixNewValue = newValue;
    lastFixEquipmentCode = equipmentCode;
    if (returnInvalidIpError) {
      return const NetworkIssueMatchResult.error('Μη έγκυρη μορφή IPv4.');
    }
    return const NetworkIssueMatchResult.success();
  }
}

class _DialogTestSession {
  _DialogTestSession(this.service);

  final LampNetworkIssueResolutionService service;
  LampNetworkIssueDialogOutcome? outcome;
}

typedef _DialogPumpResult = _DialogTestSession;

void main() {
  String? clipboardText;

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          final args = call.arguments as Map<Object?, Object?>;
          clipboardText = args['text'] as String?;
          return null;
        case 'Clipboard.getData':
          if (clipboardText == null) return null;
          return <String, Object?>{'text': clipboardText};
      }
      return null;
    });
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  setUp(() {
    clipboardText = null;
  });

  Future<_DialogPumpResult> pumpDialog(
    WidgetTester tester, {
    Future<List<LampEntityCodeSuggestion>> Function(String query)?
        searchEquipmentSuggestions,
    Future<String?> Function(int code)? equipmentPreview,
    LampNetworkIssueResolutionService? service,
    String issueType = 'network_unmatched',
    List<Map<String, Object?>>? issues,
  }) async {
    await tester.binding.setSurfaceSize(const Size(1280, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final session = _DialogTestSession(
      service ?? _FakeNetworkIssueResolutionService(),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              return ElevatedButton(
                onPressed: () {
                  showDialog<LampNetworkIssueDialogOutcome>(
                    context: context,
                    builder: (_) => LampNetworkIssueResolutionDialog(
                      issueType: issueType,
                      issues: issues ??
                          const [
                            <String, Object?>{
                              'id': 1,
                              'raw_value': 'ignored-by-fake',
                            },
                          ],
                      service: session.service,
                      databasePath: '/fake/path',
                      searchEquipmentSuggestions: searchEquipmentSuggestions ??
                          _stubSearchEquipment,
                      equipmentPreview:
                          equipmentPreview ?? _stubEquipmentPreview,
                    ),
                  ).then((value) => session.outcome = value);
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
    return session;
  }

  Future<_DialogPumpResult> pumpScanDialog(
    WidgetTester tester, {
    _FakeScanNetworkIssueResolutionService? service,
    bool returnInvalidIpError = false,
  }) async {
    final scanService = service ?? _FakeScanNetworkIssueResolutionService();
    scanService.returnInvalidIpError = returnInvalidIpError;
    return pumpDialog(
      tester,
      service: scanService,
      issueType: 'network_invalid_ip',
      issues: const [
        <String, Object?>{
          'id': 42,
          'row_number': 2356,
          'column_name': 'ip_address',
          'raw_value': '10.1.1',
          'message': 'Μη έγκυρη μορφή IPv4: «10.1.1».',
        },
      ],
    );
  }

  Future<void> closeDialog(WidgetTester tester) async {
    await tester.tap(find.text('Ακύρωση όλων'));
    await tester.pumpAndSettle();
  }

  Future<_DialogPumpResult> pumpAndSkipLastIssue(WidgetTester tester) async {
    final session = await pumpDialog(tester);
    await tester.tap(find.text('Παράλειψη'));
    await tester.pumpAndSettle();
    return session;
  }

  testWidgets(
    'εμφανίζει SelectableText με hostname και κουμπιά αντιγραφής στις γραμμές',
    (tester) async {
      await pumpDialog(tester);

      expect(
        find.widgetWithText(SelectableText, 'Hostname: PC-TEST'),
        findsOneWidget,
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.copy_outlined),
        findsWidgets,
      );
      expect(
        find.widgetWithIcon(IconButton, Icons.copy_outlined).evaluate().length,
        greaterThanOrEqualTo(1),
      );

      await closeDialog(tester);
    },
  );

  testWidgets(
    'αντιγραφή μιας γραμμής βάζει μόνο την τιμή στο clipboard και δείχνει snackbar',
    (tester) async {
      await pumpDialog(tester);

      final hostnameRow = find.ancestor(
        of: find.widgetWithText(SelectableText, 'Hostname: PC-TEST'),
        matching: find.byType(Row),
      );
      expect(hostnameRow, findsOneWidget);

      final copyButton = find.descendant(
        of: hostnameRow,
        matching: find.widgetWithIcon(IconButton, Icons.copy_outlined),
      );
      await tester.ensureVisible(copyButton);
      await tester.tap(copyButton);
      await tester.pump();

      expect(clipboardText, 'PC-TEST');
      expect(find.text('Αντιγράφηκε: PC-TEST'), findsOneWidget);

      await closeDialog(tester);
    },
  );

  testWidgets(
    '«Αντιγραφή όλων» βάζει κείμενο που περιέχει IP και hostname',
    (tester) async {
      await pumpDialog(tester);

      final copyAll = find.text('Αντιγραφή όλων');
      await tester.ensureVisible(copyAll);
      await tester.tap(copyAll);
      await tester.pump();

      expect(clipboardText, isNotNull);
      expect(clipboardText, contains('10.10.212.23'));
      expect(clipboardText, contains('PC-TEST'));
      expect(clipboardText, contains('IP: 10.10.212.23'));
      expect(clipboardText, contains('Hostname: PC-TEST'));
      expect(find.textContaining('Αντιγράφηκε:'), findsOneWidget);

      await closeDialog(tester);
    },
  );

  testWidgets(
    'το πεδίο εξοπλισμού χρησιμοποιεί LampEntityCodeAutocomplete',
    (tester) async {
      await pumpDialog(tester);

      expect(find.byType(LampEntityCodeAutocomplete), findsOneWidget);
      expect(find.text('Κωδικός ή όνομα εξοπλισμού'), findsOneWidget);

      await closeDialog(tester);
    },
  );

  testWidgets(
    'το πεδίο εξοπλισμού εστιάζεται αυτόματα μόλις ανοίξει ο διάλογος',
    (tester) async {
      await pumpDialog(tester);

      final editable = tester.state<EditableTextState>(
        find.descendant(
          of: find.byType(LampEntityCodeAutocomplete),
          matching: find.byType(EditableText),
        ),
      );
      expect(
        editable.widget.focusNode.hasPrimaryFocus,
        isTrue,
        reason: 'Με το άνοιγμα του οδηγού, ο χρήστης πρέπει να μπορεί να '
            'πληκτρολογήσει χωρίς κλικ μέσα στο πεδίο.',
      );

      await closeDialog(tester);
    },
  );

  testWidgets(
    'επιλογή πρότασης εμφανίζει γραμμή «Θα συνδεθεί με:»',
    (tester) async {
      await pumpDialog(tester);

      final field = find.descendant(
        of: find.byType(LampEntityCodeAutocomplete),
        matching: find.byType(TextField),
      );
      await tester.ensureVisible(field);
      await tester.tap(field);
      await tester.pump();
      await tester.enterText(field, 'Εκτυπ');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 150));

      await tester.tap(find.textContaining('Εκτυπωτής (5001)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.textContaining('Θα συνδεθεί με:'), findsOneWidget);
      expect(
        find.textContaining('Εκτυπωτής · SN123 · Λογιστήριο'),
        findsOneWidget,
      );

      await closeDialog(tester);
    },
  );

  testWidgets(
    'πάτημα «Διαγραφή από την ουρά» εμφανίζει διάλογο επιβεβαίωσης',
    (tester) async {
      await pumpDialog(tester);

      await tester.tap(find.text('Διαγραφή από την ουρά'));
      await tester.pumpAndSettle();

      expect(find.text('Οριστική διαγραφή;'), findsOneWidget);

      await tester.tap(find.text('Άκυρο'));
      await tester.pumpAndSettle();
      await closeDialog(tester);
    },
  );

  testWidgets(
    '«Άκυρο» στον διάλογο επιβεβαίωσης δεν καλεί deleteIssue',
    (tester) async {
      final session = await pumpDialog(tester);

      await tester.tap(find.text('Διαγραφή από την ουρά'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Άκυρο'));
      await tester.pumpAndSettle();

      expect(
        (session.service as _FakeNetworkIssueResolutionService)
            .deleteIssueCalled,
        isFalse,
      );
      expect(find.text('Διαγραφή από την ουρά'), findsOneWidget);
      expect(find.text('Οριστική διαγραφή;'), findsNothing);

      await closeDialog(tester);
    },
  );

  testWidgets(
    '«Διαγραφή» στον διάλογο επιβεβαίωσης καλεί deleteIssue',
    (tester) async {
      final session = await pumpDialog(tester);

      await tester.tap(find.text('Διαγραφή από την ουρά'));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Διαγραφή'));
      await tester.pumpAndSettle();

      expect(
        (session.service as _FakeNetworkIssueResolutionService)
            .deleteIssueCalled,
        isTrue,
      );
      expect(session.outcome, LampNetworkIssueDialogOutcome.completed);
    },
  );

  testWidgets(
    '«Παράλειψη» σε μία εγγραφή κλείνει με nothingChanged',
    (tester) async {
      final session = await pumpAndSkipLastIssue(tester);

      expect(session.outcome, LampNetworkIssueDialogOutcome.nothingChanged);
    },
  );

  testWidgets(
    'εμφανίζει τον κωδικό εξοπλισμού από το Excel',
    (tester) async {
      await pumpDialog(tester);

      expect(
        find.widgetWithText(
          SelectableText,
          'Κωδικός εξοπλισμού (Excel): 5001',
        ),
        findsOneWidget,
      );

      await closeDialog(tester);
    },
  );

  testWidgets(
    'δεν εμφανίζει πληροφορία internet από το parsed raw_value',
    (tester) async {
      await pumpDialog(tester);

      expect(find.textContaining('yes'), findsNothing);
      expect(find.textContaining('internet'), findsNothing);
      expect(find.textContaining('WORKGROUP'), findsNothing);

      await closeDialog(tester);
    },
  );

  testWidgets(
    '«Αντιγραφή όλων» περιλαμβάνει τον κωδικό εξοπλισμού Excel',
    (tester) async {
      await pumpDialog(tester);

      final copyAll = find.text('Αντιγραφή όλων');
      await tester.ensureVisible(copyAll);
      await tester.tap(copyAll);
      await tester.pump();

      expect(clipboardText, contains('Κωδικός εξοπλισμού (Excel): 5001'));

      await closeDialog(tester);
    },
  );

  testWidgets(
    'scan mode: εμφανίζει κωδικό εξοπλισμού, μήνυμα και πεδίο «Διόρθωση IP»',
    (tester) async {
      await pumpScanDialog(tester);

      expect(
        find.widgetWithText(SelectableText, 'Κωδικός εξοπλισμού: 2356'),
        findsOneWidget,
      );
      expect(
        find.widgetWithText(
          SelectableText,
          'Μη έγκυρη μορφή IPv4: «10.1.1».',
        ),
        findsOneWidget,
      );
      expect(find.text('Διόρθωση IP'), findsOneWidget);
      expect(find.textContaining('raw_value:'), findsNothing);

      final field = tester.widget<TextField>(find.byType(TextField));
      expect(field.controller?.text, '10.1.1');

      await closeDialog(tester);
    },
  );

  testWidgets(
    'scan mode: «Αποθήκευση διόρθωσης» καλεί fixEquipmentNetworkField και ολοκληρώνει',
    (tester) async {
      final scanService = _FakeScanNetworkIssueResolutionService();
      final session = await pumpScanDialog(tester, service: scanService);

      final field = find.byType(TextField);
      await tester.enterText(field, '10.1.1.50');
      await tester.pump();

      await tester.tap(find.text('Αποθήκευση διόρθωσης'));
      await tester.pumpAndSettle();

      expect(scanService.lastFixColumn, 'ip_address');
      expect(scanService.lastFixNewValue, '10.1.1.50');
      expect(scanService.lastFixEquipmentCode, 2356);
      expect(session.outcome, LampNetworkIssueDialogOutcome.completed);
    },
  );

  testWidgets(
    'scan mode: σφάλμα διόρθωσης εμφανίζει μήνυμα και δεν προχωρά',
    (tester) async {
      final scanService = _FakeScanNetworkIssueResolutionService();
      await pumpScanDialog(
        tester,
        service: scanService,
        returnInvalidIpError: true,
      );

      await tester.tap(find.text('Αποθήκευση διόρθωσης'));
      await tester.pumpAndSettle();

      expect(find.text('Μη έγκυρη μορφή IPv4.'), findsOneWidget);
      expect(find.text('Αποθήκευση διόρθωσης'), findsOneWidget);

      await closeDialog(tester);
    },
  );

  testWidgets(
    'scan mode: υπάρχει κουμπί «Αποδοχή ως έχει» που ανοίγει διάλογο αιτιολογίας',
    (tester) async {
      await pumpScanDialog(tester);

      expect(find.text('Αποδοχή ως έχει'), findsOneWidget);

      await tester.tap(find.text('Αποδοχή ως έχει'));
      await tester.pumpAndSettle();

      expect(find.text('Αιτιολογία'), findsOneWidget);

      await tester.tap(find.text('Άκυρο'));
      await tester.pumpAndSettle();
      await closeDialog(tester);
    },
  );

  testWidgets(
    'scan mode: κενή αιτιολογία — το «Αποδοχή» είναι ανενεργό',
    (tester) async {
      final scanService = _FakeScanNetworkIssueResolutionService();
      await pumpScanDialog(tester, service: scanService);

      await tester.tap(find.text('Αποδοχή ως έχει'));
      await tester.pumpAndSettle();

      final acceptButton = find.widgetWithText(FilledButton, 'Αποδοχή');
      expect(tester.widget<FilledButton>(acceptButton).onPressed, isNull);
      expect(scanService.lastAcceptIssueId, isNull);

      await tester.tap(find.text('Άκυρο'));
      await tester.pumpAndSettle();
      await closeDialog(tester);
    },
  );

  testWidgets(
    'scan mode: «Αποδοχή» με αιτιολογία καλεί acceptIssue και ολοκληρώνει',
    (tester) async {
      final scanService = _FakeScanNetworkIssueResolutionService();
      final session = await pumpScanDialog(tester, service: scanService);

      await tester.tap(find.text('Αποδοχή ως έχει'));
      await tester.pumpAndSettle();

      final reasonField = find.byWidgetPredicate(
        (widget) =>
            widget is TextField &&
            widget.decoration?.labelText == 'Αιτιολογία',
      );
      await tester.enterText(reasonField, 'Σκόπιμη διπλή IP σε DHCP');
      await tester.pump();

      await tester.tap(find.widgetWithText(FilledButton, 'Αποδοχή'));
      await tester.pumpAndSettle();

      expect(scanService.lastAcceptIssueId, 42);
      expect(scanService.lastAcceptReason, 'Σκόπιμη διπλή IP σε DHCP');
      expect(session.outcome, LampNetworkIssueDialogOutcome.completed);
    },
  );

  testWidgets(
    'ροή αντιστοίχισης: εμφανίζει ActionChip «Πρόταση: 5001»',
    (tester) async {
      await pumpDialog(tester);

      expect(find.widgetWithText(ActionChip, 'Πρόταση: 5001'), findsOneWidget);
      expect(find.text('Προτεινόμενοι κωδικοί:'), findsOneWidget);

      await closeDialog(tester);
    },
  );

  testWidgets(
    'ροή αντιστοίχισης: πάτημα chip γεμίζει τον κωδικό και εμφανίζει προεπισκόπηση',
    (tester) async {
      await pumpDialog(tester);

      await tester.tap(find.widgetWithText(ActionChip, 'Πρόταση: 5001'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      final field = find.descendant(
        of: find.byType(LampEntityCodeAutocomplete),
        matching: find.byType(TextField),
      );
      expect(tester.widget<TextField>(field).controller?.text, '5001');
      expect(find.textContaining('Θα συνδεθεί με:'), findsOneWidget);

      await closeDialog(tester);
    },
  );

  testWidgets(
    'scan mode: δεν εμφανίζονται προτάσεις κωδικών',
    (tester) async {
      await pumpScanDialog(tester);

      expect(find.textContaining('Πρόταση:'), findsNothing);
      expect(find.text('Προτεινόμενοι κωδικοί:'), findsNothing);

      await closeDialog(tester);
    },
  );
}
