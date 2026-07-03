// Widget test: φόρμα εξοπλισμού — δημιουργία, επεξεργασία, απομακρυσμένη σύνδεση.
//
// Ολόκληρο αρχείο:
//   flutter test test/features/directory/screens/widgets/equipment_form_dialog_test.dart

import 'dart:convert';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/models/remote_tool.dart';
import 'package:call_logger/core/models/remote_tool_role.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/features/calls/models/equipment_model.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/remote_paths_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:call_logger/features/directory/screens/widgets/equipment_form_dialog.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:riverpod/misc.dart' show Override;

import '../../../../test_reporter.dart';
import '../../../../test_setup.dart';

const _kOpenEquipmentFormButton = 'OPEN_EQUIP_FORM';
const _kNewEquipmentTitle = 'Νέος εξοπλισμός';
const _kEditEquipmentTitle = 'Επεξεργασία εξοπλισμού';
const _kUnsavedChangesPrompt = 'Θέλεται να γίνει:';
const _kNewEquipmentCode = 'EQ-CHAR-9001';
const _kRemoteVncToolName = 'UltraVNC Test';
const _kRemoteVncParamValue = '10.0.0.55';

RemoteTool get _kTestVncRemoteTool => RemoteTool(
      id: 1,
      name: _kRemoteVncToolName,
      role: ToolRole.vnc,
      executablePath: r'C:\vnc\viewer.exe',
      launchMode: 'direct_exec',
      sortOrder: 1,
      isActive: true,
    );

RemoteToolFormPair get _kTestVncFormPair => (
      label: _kRemoteVncToolName,
      key: '1',
      acceptsFileParam: false,
    );

Finder _fieldByLabel(String label) {
  return find.descendant(
    of: find.byWidgetPredicate(
      (w) => w is InputDecorator && w.decoration.labelText == label,
    ),
    matching: find.byType(EditableText),
  );
}

Finder _codeField() => _fieldByLabel('Κωδικός');

Finder _notesField() => _fieldByLabel('Σημειώσεις');

Finder _locationField() => _fieldByLabel('Τοποθεσία');

List<Override> _equipmentFormProviderOverrides({
  List<RemoteTool>? catalog,
  List<RemoteToolFormPair>? pairs,
}) {
  final base = callLoggerTestProviderOverrides();
  final cat = catalog ?? [_kTestVncRemoteTool];
  final prs = pairs ?? [_kTestVncFormPair];
  return <Override>[
    ...base.sublist(0, 7),
    remoteToolsCatalogProvider.overrideWith((ref) async => cat),
    remoteToolsAllCatalogProvider.overrideWith((ref) async => cat),
    remoteToolFormPairsProvider.overrideWith((ref) async => prs),
    ...base.sublist(10),
  ];
}

Future<EquipmentModel> _loadEquipmentByCode(String code) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'equipment',
    where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
    whereArgs: [code],
    limit: 1,
  );
  if (rows.isEmpty) {
    throw StateError('Equipment not found: $code');
  }
  return EquipmentModel.fromMap(rows.first);
}

Future<bool> _equipmentCodeExists(String code) async {
  final db = await DatabaseHelper.instance.database;
  final rows = await db.query(
    'equipment',
    columns: ['id'],
    where: 'code_equipment = ? AND COALESCE(is_deleted, 0) = 0',
    whereArgs: [code],
    limit: 1,
  );
  return rows.isNotEmpty;
}

Future<void> _seedEquipmentWithRemoteParams({
  required String code,
  required Map<String, String> remoteParams,
  String? defaultRemoteTool,
}) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('equipment', {
    'code_equipment': code,
    'type': 'Desktop',
    'remote_params': jsonEncode(remoteParams),
    'default_remote_tool': defaultRemoteTool,
    'is_deleted': 0,
  });
  LookupService.instance.resetForReload();
  await LookupService.instance.loadFromDatabase();
}

