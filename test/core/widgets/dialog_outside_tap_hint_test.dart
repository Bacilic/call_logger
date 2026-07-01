// Widget test: κλικ σε πρόταση Autocomplete μέσα σε διάλογο με outside-tap hint
// δεν πρέπει να ενεργοποιεί flash ούτε να καθαρίζει άλλα πεδία.
//
//   flutter test test/core/widgets/dialog_outside_tap_hint_test.dart

import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/remote_paths_provider.dart';
import 'package:call_logger/features/calls/screens/widgets/quick_call_dialog.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_caller_field.dart';
import 'package:call_logger/features/calls/screens/widgets/smart_entity_selector_department_field.dart';
import 'package:call_logger/features/directory/models/department_model.dart';
import 'package:call_logger/features/history/providers/history_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

const _kTestCallerText = 'Δοκιμαστικός Καλών';
const _kTestDepartmentName = 'Πληροφορική';

class _FakeLookupService extends LookupService {
  _FakeLookupService() : super.forTest();

  static final List<DepartmentModel> _departments = [
    DepartmentModel(id: 1, name: _kTestDepartmentName),
    DepartmentModel(id: 2, name: 'Παιδιατρική'),
  ];

  @override
  List<String> searchPhonesByPrefix(String prefix) => const [];

  @override
  List<UserModel> searchUsersByQuery(String query) => const [];

  @override
  List<UserModel> findUsersByPhone(String phone) => const [];

  @override
  List<EquipmentModel> findEquipmentsForUser(int userId) => const [];

  @override
  List<EquipmentModel> findEquipmentsByCode(String query) => const [];

  @override
  List<DepartmentModel> searchDepartments(String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return _departments;
    return _departments
        .where((d) => d.name.toLowerCase().contains(q))
        .toList();
  }
}

Finder _callerField() {
  return find.descendant(
    of: find.byType(SmartEntityCallerField),
    matching: find.byType(TextField),
  );
}

Finder _departmentField() {
  return find.descendant(
    of: find.byType(SmartEntityDepartmentField),
    matching: find.byType(TextField),
  );
}

const _kDialogFlashBackdropKey = ValueKey('dialog_flash_backdrop');

AnimatedContainer? _dialogFlashBackdrop(WidgetTester tester) {
  final containerFinder = find.byKey(_kDialogFlashBackdropKey);
  if (containerFinder.evaluate().isEmpty) return null;
  return tester.widget<AnimatedContainer>(containerFinder);
}

bool _isDialogFlashActive(WidgetTester tester) {
  final container = _dialogFlashBackdrop(tester);
  if (container == null) return false;
  final fg = container.foregroundDecoration;
  if (fg == null) return false;
  if (fg is! BoxDecoration) return false;
  final border = fg.border;
  if (border is! Border) return false;
  return border.top.color.a > 0;
}

/// Το χρώμα (target) του υποστρώματος — αλλάζει σε primary απόχρωση κατά το flash.
Color? _dialogBackdropColor(WidgetTester tester) {
  final container = _dialogFlashBackdrop(tester);
  final decoration = container?.decoration;
  if (decoration is BoxDecoration) return decoration.color;
  return null;
}

Future<void> _pumpHarness(WidgetTester tester) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        lookupServiceProvider.overrideWith(
          (ref) async => LookupLoadResult(service: _FakeLookupService()),
        ),
        remoteToolsCatalogProvider.overrideWith(
          (ref) async => const <RemoteTool>[],
        ),
        remoteToolsAllCatalogProvider.overrideWith(
          (ref) async => const <RemoteTool>[],
        ),
        historyCategoryEntriesProvider.overrideWith(
          (ref) async => const <({int id, String name})>[],
        ),
      ],
      child: MaterialApp(
        locale: const Locale('el'),
        supportedLocales: const [Locale('el', 'GR'), Locale('en', 'US')],
        localizationsDelegates: const [
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: Builder(
          builder: (context) {
            return Scaffold(
              body: Center(
                child: ElevatedButton(
                  onPressed: () => showQuickCallDialog(context),
                  child: const Text('Άνοιγμα γρήγορης καταγραφής'),
                ),
              ),
            );
          },
        ),
      ),
    ),
  );
  await tester.pump();
  await pumpUntilSettled(tester);
}

Future<void> _openQuickCallDialog(WidgetTester tester) async {
  await tester.tap(find.text('Άνοιγμα γρήγορης καταγραφής'));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilSettled(tester);
  expect(
    find.byKey(const ValueKey('quick_call_dialog')),
    findsOneWidget,
  );
}

