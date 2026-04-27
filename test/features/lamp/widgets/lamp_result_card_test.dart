import 'package:call_logger/features/lamp/widgets/lamp_result_card.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  String? clipboardText;

  setUpAll(() async {
    await initializeDateFormatting('el');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      switch (call.method) {
        case 'Clipboard.setData':
          final args = call.arguments as Map<Object?, Object?>;
          clipboardText = args['text'] as String?;
          return null;
        case 'Clipboard.getData':
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

  testWidgets('Lamp result card εμφανίζει τις 5 ενότητες με πλήρη δεδομένα', (
    tester,
  ) async {
    await _pumpCard(tester, width: 1300, row: _fullRow);

    expect(find.text('ΕΞΟΠΛΙΣΜΟΣ'), findsOneWidget);
    expect(find.text('ΜΟΝΤΕΛΟ'), findsOneWidget);
    expect(find.text('ΣΥΜΒΑΣΗ'), findsOneWidget);
    expect(find.text('ΙΔΙΟΚΤΗΤΗΣ'), findsOneWidget);
    expect(find.text('ΤΜΗΜΑ'), findsOneWidget);
    expect(find.text('SN123456789'), findsOneWidget);
    expect(find.text('LaserJet Pro MFP M428'), findsOneWidget);
  });

  testWidgets(
    'Lamp result card κρύβει «Συνδεδεμένο σε» όταν κωδικός = set_master',
    (tester) async {
      await _pumpCard(
        tester,
        width: 1300,
        row: const <String, Object?>{
          'code': 3663,
          'description': 'Δείγμα εξοπλισμού',
          'set_master': 3663,
        },
      );

      expect(find.text('Συνδεδεμένο σε'), findsNothing);
    },
  );

  testWidgets(
    'Lamp result card εμφανίζει «Συνδεδεμένο σε» όταν διαφέρει από τον κωδικό',
    (tester) async {
      await _pumpCard(
        tester,
        width: 1300,
        row: const <String, Object?>{
          'code': 3663,
          'description': 'Δείγμα',
          'set_master': 1000,
        },
      );

      expect(find.text('Συνδεδεμένο σε'), findsOneWidget);
      expect(find.text('1000'), findsOneWidget);
    },
  );

  testWidgets('Lamp result card κρύβει κενές ενότητες και γραμμές', (
    tester,
  ) async {
    await _pumpCard(tester, width: 1300, row: const <String, Object?>{
      'code': 1001,
    });

    expect(find.text('ΕΞΟΠΛΙΣΜΟΣ'), findsOneWidget);
    expect(find.text('ΜΟΝΤΕΛΟ'), findsNothing);
    expect(find.text('ΣΥΜΒΑΣΗ'), findsNothing);
    expect(find.text('ΙΔΙΟΚΤΗΤΗΣ'), findsNothing);
    expect(find.text('ΤΜΗΜΑ'), findsNothing);
    expect(find.text('-'), findsNothing);
  });

  testWidgets('Lamp result card δεν κάνει overflow σε μικρό πλάτος', (
    tester,
  ) async {
    await _pumpCard(
      tester,
      width: 700,
      row: {
        ..._fullRow,
        'description': List.filled(30, 'πολύ μεγάλη περιγραφή').join(' '),
        'equipment_attributes': List.filled(25, 'attribute').join(', '),
      },
    );

    expect(tester.takeException(), isNull);
    expect(find.text('ΕΞΟΠΛΙΣΜΟΣ'), findsOneWidget);
    expect(find.byType(Wrap), findsNothing);
  });

  testWidgets('Lamp result card χρησιμοποιεί grid διάταξη σε tablet πλάτος', (
    tester,
  ) async {
    await _pumpCard(tester, width: 1000, row: _fullRow);

    expect(tester.takeException(), isNull);
    expect(find.byType(Wrap), findsOneWidget);
  });

  testWidgets('CopyableField αντιγράφει value και δείχνει ακριβές SnackBar', (
    tester,
  ) async {
    await _pumpCard(tester, width: 1300, row: _fullRow);

    await tester.tap(
      find.byTooltip('Αντιγραφή Email').first,
    );
    await tester.pump();

    final clipboard = await Clipboard.getData(Clipboard.kTextPlain);
    expect(clipboard?.text, 'g.papadopoulos@org.gr');
    expect(
      find.text('Αντιγράφηκε Email: g.papadopoulos@org.gr'),
      findsOneWidget,
    );
  });

  testWidgets('Section edit ενεργοποιεί αποθήκευση μόνο μετά από αλλαγή', (
    tester,
  ) async {
    Map<String, Object?>? savedFields;
    await _pumpCard(
      tester,
      width: 1300,
      row: _fullRow,
      onSaveSection: ({required id, required sectionType, required updatedFields}) async {
        savedFields = updatedFields;
        return const EquipmentSectionSaveResult(success: true);
      },
    );

    await tester.tap(find.byTooltip('Επεξεργασία ΙΔΙΟΚΤΗΤΗΣ'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(FilledButton, 'Αποθήκευση'), findsOneWidget);
    final saveButton =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Αποθήκευση'));
    expect(saveButton.onPressed, isNull);

    await tester.enterText(find.widgetWithText(TextFormField, 'Email'), 'new@example.gr');
    await tester.pumpAndSettle();
    final enabledSave =
        tester.widget<FilledButton>(find.widgetWithText(FilledButton, 'Αποθήκευση'));
    expect(enabledSave.onPressed, isNotNull);

    await tester.tap(find.widgetWithText(FilledButton, 'Αποθήκευση'));
    await tester.pumpAndSettle();

    expect(savedFields, containsPair('owner_email', 'new@example.gr'));
    expect(find.text('new@example.gr'), findsOneWidget);
  });

  testWidgets('Lamp result card golden desktop baseline', (tester) async {
    await _pumpCard(tester, width: 1300, row: _fullRow);

    await expectLater(
      find.byType(EquipmentResultCard),
      matchesGoldenFile('goldens/lamp_result_card_full.png'),
    );
  });
}

Future<void> _pumpCard(
  WidgetTester tester, {
  required double width,
  required Map<String, Object?> row,
  SaveEquipmentSection? onSaveSection,
}) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(width, 520);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetPhysicalSize);

  await tester.pumpWidget(
    MaterialApp(
      locale: const Locale('el'),
      supportedLocales: const [Locale('el', 'GR'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.deepPurple),
      ),
      home: Scaffold(
        body: SingleChildScrollView(
          child: Center(
            child: SizedBox(
              width: width,
              child: EquipmentResultCard(
                viewModel: EquipmentViewModel.fromRow(row),
                onSaveSection: onSaveSection,
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

const _fullRow = <String, Object?>{
  'code': 1001,
  'description': 'Εκτυπωτής Laser A3',
  'serial_no': 'SN123456789',
  'asset_no': 'INV-2021-0001',
  'state_name': 'Ενεργός',
  'set_master': 1000,
  'receiving_date': '2021-03-15',
  'end_of_guarantee_date': '2024-03-15',
  'cost': '850',
  'equipment_comments': 'Δικτυακός εκτυπωτής γραφείου',
  'model_id': 42,
  'model_name': 'LaserJet Pro MFP M428',
  'category_name': 'Εκτυπωτές',
  'subcategory_name': 'Laser',
  'manufacturer_name': 'HP',
  'model_attributes': 'A3, 40ppm, Δικτυακός',
  'consumables': 'Toner HP 59A',
  'contract_id': 15,
  'contract_name': 'ΣΥΜ-2021-15',
  'contract_category_name': 'Εκτυπωτικός Εξοπλισμός',
  'supplier_name': 'Office Solutions A.E.',
  'contract_award': 'ΑΝΑΘ-2021-12',
  'contract_declaration': 'ΔΙΑΚ-2020-45',
  'maintenance_contract': 'Συντήρηση',
  'contract_comments': 'Ετήσια υποστήριξη',
  'owner_id': 7,
  'last_name': 'Παπαδόπουλος',
  'first_name': 'Γιώργος',
  'owner_email': 'g.papadopoulos@org.gr',
  'owner_phones': '210 1234567; 6900000000',
  'office_id': 3,
  'office_name': 'Τμήμα Πληροφορικής',
  'organization_name': 'Δ/νση Τεχνολογιών',
  'office_email': 'info@dept.gr',
  'office_phones': '210 9876543',
  'building': 'Κτίριο Α',
  'level': 2,
};
