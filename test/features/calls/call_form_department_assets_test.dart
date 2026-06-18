// Widget test: φόρμα κλήσης — εμφάνιση εξοπλισμού και τηλεφώνων μετά την επιλογή τμήματος.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/calls/call_form_department_assets_test.dart
// Σενάριο Φάντασμα (κοινόχρηστα):
//   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "επιλογή τμήματος"
// Σενάριο ροής χρήστη (τμήμα → εξοπλισμός → τηλέφωνο):
//   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "select_department"

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_department_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_equipment_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_phone_suggestion_list.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../test_reporter.dart';
import '../../test_setup.dart';

const _kFantasmaDepartmentName = 'Φάντασμα';
const _kMariaFirstName = 'Μαρία';
const _kMariaLastName = 'Άσχημη';
const _kSharedPhone = '333';
const _kUserOnlyPhone = '444';
const _kSharedEquipmentCodes = ['2001', '2002', '2003'];
const _kUserEquipmentCode = 'PC-MARIA';

Finder _callLoggerDepartmentTextField() {
  return find.descendant(
    of: find.byType(SmartEntityDepartmentField),
    matching: find.byType(TextField),
  );
}

Finder _callLoggerEquipmentTextField() {
  return find.descendant(
    of: find.byType(SmartEntityEquipmentField),
    matching: find.byType(TextField),
  );
}

/// Περιμένει εμφάνιση [finder] στο δέντρο widget χωρίς σκληρές καθυστερήσεις.
Future<void> _pumpUntilFinderVisible(
  WidgetTester tester,
  Finder finder, {
  int maxAttempts = 45,
  required String failDescription,
}) async {
  for (var attempt = 0; attempt < maxAttempts; attempt++) {
    if (finder.evaluate().isNotEmpty) {
      return;
    }
    await pumpUntilSettled(
      tester,
      steps: 2,
      step: const Duration(milliseconds: 30),
    );
  }
  fail(greekExpectMsg(failDescription));
}

Finder _equipmentCodeInListFinder(String code) {
  return find.byWidgetPredicate(
    (w) =>
        w is ListTile &&
        w.title is Text &&
        ((w.title as Text).data?.contains(code) ?? false),
  );
}

/// Τμήμα «Φάντασμα»: κοινόχρηστο 333, ιδιωτικό 444, κοινόχρηστος εξοπλισμός 2001–2003,
/// ιδιωτικός εξοπλισμός PC-MARIA για τη Μαρία Άσχημη.
Future<int> _seedFantasmaDepartmentAssetsScenario() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('user_equipment');
  await db.delete('user_phones');
  await db.delete('department_phones');
  await db.delete('phones');
  await db.delete('equipment');
  await db.delete('users');
  await db.delete('departments');

  final deptId = await db.insert('departments', {
    'name': _kFantasmaDepartmentName,
    'name_key': SearchTextNormalizer.normalizeForSearch(
      _kFantasmaDepartmentName,
    ),
    'color': '#33691F',
    'is_deleted': 0,
  });

  final userId = await db.insert('users', {
    'first_name': _kMariaFirstName,
    'last_name': _kMariaLastName,
    'department_id': deptId,
    'is_deleted': 0,
  });

  final sharedPhoneId = await db.insert('phones', {'number': _kSharedPhone});
  await db.insert('user_phones', {
    'user_id': userId,
    'phone_id': sharedPhoneId,
  });
  await db.insert('department_phones', {
    'department_id': deptId,
    'phone_id': sharedPhoneId,
  });

  final userOnlyPhoneId = await db.insert('phones', {'number': _kUserOnlyPhone});
  await db.insert('user_phones', {
    'user_id': userId,
    'phone_id': userOnlyPhoneId,
  });

  for (final code in _kSharedEquipmentCodes) {
    await db.insert('equipment', {
      'code_equipment': code,
      'department_id': deptId,
      'is_deleted': 0,
    });
  }

  final userEquipmentId = await db.insert('equipment', {
    'code_equipment': _kUserEquipmentCode,
    'type': 'Desktop',
    'is_deleted': 0,
  });
  await db.insert('user_equipment', {
    'user_id': userId,
    'equipment_id': userEquipmentId,
  });

  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
  return deptId;
}

Future<void> _loadCallFormApp(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: callLoggerTestProviderOverrides(),
        child: const MyApp(),
      ),
    );
    await tester.pump();
    await pumpUntilSettledLong(tester);
    await GoogleFonts.pendingFonts();
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    await container.read(lookupServiceProvider.future);
  });
  await pumpUntilSettled(tester);
}

