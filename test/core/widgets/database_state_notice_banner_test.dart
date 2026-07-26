// Λωρίδα ειδοποίησης παλιάς/κενής βάσης στο MainShell.
//
//   flutter test test/core/widgets/database_state_notice_banner_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/database_init_result.dart';
import 'package:call_logger/core/database/database_state_notice.dart';
import 'package:call_logger/core/services/lookup_service.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/core/widgets/main_shell.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:call_logger/features/calls/provider/calls_dashboard_providers.dart';
import 'package:call_logger/features/tasks/providers/tasks_provider.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../test_setup.dart';

DatabaseFileProfile _oldProfile() {
  final latest = DateTime.now().subtract(
    const Duration(days: kOldDatabaseNoticeThresholdDays + 5),
  );
  return DatabaseFileProfile(
    kind: DatabaseFileKind.callLogger,
    callCount: 12480,
    userCount: 10,
    phoneCount: 20,
    equipmentCount: 15,
    departmentCount: 3,
    latestCallDate:
        '${latest.year.toString().padLeft(4, '0')}-'
        '${latest.month.toString().padLeft(2, '0')}-'
        '${latest.day.toString().padLeft(2, '0')}',
  );
}

Future<void> _pumpShell(
  WidgetTester tester, {
  required DatabaseFileProfile profile,
  required String path,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        ...callLoggerTestProviderOverrides(),
        globalRecentCallsProvider.overrideWith(
          (ref) async => const <CallModel>[],
        ),
        globalPendingTasksCountProvider.overrideWith((ref) async => 0),
      ],
      child: MaterialApp(
        home: MainShell(
          databaseResult: DatabaseInitResult.success(path),
          isLocalDevMode: false,
          databaseProfile: profile,
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

Future<void> _flushPendingTimers(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 11));
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUpAll(() async {
    LookupService.instance.resetForReload();
    await LookupService.instance.loadFromDatabase();
  });

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('εμφανίζει λωρίδα για παλιά βάση', (tester) async {
    final path = (await DatabaseHelper.instance.database).path;
    await _pumpShell(tester, profile: _oldProfile(), path: path);

    expect(
      find.byKey(const ValueKey('database_state_notice_banner')),
      findsOneWidget,
    );
    expect(find.textContaining('ΠΑΛΙΑ ΒΑΣΗ'), findsOneWidget);
    await _flushPendingTimers(tester);
  });

  testWidgets('εξαφανίζεται μετά το πάτημα του X', (tester) async {
    final path = (await DatabaseHelper.instance.database).path;
    await _pumpShell(tester, profile: _oldProfile(), path: path);
    expect(
      find.byKey(const ValueKey('database_state_notice_banner')),
      findsOneWidget,
    );

    await tester.tap(
      find.byKey(const ValueKey('database_state_notice_dismiss')),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.byKey(const ValueKey('database_state_notice_banner')),
      findsNothing,
    );
    await _flushPendingTimers(tester);
  });

  testWidgets('δεν εμφανίζεται όταν η αποθηκευμένη ταυτότητα ταιριάζει', (
    tester,
  ) async {
    final path = (await DatabaseHelper.instance.database).path;
    final profile = _oldProfile();
    final modifiedMs = File(path).lastModifiedSync().millisecondsSinceEpoch;
    final identity = databaseContentIdentity(
      dbPath: path,
      latestCallDate: profile.latestCallDate,
      callCount: profile.callCount,
      userCount: profile.userCount,
      phoneCount: profile.phoneCount,
      equipmentCount: profile.equipmentCount,
      departmentCount: profile.departmentCount,
      fileModifiedMs: modifiedMs,
    );
    await SettingsService().setAcknowledgedDatabaseNoticeIdentity(identity);

    await _pumpShell(tester, profile: profile, path: path);

    expect(
      find.byKey(const ValueKey('database_state_notice_banner')),
      findsNothing,
    );
    await _flushPendingTimers(tester);
  });
}
