// Widget test: φόρμα κλήσης — εμφάνιση εξοπλισμού και τηλεφώνων μετά την επιλογή τμήματος.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/calls/call_form_department_assets_test.dart
// Σενάριο Φάντασμα (κοινόχρηστα):
//   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "επιλογή τμήματος"
// Σενάριο ροής χρήστη (τμήμα → εξοπλισμός → τηλέφωνο):
//   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "select_department"
// Σενάρια Δοκιμαστικό (regression overlay μετά καθαρισμό πεδίων):
//   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "Δοκιμαστικό"
// Σενάριο καθαρισμού τμήματος (regression φιλτραρίσματος + κόκκινο Χ):
//   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "καθαρισμό τμήματος"
// Σενάριο ορφανού τηλεφώνου τμήματος (2580 → τμήμα + εξοπλισμός 3856):
//   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "ορφανό τηλέφωνο τμήματος"

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/provider/call_header_provider.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_caller_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_department_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_equipment_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_equipment_suggestion_list.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_phone_suggestion_list.dart';
import 'package:call_logger/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

const _kDokimastikoDepartmentName = 'Δοκιμαστικό';
const _kDokimastikoSharedPhones = ['2001', '2002', '2003'];
const _kDokimastikoSharedEquipmentCodes = ['1001', '1002', '1003'];
const _kDokimastikoScenarioEquipment = '1002';
const _kDokimastikoScenarioPhone = '2003';

/// Αναπαραγωγή παραγωγικού σενάριου: τηλέφωνο μόνο σε τμήμα (χωρίς χρήστη).
const _kOrphanDepartmentPhone = '2580';
const _kOrphanDepartmentName = 'ΤΕΙ Ορθοπεδικό';
const _kOrphanDepartmentEquipment = '3856';

Finder _callLoggerDepartmentTextField() {
  return find.descendant(
    of: find.byType(SmartEntityDepartmentField),
    matching: find.byType(TextField),
  );
}

Finder _callLoggerCallerTextField() {
  return find.descendant(
    of: find.byType(SmartEntityCallerField),
    matching: find.byType(TextField),
  );
}

Finder _clearAllFieldsButton() {
  return find.byTooltip('Καθαρισμός όλων των πεδίων');
}

Finder _departmentFieldClearButton() {
  return find.descendant(
    of: find.byType(SmartEntityDepartmentField),
    matching: find.byIcon(Icons.close),
  );
}

Future<void> _clearDepartmentField(WidgetTester tester) async {
  await tester.tap(_callLoggerDepartmentTextField());
  await pumpUntilSettled(tester);
  final clearButton = _departmentFieldClearButton();
  expect(
    clearButton,
    findsOneWidget,
    reason: greekExpectMsg('Κουμπί «χ» καθαρισμού πεδίου τμήματος'),
  );
  await tester.tap(clearButton);
  await pumpUntilSettled(tester);
}

Future<void> _expectClearAllButtonVisible(
  WidgetTester tester, {
  required bool visible,
  required String failContext,
}) async {
  final header = await _readCallHeaderState(tester);
  expect(
    header.hasAnyContent,
    visible,
    reason: greekExpectMsg(
      visible
          ? 'hasAnyContent=true — εμφανές κουμπί καθαρισμού όλων ($failContext)'
          : 'hasAnyContent=false — κρυφό κουμπί καθαρισμού όλων ($failContext)',
    ),
  );

  final clearAllButton = _clearAllFieldsButton();
  expect(
    clearAllButton,
    findsOneWidget,
    reason: greekExpectMsg('Υπάρχει το κουμπί «Καθαρισμός όλων των πεδίων»'),
  );
  final animatedOpacity = tester.widget<AnimatedOpacity>(
    find.ancestor(
      of: clearAllButton,
      matching: find.byType(AnimatedOpacity),
    ).first,
  );
  expect(
    animatedOpacity.opacity,
    visible ? 1.0 : 0.0,
    reason: greekExpectMsg(
      visible
          ? 'Ορατό κόκκινο Χ καθαρισμού όλων ($failContext)'
          : 'Κρυφό κόκκινο Χ καθαρισμού όλων ($failContext)',
    ),
  );
}