Future<void> _selectDepartmentFromAutocomplete(
  WidgetTester tester,
  String departmentName,
) async {
  final deptField = _callLoggerDepartmentTextField();
  await tester.tap(deptField);
  await pumpUntilSettled(tester);
  await tester.enterText(deptField, departmentName.substring(0, 3));
  await pumpUntilSettled(tester);

  final option = find.descendant(
    of: find.byType(Material),
    matching: find.widgetWithText(ListTile, departmentName),
  );
  expect(
    option,
    findsWidgets,
    reason: greekExpectMsg(
      'Η αναζήτηση τμήματος πρέπει να εμφανίζει «$departmentName» στη λίστα',
    ),
  );
  await tester.tap(option.first);
  await pumpUntilSettled(tester);
}

Future<CallHeaderState> _readCallHeaderState(WidgetTester tester) async {
  CallHeaderState? state;
  await tester.runAsync(() async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    state = container.read(callHeaderProvider);
  });
  await tester.pump();
  return state!;
}

void _configureDesktopViewport(WidgetTester tester) {
  tester.view.physicalSize = const Size(1600, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(() {
    tester.view.resetPhysicalSize();
    tester.view.resetDevicePixelRatio();
  });
}

Future<void> _selectEquipmentFromList(
  WidgetTester tester,
  String equipmentCode,
) async {
  final tile = _equipmentCodeInListFinder(equipmentCode);
  await _pumpUntilFinderVisible(
    tester,
    tile,
    failDescription:
        'Ο εξοπλισμός $equipmentCode δεν εμφανίστηκε εγκαίρως στη λίστα UI',
  );
  await tester.tap(tile.first);
  await pumpUntilSettled(tester);
}

Future<void> _finishCallFormWidgetTest(WidgetTester tester) async {
  final notesFinder = find.byWidgetPredicate(
    (w) =>
        w is TextField &&
        (w.decoration?.hintText?.contains('Σημειώσεις') ?? false),
  );
  await tester.tap(notesFinder);
  await pumpUntilSettled(tester);
  await tester.pump(const Duration(seconds: 11));
  while (tester.takeException() != null) {}
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Φόρμα κλήσης — σενάριο Φάντασμα (widget)', () {
    late int deptId;

    setUp(() async {
      deptId = await _seedFantasmaDepartmentAssetsScenario();
    });

    // Σενάριο: επιλογή τμήματος → λίστα εξοπλισμού → tap τηλεφώνου → λίστα αριθμών.
    //   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "επιλογή τμήματος"
    testWidgets(
      'επιλογή τμήματος: εμφανίζονται εξοπλισμός και τηλέφωνα στη φόρμα κλήσης',
      (tester) async {
        _configureDesktopViewport(tester);

        final reporter = GreekTestReportCollector();

        // —— Setup: φόρτωση εφαρμογής ——
        reporter.logProgress('Φόρτωση οθόνης «Νέα Κλήση» με απομονωμένη βάση');
        await _loadCallFormApp(tester);
        expect(
          find.byType(NavigationRail),
          findsOneWidget,
          reason: greekExpectMsg('Κύριο κέλυφος — οθόνη Κλήσεων'),
        );
        reporter.logStepDone('Εφαρμογή φορτώθηκε');

        // —— Αλληλεπίδραση: επιλογή τμήματος ——
        reporter.logProgress('Επιλογή τμήματος «$_kFantasmaDepartmentName»');
        await _selectDepartmentFromAutocomplete(
          tester,
          _kFantasmaDepartmentName,
        );

        final headerAfterDept = await _readCallHeaderState(tester);
        expect(
          headerAfterDept.departmentText,
          _kFantasmaDepartmentName,
          reason: greekExpectMsg('Το πεδίο τμήματος συμπληρώνεται μετά την επιλογή'),
        );
        expect(
          headerAfterDept.selectedDepartmentId,
          deptId,
          reason: greekExpectMsg('Το id τμήματος συγχρονίζεται στο state'),
        );
        reporter.logStepDone('Τμήμα επιλέχθηκε — state ενημερώθηκε');

        // —— Έλεγχος: λίστα εξοπλισμού ——
        reporter.logProgress(
          'Έλεγχος λίστας εξοπλισμού (κοινόχρηστος + ιδιωτικός)',
        );

        final expectedEquipmentCodes = [
          ..._kSharedEquipmentCodes,
          _kUserEquipmentCode,
        ];
        expect(
          headerAfterDept.equipmentCandidates
              .map((EquipmentModel e) => e.code?.trim())
              .whereType<String>()
              .toSet(),
          expectedEquipmentCodes.toSet(),
          reason: greekExpectMsg(
            'Οι υποψήφιοι εξοπλισμοί στο state περιλαμβάνουν κοινόχρηστο και ιδιωτικό',
          ),
        );

        // Μετά την επιλογή τμήματος η εστίαση πηγαίνει στο πεδίο εξοπλισμού·
        // επιβεβαιώνουμε ότι το overlay εμφανίζει τους κωδικούς.
        await tester.tap(_callLoggerEquipmentTextField());
        await pumpUntilSettled(tester);

        for (final code in expectedEquipmentCodes) {
          final codeFinder = _equipmentCodeInListFinder(code);
          await _pumpUntilFinderVisible(
            tester,
            codeFinder,
            failDescription:
                'Ο κωδικός εξοπλισμού $code δεν εμφανίστηκε εγκαίρως στη λίστα UI',
          );
          expect(
            codeFinder,
            findsWidgets,
            reason: greekExpectMsg(
              'Ο κωδικός εξοπλισμού $code εμφανίζεται στη λίστα UI',
            ),
          );
        }
        reporter.logStepDone(
          'Λίστα εξοπλισμού: ${expectedEquipmentCodes.join(', ')}',
        );

        // —— Αλληλεπίδραση + έλεγχος: λίστα τηλεφώνων ——
        reporter.logProgress('Tap στο πεδίο τηλεφώνου — λίστα αριθμών τμήματος');

        final expectedPhones = [_kSharedPhone, _kUserOnlyPhone];
        expect(
          headerAfterDept.phoneCandidates.toSet(),
          expectedPhones.toSet(),
          reason: greekExpectMsg(
            'Οι υποψήφιοι αριθμοί στο state περιλαμβάνουν κοινόχρηστο και ιδιωτικό',
          ),
        );

        await tester.tap(callLoggerPhoneTextField());
        await pumpUntilSettled(tester);

        for (final phone in expectedPhones) {
          final phoneFinder = find.widgetWithText(ListTile, phone);
          await _pumpUntilFinderVisible(
            tester,
            phoneFinder,
            failDescription:
                'Ο αριθμός $phone δεν εμφανίστηκε εγκαίρως στη λίστα τηλεφώνων',
          );
          expect(
            phoneFinder,
            findsWidgets,
            reason: greekExpectMsg(
              'Ο αριθμός $phone εμφανίζεται στη λίστα τηλεφώνων',
            ),
          );
        }

        // Επιλογή κοινόχρηστου τηλεφώνου από τη λίστα — δεν πρέπει να αποτυγχάνει σιωπηλά.
        final sharedPhoneTile = find.descendant(
          of: find.byType(Material),
          matching: find.widgetWithText(ListTile, _kSharedPhone),
        );
        expect(
          sharedPhoneTile,
          findsWidgets,
          reason: greekExpectMsg(
            'Κλικ σε κοινόχρηστο τηλέφωνο — διαθέσιμο ListTile',
          ),
        );
        await tester.tap(sharedPhoneTile.first);
        await pumpUntilSettled(tester);

        final headerAfterPhone = await _readCallHeaderState(tester);
        expect(
          headerAfterPhone.selectedPhone,
          _kSharedPhone,
          reason: greekExpectMsg(
            'Μετά την επιλογή από τη λίστα ορισμός selectedPhone',
          ),
        );
        expect(
          headerAfterPhone.phoneCandidates,
          isEmpty,
          reason: greekExpectMsg(
            'Μετά την επιλογή αδειάζει η λίστα υποψηφίων τηλεφώνων',
          ),
        );

        reporter.logStepDone(
          'Λίστα τηλεφώνων: ${expectedPhones.join(', ')} — επιλογή $_kSharedPhone OK',
        );

        await _finishCallFormWidgetTest(tester);

        reporter.recordPass(
          'Επιλογή τμήματος — εξοπλισμός και τηλέφωνα εμφανίζονται σωστά στη φόρμα',
        );
      },
      semanticsEnabled: false,
    );
  });

  group('Φόρμα κλήσης — select_department (widget)', () {
    late int deptId;

    setUp(() async {
      await seedIsolatedTestDatabase();
      final db = await DatabaseHelper.instance.database;
      final rows = await db.query(
        'departments',
        columns: ['id'],
        where: 'name = ?',
        whereArgs: [kTestDepartmentName],
      );
      deptId = rows.first['id'] as int;
    });

    // Ροή χρήστη: Νέα κλήση → τμήμα → εξοπλισμός (λίστα + επιλογή) → τηλέφωνο (λίστα).
    //   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "select_department"
    testWidgets(
      'select_department: τμήμα → εξοπλισμός (επιλογή) → τηλέφωνο (λίστα)',
      (tester) async {
        _configureDesktopViewport(tester);

        final reporter = GreekTestReportCollector();

        // —— Setup ——
        reporter.logProgress('Οθόνη «Νέα Κλήση» — βάση δοκιμών (Τμήμα Δοκιμών)');
        await _loadCallFormApp(tester);
        expect(
          find.byType(NavigationRail),
          findsOneWidget,
          reason: greekExpectMsg('Οθόνη Νέα Κλήση'),
        );
        reporter.logStepDone('Εφαρμογή φορτώθηκε');

        // —— Βήμα 1: επιλογή τμήματος ——
        reporter.logProgress('Επιλογή τμήματος «$kTestDepartmentName»');
        await _selectDepartmentFromAutocomplete(tester, kTestDepartmentName);

        final headerAfterDept = await _readCallHeaderState(tester);
        expect(
          headerAfterDept.departmentText,
          kTestDepartmentName,
          reason: greekExpectMsg('Συμπλήρωση πεδίου τμήματος'),
        );
        expect(
          headerAfterDept.selectedDepartmentId,
          deptId,
          reason: greekExpectMsg('Επιλεγμένο id τμήματος'),
        );
        expect(
          headerAfterDept.equipmentCandidates
              .map((EquipmentModel e) => e.code?.trim())
              .whereType<String>()
              .toSet(),
          {kTestEquipmentCode},
          reason: greekExpectMsg('Υποψήφιος εξοπλισμός τμήματος στο state'),
        );
        expect(
          headerAfterDept.phoneCandidates.toSet(),
          {kTestPhoneDigits},
          reason: greekExpectMsg('Υποψήφιοι αριθμοί τμήματος στο state'),
        );
        reporter.logStepDone('Τμήμα «$kTestDepartmentName» επιλέχθηκε');

        // —— Βήμα 2: κλικ εξοπλισμός → λίστα ——
        reporter.logProgress('Κλικ στο πεδίο εξοπλισμού — εμφάνιση λίστας');
        await tester.tap(_callLoggerEquipmentTextField());
        await pumpUntilSettled(tester);

        final equipmentTile = _equipmentCodeInListFinder(kTestEquipmentCode);
        await _pumpUntilFinderVisible(
          tester,
          equipmentTile,
          failDescription:
              'Ο εξοπλισμός $kTestEquipmentCode δεν εμφανίστηκε στη λίστα',
        );
        expect(
          equipmentTile,
          findsWidgets,
          reason: greekExpectMsg('Λίστα εξοπλισμού με $kTestEquipmentCode'),
        );
        reporter.logStepDone('Λίστα εξοπλισμού εμφανίστηκε');

        // —— Βήμα 3: επιλογή εξοπλισμού από τη λίστα ——
        reporter.logProgress('Επιλογή εξοπλισμού «$kTestEquipmentCode»');
        await _selectEquipmentFromList(tester, kTestEquipmentCode);

        final headerAfterEquipment = await _readCallHeaderState(tester);
        expect(
          headerAfterEquipment.selectedEquipment?.code,
          kTestEquipmentCode,
          reason: greekExpectMsg('Επιλεγμένος εξοπλισμός μετά το tap στη λίστα'),
        );
        expect(
          headerAfterEquipment.phoneCandidates,
          isNotEmpty,
          reason: greekExpectMsg(
            'Μετά εξοπλισμό, οι υποψήφιοι τηλεφώνων του τμήματος δεν πρέπει να '
            'καθαρίζονται',
          ),
        );
        reporter.logStepDone('Εξοπλισμός $kTestEquipmentCode επιλέχθηκε');

        // —— Βήμα 4: κλικ τηλέφωνο (μετά την επιλογή εξοπλισμού) ——
        reporter.logProgress('Κλικ στο πεδίο τηλεφώνου — overlay λίστας τμήματος');
        await tester.tap(callLoggerPhoneTextField());
        await pumpUntilSettled(tester);

        final departmentPhoneOverlay = find.byType(SmartEntityPhoneSuggestionList);
        await _pumpUntilFinderVisible(
          tester,
          departmentPhoneOverlay,
          failDescription:
              'Η overlay λίστα τηλεφώνων τμήματος (SmartEntityPhoneSuggestionList) '
              'δεν εμφανίστηκε μετά επιλογή εξοπλισμού',
        );
        expect(
          departmentPhoneOverlay,
          findsOneWidget,
          reason: greekExpectMsg(
            'Overlay λίστας τηλεφώνων τμήματος — όχι autocomplete prefix',
          ),
        );
        expect(
          find.descendant(
            of: departmentPhoneOverlay,
            matching: find.text(kTestPhoneDigits),
          ),
          findsOneWidget,
          reason: greekExpectMsg(
            'Στην overlay λίστα τμήματος εμφανίζεται ο $kTestPhoneDigits',
          ),
        );
        reporter.logStepDone('Overlay λίστα τηλεφώνων: $kTestPhoneDigits');

        await _finishCallFormWidgetTest(tester);

        reporter.recordPass(
          'select_department: τμήμα → εξοπλισμός → τηλέφωνο',
        );
      },
      semanticsEnabled: false,
    );
  });
}