Future<void> _openEquipmentFormInDialog(
  WidgetTester tester,
  ProviderContainer container, {
  EquipmentModel? initialEquipment,
  required EquipmentDirectoryNotifier notifier,
}) async {
  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        home: Consumer(
          builder: (context, ref, _) => Scaffold(
            body: Center(
              child: FilledButton(
                onPressed: () => showDialog<void>(
                  context: context,
                  barrierDismissible: true,
                  builder: (ctx) => EquipmentFormDialog(
                    initialEquipment: initialEquipment,
                    notifier: notifier,
                    ref: ref,
                  ),
                ),
                child: const Text(_kOpenEquipmentFormButton),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.tap(find.text(_kOpenEquipmentFormButton));
  await pumpUntilSettledLong(tester);
}

Future<void> _pumpUntilEquipmentSaveCompletes(WidgetTester tester) async {
  const maxAttempts = 40;
  for (var i = 0; i < maxAttempts; i++) {
    final formOpen = find.text(_kNewEquipmentTitle).evaluate().isNotEmpty ||
        find.text(_kEditEquipmentTitle).evaluate().isNotEmpty;
    if (!formOpen) return;
    await tester.runAsync(() async {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump(const Duration(milliseconds: 50));
  }
  fail(
    greekExpectMsg('Η φόρμα εξοπλισμού δεν έκλεισε εγκαίρως μετά την αποθήκευση'),
  );
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Φόρμα εξοπλισμού — χαρακτηρισμός (widget)', () {
    testWidgets(
      'δημιουργία: διάλογος αποδίδεται και η αποθήκευση μπλοκάρεται χωρίς κωδικό',
      (tester) async {
        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late EquipmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(equipmentDirectoryProvider.notifier);
          await notifier.load();
          await _openEquipmentFormInDialog(tester, container, notifier: notifier);
        });

        expect(find.text(_kNewEquipmentTitle), findsOneWidget);

        await tester.enterText(_notesField(), 'Σημείωση χωρίς κωδικό');
        await pumpUntilSettled(tester);

        final addButton = find.widgetWithText(FilledButton, 'Προσθήκη');
        expect(addButton, findsOneWidget);
        expect(
          tester.widget<FilledButton>(addButton).onPressed,
          isNull,
          reason: greekExpectMsg(
            'Η προσθήκη απενεργοποιείται όταν λείπει ο υποχρεωτικός κωδικός',
          ),
        );
      },
    );

    testWidgets(
      'δημιουργία: επιτυχής αποθήκευση νέου εξοπλισμού στη βάση',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late EquipmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(equipmentDirectoryProvider.notifier);
          await notifier.load();
          await _openEquipmentFormInDialog(tester, container, notifier: notifier);
        });

        await tester.enterText(_codeField(), _kNewEquipmentCode);
        await pumpUntilSettled(tester);

        final addButton = find.widgetWithText(FilledButton, 'Προσθήκη');
        expect(
          tester.widget<FilledButton>(addButton).onPressed,
          isNotNull,
          reason: greekExpectMsg('Η προσθήκη ενεργοποιείται με συμπληρωμένο κωδικό'),
        );

        await tester.tap(addButton);
        await pumpUntilSettled(tester);
        await _pumpUntilEquipmentSaveCompletes(tester);

        final exists = await tester.runAsync(
          () => _equipmentCodeExists(_kNewEquipmentCode),
        );
        expect(exists, isTrue);
      },
    );

    testWidgets(
      'επεξεργασία: αλλαγή εμφανίζει διάλογο με τρεις επιλογές, χωρίς αλλαγές όχι',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        final container = ProviderContainer(
          overrides: callLoggerTestProviderOverrides(),
        );
        addTearDown(container.dispose);

        late EquipmentDirectoryNotifier notifier;
        late EquipmentModel initial;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(equipmentDirectoryProvider.notifier);
          await notifier.load();
          initial = await _loadEquipmentByCode(kTestEquipmentCode);
          await _openEquipmentFormInDialog(
            tester,
            container,
            initialEquipment: initial,
            notifier: notifier,
          );
        });

        expect(find.text(_kEditEquipmentTitle), findsOneWidget);

        await tester.tapAt(const Offset(8, 8));
        await pumpUntilSettled(tester);
        expect(find.textContaining(_kUnsavedChangesPrompt), findsNothing);
        expect(find.text(_kEditEquipmentTitle), findsNothing);

        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          await notifier.load();
          initial = await _loadEquipmentByCode(kTestEquipmentCode);
          await _openEquipmentFormInDialog(
            tester,
            container,
            initialEquipment: initial,
            notifier: notifier,
          );
        });

        await tester.enterText(_locationField(), 'Νέα τοποθεσία δοκιμής');
        await pumpUntilSettled(tester);
        await tester.tapAt(const Offset(8, 8));
        await pumpUntilSettled(tester);

        expect(find.text('Μη αποθηκευμένες αλλαγές'), findsOneWidget);
        expect(find.textContaining(_kUnsavedChangesPrompt), findsOneWidget);
        expect(find.text('Διατήρηση'), findsOneWidget);
        expect(find.text('Ακύρωση Αλλαγών'), findsOneWidget);
        expect(find.text('Επεξεργασία'), findsOneWidget);
        expect(find.text(_kEditEquipmentTitle), findsOneWidget);
      },
    );

    testWidgets(
      'επεξεργασία: εξοπλισμός με remote_params εμφανίζει επιλεγμένα chips',
      (tester) async {
        tester.view.physicalSize = const Size(1600, 900);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(() {
          tester.view.resetPhysicalSize();
          tester.view.resetDevicePixelRatio();
        });

        const remoteCode = 'EQ-REMOTE-CHIP';
        await tester.runAsync(() async {
          await _seedEquipmentWithRemoteParams(
            code: remoteCode,
            remoteParams: const {'1': _kRemoteVncParamValue},
            defaultRemoteTool: '1',
          );
        });

        final container = ProviderContainer(
          overrides: _equipmentFormProviderOverrides(),
        );
        addTearDown(container.dispose);

        late EquipmentDirectoryNotifier notifier;
        await tester.runAsync(() async {
          await container.read(lookupServiceProvider.future);
          notifier = container.read(equipmentDirectoryProvider.notifier);
          await notifier.load();
          final initial = await _loadEquipmentByCode(remoteCode);
          await _openEquipmentFormInDialog(
            tester,
            container,
            initialEquipment: initial,
            notifier: notifier,
          );
        });

        expect(find.text(_kEditEquipmentTitle), findsOneWidget);
        expect(
          find.widgetWithText(FilterChip, _kRemoteVncToolName),
          findsOneWidget,
          reason: greekExpectMsg(
            'Το chip του εργαλείου απομακρυσμένης εμφανίζεται επιλεγμένο',
          ),
        );
        expect(
          find.textContaining(_kRemoteVncParamValue),
          findsOneWidget,
          reason: greekExpectMsg(
            'Η αποθηκευμένη τιμή παραμέτρου εμφανίζεται στο πεδίο',
          ),
        );
      },
    );
  });
}