Future<void> _expectNoDepartmentScopedOverlays(
  WidgetTester tester, {
  required String failContext,
  String? departmentCallerName,
  Iterable<String> departmentPhones = const [],
  Iterable<String> departmentEquipmentCodes = const [],
}) async {
  final header = await _readCallHeaderState(tester);
  expect(
    header.phoneCandidates,
    isEmpty,
    reason: greekExpectMsg(
      'Κενοί υποψήφιοι τηλεφώνων μετά καθαρισμό τμήματος — $failContext',
    ),
  );
  expect(
    header.equipmentCandidates,
    isEmpty,
    reason: greekExpectMsg(
      'Κενοί υποψήφιοι εξοπλισμού μετά καθαρισμό τμήματος — $failContext',
    ),
  );
  expect(
    header.callerCandidates,
    isEmpty,
    reason: greekExpectMsg(
      'Κενοί υποψήφιοι καλούντα μετά καθαρισμό τμήματος — $failContext',
    ),
  );

  await tester.tap(callLoggerPhoneTextField());
  await pumpUntilSettled(tester);
  expect(
    find.byType(SmartEntityPhoneSuggestionList),
    findsNothing,
    reason: greekExpectMsg(
      'Χωρίς overlay τηλεφώνων τμήματος — $failContext',
    ),
  );
  for (final phone in departmentPhones) {
    expect(
      find.widgetWithText(ListTile, phone),
      findsNothing,
      reason: greekExpectMsg(
        'Δεν εμφανίζεται φιλτραρισμένος αριθμός $phone — $failContext',
      ),
    );
  }

  await tester.tap(_callLoggerEquipmentTextField());
  await pumpUntilSettled(tester);
  expect(
    find.byType(SmartEntityEquipmentSuggestionList),
    findsNothing,
    reason: greekExpectMsg(
      'Χωρίς overlay εξοπλισμού τμήματος — $failContext',
    ),
  );
  for (final code in departmentEquipmentCodes) {
    expect(
      _equipmentCodeInListFinder(code),
      findsNothing,
      reason: greekExpectMsg(
        'Δεν εμφανίζεται φιλτραρισμένος εξοπλισμός $code — $failContext',
      ),
    );
  }

  await tester.tap(_callLoggerCallerTextField());
  await pumpUntilSettled(tester);
  if (departmentCallerName != null && departmentCallerName.trim().isNotEmpty) {
    expect(
      find.descendant(
        of: find.byType(SmartEntityCallerSuggestionList),
        matching: find.textContaining(departmentCallerName),
      ),
      findsNothing,
      reason: greekExpectMsg(
        'Η overlay καλούντα δεν περιέχει «$departmentCallerName» — $failContext',
      ),
    );
  } else {
    expect(
      find.byType(SmartEntityCallerSuggestionList),
      findsNothing,
      reason: greekExpectMsg(
        'Χωρίς overlay καλούντα τμήματος — $failContext',
      ),
    );
  }
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

/// Τμήμα «Δοκιμαστικό»: κοινόχρηστα τηλέφωνα 2001–2003, κοινόχρηστος εξοπλισμός 1001–1003.
/// Τμήμα με ορφανό τηλέφωνο (department_phones χωρίς user_phones) και κοινόχρηστο εξοπλισμό.
Future<int> _seedOrphanDepartmentPhoneEquipmentScenario() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('user_equipment');
  await db.delete('user_phones');
  await db.delete('department_phones');
  await db.delete('phones');
  await db.delete('equipment');
  await db.delete('users');
  await db.delete('departments');

  final deptId = await db.insert('departments', {
    'name': _kOrphanDepartmentName,
    'name_key': SearchTextNormalizer.normalizeForSearch(_kOrphanDepartmentName),
    'is_deleted': 0,
  });

  final phoneId = await db.insert('phones', {
    'number': _kOrphanDepartmentPhone,
    'is_deleted': 0,
  });
  await db.insert('department_phones', {
    'department_id': deptId,
    'phone_id': phoneId,
  });

  await db.insert('equipment', {
    'code_equipment': _kOrphanDepartmentEquipment,
    'department_id': deptId,
    'is_deleted': 0,
  });

  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
  return deptId;
}