Future<void> _dismissQuickCallDialog(WidgetTester tester) async {
  final dialog = find.byKey(const ValueKey('quick_call_dialog'));
  if (dialog.evaluate().isEmpty) return;
  await tester.tap(
    find.descendant(of: dialog, matching: find.byTooltip('Κλείσιμο')),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  await pumpUntilSettled(tester);
}

void main() {
  group('DialogOutsideTapHint — Autocomplete μέσα σε διάλογο', () {
    testWidgets(
      'κλικ σε πρόταση τμήματος δεν ενεργοποιεί flash και διατηρεί κείμενο καλούντα',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        addTearDown(() async {
          await _dismissQuickCallDialog(tester);
        });

        await _pumpHarness(tester);
        await _openQuickCallDialog(tester);

        await tester.tap(_callerField());
        await pumpUntilSettled(tester);
        await tester.enterText(_callerField(), _kTestCallerText);
        await pumpUntilSettled(tester);
        expect(
          tester.widget<TextField>(_callerField()).controller?.text,
          _kTestCallerText,
        );

        await tester.tap(_departmentField());
        await pumpUntilSettled(tester);
        await tester.enterText(_departmentField(), _kTestDepartmentName.substring(0, 3));
        await pumpUntilSettled(tester);

        final option = find.descendant(
          of: find.byType(Material),
          matching: find.widgetWithText(ListTile, _kTestDepartmentName),
        );
        expect(option, findsWidgets);

        await tester.tap(option.first);
        await pumpUntilSettled(tester);
        await tester.pump(const Duration(milliseconds: 500));

        expect(
          tester.widget<TextField>(_callerField()).controller?.text,
          _kTestCallerText,
          reason:
              'Το κείμενο καλούντα πρέπει να διατηρείται μετά την επιλογή τμήματος από τη λίστα',
        );
        expect(
          _isDialogFlashActive(tester),
          isFalse,
          reason:
              'Κλικ σε πρόταση Autocomplete δεν πρέπει να ενεργοποιεί το flash έξω από τον διάλογο',
        );
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'κλικ έξω από τον διάλογο αναβοσβήνει το υπόστρωμα',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        addTearDown(() async {
          await _dismissQuickCallDialog(tester);
        });

        await _pumpHarness(tester);
        await _openQuickCallDialog(tester);

        // Σε ηρεμία το υπόστρωμα έχει το σκοτεινό χρώμα (χωρίς primary απόχρωση).
        final restColor = _dialogBackdropColor(tester);
        expect(restColor, isNotNull);
        expect(
          _isDialogFlashActive(tester),
          isFalse,
          reason: 'Πριν το κλικ, το υπόστρωμα δεν πρέπει να αναβοσβήνει',
        );

        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 150));

        expect(
          _isDialogFlashActive(tester),
          isTrue,
          reason:
              'Κλικ στο scrim έξω από τον διάλογο πρέπει να ενεργοποιεί flash στο υπόστρωμα',
        );
        expect(
          _dialogBackdropColor(tester),
          isNot(equals(restColor)),
          reason:
              'Κατά το flash, το χρώμα του υποστρώματος πρέπει να αλλάζει (primary απόχρωση)',
        );

        await tester.pump(const Duration(milliseconds: 900));
      },
      semanticsEnabled: false,
    );

    testWidgets(
      'κλικ στο scrim (flash έξω από διάλογο) διατηρεί κείμενο καλούντα',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });
        addTearDown(() async {
          await _dismissQuickCallDialog(tester);
        });

        await _pumpHarness(tester);
        await _openQuickCallDialog(tester);

        await tester.tap(_callerField());
        await pumpUntilSettled(tester);
        await tester.enterText(_callerField(), _kTestCallerText);
        await pumpUntilSettled(tester);
        expect(
          tester.widget<TextField>(_callerField()).controller?.text,
          _kTestCallerText,
        );

        // Γνήσιο κλικ στο scrim, έξω από το ορατό κουτί του διαλόγου.
        await tester.tapAt(const Offset(10, 10));
        await tester.pump();
        expect(
          _isDialogFlashActive(tester),
          isTrue,
          reason: 'Κλικ στο scrim πρέπει να ενεργοποιεί το flash',
        );

        await tester.pump(const Duration(milliseconds: 900));

        expect(
          tester.widget<TextField>(_callerField()).controller?.text,
          _kTestCallerText,
          reason:
              'Μετά το flash από κλικ έξω, το κείμενο καλούντα πρέπει να διατηρείται',
        );
      },
      semanticsEnabled: false,
    );
  });
}