Future<void> _enterPhoneDigitsAndRunLookup(
  WidgetTester tester,
  String digits,
) async {
  final phoneField = callLoggerPhoneTextField();
  await tester.tap(phoneField);
  await pumpUntilSettled(tester);
  await tester.enterText(phoneField, digits);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
  await pumpUntilSettled(tester);
  await tester.runAsync(() async {
    final container = ProviderScope.containerOf(
      tester.element(find.byType(MaterialApp)),
    );
    final notifier = container.read(callHeaderProvider.notifier);
    notifier.updatePhone(digits);
    notifier.performPhoneLookup(digits);
  });
  await tester.pump();
  await pumpUntilSettled(tester, steps: 40, step: const Duration(milliseconds: 60));
  await pumpUntilSettledLong(tester);
}

Future<int> _seedDokimastikoDepartmentAssetsScenario() async {
  final db = await DatabaseHelper.instance.database;
  await db.delete('user_equipment');
  await db.delete('user_phones');
  await db.delete('department_phones');
  await db.delete('phones');
  await db.delete('equipment');
  await db.delete('users');
  await db.delete('departments');

  final deptId = await db.insert('departments', {
    'name': _kDokimastikoDepartmentName,
    'name_key': SearchTextNormalizer.normalizeForSearch(
      _kDokimastikoDepartmentName,
    ),
    'is_deleted': 0,
  });

  for (final phone in _kDokimastikoSharedPhones) {
    final phoneId = await db.insert('phones', {
      'number': phone,
      'is_deleted': 0,
    });
    await db.insert('department_phones', {
      'department_id': deptId,
      'phone_id': phoneId,
    });
  }

  for (final code in _kDokimastikoSharedEquipmentCodes) {
    await db.insert('equipment', {
      'code_equipment': code,
      'department_id': deptId,
      'is_deleted': 0,
    });
  }

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

Future<void> _selectPhoneFromDepartmentOverlay(
  WidgetTester tester,
  String phone,
) async {
  final overlay = find.byType(SmartEntityPhoneSuggestionList);
  await _pumpUntilFinderVisible(
    tester,
    overlay,
    failDescription:
        'Η overlay λίστα τηλεφώνων τμήματος (SmartEntityPhoneSuggestionList) '
        'δεν εμφανίστηκε πριν την επιλογή $phone',
  );
  final tile = find.descendant(
    of: overlay,
    matching: find.widgetWithText(ListTile, phone),
  );
  expect(
    tile,
    findsOneWidget,
    reason: greekExpectMsg(
      'Στην overlay λίστα τμήματος εμφανίζεται ο αριθμός $phone',
    ),
  );
  await tester.tap(tile);
  await pumpUntilSettled(tester);
}

Future<void> _clearTextFieldWithBackspace(
  WidgetTester tester,
  Finder field,
) async {
  await tester.tap(field);
  await pumpUntilSettled(tester);
  final text = tester.widget<TextField>(field).controller?.text ?? '';
  for (var i = 0; i < text.length; i++) {
    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pump(const Duration(milliseconds: 30));
  }
  await pumpUntilSettled(tester);
}

Future<void> _clearEquipmentWithClearButton(WidgetTester tester) async {
  await tester.tap(_callLoggerEquipmentTextField());
  await pumpUntilSettled(tester);
  final clearButton = find.descendant(
    of: find.byType(SmartEntityEquipmentField),
    matching: find.byIcon(Icons.close),
  );
  expect(
    clearButton,
    findsOneWidget,
    reason: greekExpectMsg('Κουμπί «χ» καθαρισμού εξοπλισμού'),
  );
  await tester.tap(clearButton);
  await pumpUntilSettled(tester);
}

Future<void> _runDokimastikoDepartmentEquipPhoneBaseFlow(
  WidgetTester tester,
) async {
  await _selectDepartmentFromAutocomplete(
    tester,
    _kDokimastikoDepartmentName,
  );

  await tester.tap(_callLoggerEquipmentTextField());
  await pumpUntilSettled(tester);
  await _selectEquipmentFromList(tester, _kDokimastikoScenarioEquipment);

  await tester.tap(callLoggerPhoneTextField());
  await pumpUntilSettled(tester);
  await _selectPhoneFromDepartmentOverlay(tester, _kDokimastikoScenarioPhone);
}

Future<void> _expectDepartmentEquipmentOverlayVisible(
  WidgetTester tester, {
  required String failContext,
}) async {
  await tester.tap(_callLoggerEquipmentTextField());
  await pumpUntilSettled(tester);

  final overlay = find.byType(SmartEntityEquipmentSuggestionList);
  await _pumpUntilFinderVisible(
    tester,
    overlay,
    failDescription:
        'Η overlay λίστα εξοπλισμού τμήματος (SmartEntityEquipmentSuggestionList) '
        'δεν εμφανίστηκε — $failContext',
  );
  expect(
    overlay,
    findsOneWidget,
    reason: greekExpectMsg(
      'Ορατή overlay λίστα εξοπλισμού τμήματος — $failContext',
    ),
  );
  for (final code in _kDokimastikoSharedEquipmentCodes) {
    final codeInOverlay = find.descendant(
      of: overlay,
      matching: _equipmentCodeInListFinder(code),
    );
    expect(
      codeInOverlay,
      findsOneWidget,
      reason: greekExpectMsg(
        'Στην overlay εμφανίζεται ο εξοπλισμός $code — $failContext',
      ),
    );
  }
}

Future<void> _expectDepartmentPhoneOverlayVisible(
  WidgetTester tester, {
  required String failContext,
}) async {
  await tester.tap(callLoggerPhoneTextField());
  await pumpUntilSettled(tester);

  final overlay = find.byType(SmartEntityPhoneSuggestionList);
  await _pumpUntilFinderVisible(
    tester,
    overlay,
    failDescription:
        'Η overlay λίστα τηλεφώνων τμήματος (SmartEntityPhoneSuggestionList) '
        'δεν εμφανίστηκε — $failContext',
  );
  expect(
    overlay,
    findsOneWidget,
    reason: greekExpectMsg(
      'Ορατή overlay λίστα τηλεφώνων τμήματος — $failContext',
    ),
  );
  for (final phone in _kDokimastikoSharedPhones) {
    final phoneInOverlay = find.descendant(
      of: overlay,
      matching: find.widgetWithText(ListTile, phone),
    );
    expect(
      phoneInOverlay,
      findsOneWidget,
      reason: greekExpectMsg(
        'Στην overlay εμφανίζεται ο αριθμός $phone — $failContext',
      ),
    );
  }
}

Future<void> _finishCallFormWidgetTest(WidgetTester tester) async {
  // sqflite lock retry timer (10s) — βλ. test_setup.dart tearDown.
  // Σημειώσεις εμφανίζονται μόνο με ενεργή Ομάδα Τηλεφώνου· μην απαιτείται εδώ.
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

    // Σενάριο: επιλογή τμήματος → καθαρισμός τμήματος → χωρίς φιλτραρισμένες λίστες / κόκκινο Χ.
    //   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "καθαρισμό τμήματος"
    testWidgets(
      'καθαρισμό τμήματος: οι λίστες ξεφιλτράρονται και εξαφανίζεται το κόκκινο Χ',
      (tester) async {
        _configureDesktopViewport(tester);

        final reporter = GreekTestReportCollector();
        final expectedCallerName = '$_kMariaFirstName $_kMariaLastName';

        reporter.logProgress('Φόρτωση οθόνης «Νέα Κλήση»');
        await _loadCallFormApp(tester);
        reporter.logStepDone('Εφαρμογή φορτώθηκε');

        reporter.logProgress('Επιλογή τμήματος «$_kFantasmaDepartmentName»');
        await _selectDepartmentFromAutocomplete(
          tester,
          _kFantasmaDepartmentName,
        );

        final headerWithDept = await _readCallHeaderState(tester);
        expect(
          headerWithDept.selectedDepartmentId,
          deptId,
          reason: greekExpectMsg('Επιλεγμένο τμήμα στο state'),
        );
        expect(
          headerWithDept.phoneCandidates,
          isNotEmpty,
          reason: greekExpectMsg('Φιλτραρισμένοι υποψήφιοι τηλεφώνων τμήματος'),
        );
        expect(
          headerWithDept.equipmentCandidates,
          isNotEmpty,
          reason: greekExpectMsg('Φιλτραρισμένοι υποψήφιοι εξοπλισμού τμήματος'),
        );
        expect(
          headerWithDept.callerCandidates
              .map((u) => u.name ?? u.fullNameWithDepartment)
              .toList(),
          contains(expectedCallerName),
          reason: greekExpectMsg('Φιλτραρισμένοι υποψήφιοι καλούντα τμήματος'),
        );
        await _expectClearAllButtonVisible(
          tester,
          visible: true,
          failContext: 'μετά επιλογή τμήματος',
        );
        reporter.logStepDone('Τμήμα επιλέχθηκε — φιλτραρισμένες λίστες ενεργές');

        reporter.logProgress('Καθαρισμός πεδίου τμήματος');
        await _clearDepartmentField(tester);

        final headerAfterClear = await _readCallHeaderState(tester);
        expect(
          headerAfterClear.departmentText.trim(),
          isEmpty,
          reason: greekExpectMsg('Κενό πεδίο τμήματος μετά καθαρισμό'),
        );
        expect(
          headerAfterClear.selectedDepartmentId,
          isNull,
          reason: greekExpectMsg('Μηδενισμένο id τμήματος μετά καθαρισμό'),
        );
        reporter.logStepDone('Τμήμα καθαρίστηκε');

        reporter.logProgress(
          'Έλεγχος: χωρίς φιλτραρισμένες λίστες και κρυφό κόκκινο Χ',
        );
        await _expectNoDepartmentScopedOverlays(
          tester,
          failContext: 'μετά καθαρισμό τμήματος',
          departmentCallerName: expectedCallerName,
          departmentPhones: [_kSharedPhone, _kUserOnlyPhone],
          departmentEquipmentCodes: [
            ..._kSharedEquipmentCodes,
            _kUserEquipmentCode,
          ],
        );
        await _expectClearAllButtonVisible(
          tester,
          visible: false,
          failContext: 'μετά καθαρισμό τμήματος',
        );
        reporter.logStepDone('Λίστες ξεφιλτράρονται — κόκκινο Χ κρυφό');

        await _finishCallFormWidgetTest(tester);
        reporter.recordPass('Καθαρισμός τμήματος — regression overlay / κόκκινο Χ');
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

  group('Φόρμα κλήσης — Δοκιμαστικό overlay μετά καθαρισμό (widget)', () {
    setUp(() async {
      await _seedDokimastikoDepartmentAssetsScenario();
    });

    // Σενάριο 1: τμήμα → εξοπλισμός 1002 → τηλέφωνο 2003 → καθαρισμός εξοπλισμού → overlay.
    //   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "καθαρισμό εξοπλισμού"
    testWidgets(
      'Δοκιμαστικό: μετά καθαρισμό εξοπλισμού επαναεμφανίζεται overlay λίστας τμήματος',
      (tester) async {
        _configureDesktopViewport(tester);
        final reporter = GreekTestReportCollector();

        reporter.logProgress('Οθόνη «Νέα Κλήση» — σενάριο Δοκιμαστικό (σενάριο 1)');
        await _loadCallFormApp(tester);
        reporter.logStepDone('Εφαρμογή φορτώθηκε');

        reporter.logProgress(
          'Ροή: τμήμα → εξοπλισμός $_kDokimastikoScenarioEquipment → '
          'τηλέφωνο $_kDokimastikoScenarioPhone',
        );
        await _runDokimastikoDepartmentEquipPhoneBaseFlow(tester);
        reporter.logStepDone('Βασική ροή ολοκληρώθηκε');

        reporter.logProgress('Καθαρισμός εξοπλισμού με backspace');
        await _clearTextFieldWithBackspace(
          tester,
          _callLoggerEquipmentTextField(),
        );
        final headerAfterClear = await _readCallHeaderState(tester);
        expect(
          headerAfterClear.equipmentText,
          isEmpty,
          reason: greekExpectMsg('Το πεδίο εξοπλισμού είναι κενό μετά backspace'),
        );
        reporter.logStepDone('Εξοπλισμός καθαρίστηκε');

        reporter.logProgress(
          'Κλικ εξοπλισμός — αναμένεται ορατή overlay λίστα τμήματος',
        );
        await _expectDepartmentEquipmentOverlayVisible(
          tester,
          failContext: 'μετά backspace εξοπλισμού με επιλεγμένο τηλέφωνο',
        );
        reporter.logStepDone('Overlay εξοπλισμού τμήματος εμφανίστηκε');

        await _finishCallFormWidgetTest(tester);
        reporter.recordPass('Σενάριο 1 — overlay εξοπλισμού μετά καθαρισμό');
      },
      semanticsEnabled: false,
    );

    // Σενάριο 2: τμήμα → εξοπλισμός 1002 → τηλέφωνο 2003 → καθαρισμός τηλεφώνου → overlay.
    //   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "καθαρισμό τηλεφώνου"
    testWidgets(
      'Δοκιμαστικό: μετά καθαρισμό τηλεφώνου επαναεμφανίζεται overlay λίστας τμήματος',
      (tester) async {
        _configureDesktopViewport(tester);
        final reporter = GreekTestReportCollector();

        reporter.logProgress('Οθόνη «Νέα Κλήση» — σενάριο Δοκιμαστικό (σενάριο 2)');
        await _loadCallFormApp(tester);
        reporter.logStepDone('Εφαρμογή φορτώθηκε');

        await _runDokimastikoDepartmentEquipPhoneBaseFlow(tester);
        reporter.logStepDone('Βασική ροή ολοκληρώθηκε');

        reporter.logProgress('Καθαρισμός τηλεφώνου με backspace');
        await _clearTextFieldWithBackspace(
          tester,
          callLoggerPhoneTextField(),
        );
        final headerAfter = await _readCallHeaderState(tester);
        expect(
          headerAfter.selectedPhone,
          anyOf(isNull, ''),
          reason: greekExpectMsg('Το πεδίο τηλεφώνου είναι κενό μετά backspace'),
        );
        reporter.logStepDone('Τηλέφωνο καθαρίστηκε');

        reporter.logProgress(
          'Κλικ τηλέφωνο — αναμένεται ορατή overlay λίστα τμήματος',
        );
        await _expectDepartmentPhoneOverlayVisible(
          tester,
          failContext: 'μετά backspace τηλεφώνου με επιλεγμένο εξοπλισμό',
        );
        reporter.logStepDone('Overlay τηλεφώνων τμήματος εμφανίστηκε');

        await _finishCallFormWidgetTest(tester);
        reporter.recordPass('Σενάριο 2 — overlay τηλεφώνων μετά καθαρισμό');
      },
      semanticsEnabled: false,
    );

    // Σενάριο 3: καθαρισμός τηλεφώνου και εξοπλισμού → overlay και στα δύο πεδία.
    //   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "καθαρισμό τηλεφώνου και εξοπλισμού"
    testWidgets(
      'Δοκιμαστικό: μετά καθαρισμό τηλεφώνου και εξοπλισμού επαναεμφανίζονται overlays τμήματος',
      (tester) async {
        _configureDesktopViewport(tester);
        final reporter = GreekTestReportCollector();

        reporter.logProgress('Οθόνη «Νέα Κλήση» — σενάριο Δοκιμαστικό (σενάριο 3)');
        await _loadCallFormApp(tester);
        reporter.logStepDone('Εφαρμογή φορτώθηκε');

        await _runDokimastikoDepartmentEquipPhoneBaseFlow(tester);
        reporter.logStepDone('Βασική ροή ολοκληρώθηκε');

        reporter.logProgress('Καθαρισμός τηλεφώνου με backspace');
        await _clearTextFieldWithBackspace(
          tester,
          callLoggerPhoneTextField(),
        );
        reporter.logStepDone('Τηλέφωνο καθαρίστηκε');

        reporter.logProgress('Καθαρισμός εξοπλισμού με κουμπί «χ»');
        await _clearEquipmentWithClearButton(tester);
        final headerAfter = await _readCallHeaderState(tester);
        expect(
          headerAfter.equipmentText,
          isEmpty,
          reason: greekExpectMsg('Το πεδίο εξοπλισμού είναι κενό μετά «χ»'),
        );
        expect(
          headerAfter.selectedPhone,
          anyOf(isNull, ''),
          reason: greekExpectMsg('Το πεδίο τηλεφώνου είναι κενό'),
        );
        reporter.logStepDone('Εξοπλισμός καθαρίστηκε');

        reporter.logProgress(
          'Κλικ τηλέφωνο — αναμένεται ορατή overlay λίστα τμήματος',
        );
        await _expectDepartmentPhoneOverlayVisible(
          tester,
          failContext: 'μετά καθαρισμό και των δύο πεδίων (τηλέφωνο)',
        );
        reporter.logStepDone('Overlay τηλεφώνων τμήματος εμφανίστηκε');

        reporter.logProgress(
          'Κλικ εξοπλισμός — αναμένεται ορατή overlay λίστα τμήματος',
        );
        await _expectDepartmentEquipmentOverlayVisible(
          tester,
          failContext: 'μετά καθαρισμό και των δύο πεδίων (εξοπλισμός)',
        );
        reporter.logStepDone('Overlay εξοπλισμού τμήματος εμφανίστηκε');

        await _finishCallFormWidgetTest(tester);
        reporter.recordPass('Σενάριο 3 — overlays μετά διπλό καθαρισμό');
      },
      semanticsEnabled: false,
    );
  });

  group('Φόρμα κλήσης — ορφανό τηλέφωνο τμήματος (widget)', () {
    late int deptId;

    setUp(() async {
      deptId = await _seedOrphanDepartmentPhoneEquipmentScenario();
    });

    // Σενάριο: τηλέφωνο 2580 → αυτόματο τμήμα, χωρίς χρήστη, αναμενόμενος εξοπλισμός 3856.
    //   flutter test test/features/calls/call_form_department_assets_test.dart --plain-name "ορφανό τηλέφωνο τμήματος"
    testWidgets(
      'ορφανό τηλέφωνο τμήματος: lookup τηλεφώνου συμπληρώνει τμήμα και εξοπλισμό',
      (tester) async {
        _configureDesktopViewport(tester);

        final reporter = GreekTestReportCollector();

        reporter.logProgress(
          'Οθόνη «Νέα Κλήση» — τηλέφωνο $_kOrphanDepartmentPhone χωρίς καλούντα',
        );
        await _loadCallFormApp(tester);
        reporter.logStepDone('Εφαρμογή φορτώθηκε');

        reporter.logProgress(
          'Πληκτρολόγηση $_kOrphanDepartmentPhone — αναμενόμενο τμήμα «$_kOrphanDepartmentName»',
        );
        await _enterPhoneDigitsAndRunLookup(tester, _kOrphanDepartmentPhone);

        final headerAfterLookup = await _readCallHeaderState(tester);
        expect(
          headerAfterLookup.departmentText,
          _kOrphanDepartmentName,
          reason: greekExpectMsg(
            'Το lookup τηλεφώνου πρέπει να συμπληρώνει το τμήμα από department_phones',
          ),
        );
        expect(
          headerAfterLookup.selectedDepartmentId,
          deptId,
          reason: greekExpectMsg('Επιλεγμένο id τμήματος μετά το lookup'),
        );
        expect(
          headerAfterLookup.callerNoMatch,
          isTrue,
          reason: greekExpectMsg(
            'Χωρίς χρήστη στο τηλέφωνο εμφανίζεται «Καμία αντιστοιχία» καλούντα',
          ),
        );
        expect(
          find.descendant(
            of: find.byType(SmartEntityCallerField),
            matching: find.text('Καμία αντιστοιχία'),
          ),
          findsOneWidget,
          reason: greekExpectMsg('Υπόδειξη «Καμία αντιστοιχία» στο πεδίο καλούντα'),
        );
        reporter.logStepDone('Τμήμα συμπληρώθηκε — καλούντας χωρίς αντιστοιχία');

        reporter.logProgress(
          'Έλεγχος αυτόματης συμπλήρωσης εξοπλισμού $_kOrphanDepartmentEquipment',
        );
        expect(
          headerAfterLookup.selectedEquipment?.code,
          _kOrphanDepartmentEquipment,
          reason: greekExpectMsg(
            'Με μοναδικό εξοπλισμό τμήματος, το lookup τηλεφώνου πρέπει να '
            'επιλέγει τον κωδικό $_kOrphanDepartmentEquipment',
          ),
        );
        expect(
          headerAfterLookup.equipmentCandidates
              .map((EquipmentModel e) => e.code?.trim())
              .whereType<String>()
              .toSet(),
          {_kOrphanDepartmentEquipment},
          reason: greekExpectMsg(
            'Ο εξοπλισμός τμήματος είναι διαθέσιμος στους υποψήφιους μετά το lookup',
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 100));
        expect(
          find.descendant(
            of: find.byType(SmartEntityEquipmentField),
            matching: find.textContaining(_kOrphanDepartmentEquipment),
          ),
          findsWidgets,
          reason: greekExpectMsg(
            'Ο κωδικός $_kOrphanDepartmentEquipment εμφανίζεται στο πεδίο εξοπλισμού',
          ),
        );
        reporter.logStepDone('Εξοπλισμός συμπληρώθηκε αυτόματα');

        reporter.logProgress('Κλικ στο πεδίο εξοπλισμού — αναμένεται στη λίστα');
        await tester.tap(_callLoggerEquipmentTextField());
        await pumpUntilSettled(tester);

        final equipmentTile =
            _equipmentCodeInListFinder(_kOrphanDepartmentEquipment);
        await _pumpUntilFinderVisible(
          tester,
          equipmentTile,
          failDescription:
              'Ο εξοπλισμός $_kOrphanDepartmentEquipment δεν εμφανίστηκε στη λίστα '
              'μετά lookup ορφανού τηλεφώνου τμήματος',
        );
        expect(
          equipmentTile,
          findsWidgets,
          reason: greekExpectMsg(
            'Με κλικ στο πεδίο εξοπλισμού εμφανίζεται ο $_kOrphanDepartmentEquipment',
          ),
        );
        reporter.logStepDone('Εξοπλισμός ορατός στη λίστα overlay');

        await _finishCallFormWidgetTest(tester);
        reporter.recordPass(
          'ορφανό τηλέφωνο τμήματος: τμήμα + εξοπλισμός από lookup',
        );
      },
      semanticsEnabled: false,
    );
  });
}
