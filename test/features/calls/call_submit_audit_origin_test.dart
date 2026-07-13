import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_support.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/association_two_step_runner.dart';
import '../../test_setup.dart';

/// Καλωδίωση Φάσης 3: προέλευση audit από πραγματικές ροές UI (associate + submit).
void main() {
  group('call submit audit origin — UI provider path', () {
    setUpAll(() async {
      SharedPreferences.setMockInitialValues(<String, Object>{});
      await bindCallLoggerIsolatedTestDatabase();
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    setUp(() async {
      await AssociationTwoStepRunner.resetCatalog();
      final db = await DatabaseHelper.instance.database;
      await db.delete('audit_log');
      await db.delete('tasks');
      await db.delete('calls');
    });

    Future<ProviderContainer> createContainer() =>
        AssociationTwoStepRunner.createContainer();

    bool hasCallOrigin(String? details, int callId) =>
        (details ?? '').contains(DirectorySupport.auditOriginSuffixFromCall(callId));

    bool hasTaskOrigin(String? details, int taskId) =>
        (details ?? '').contains(DirectorySupport.auditOriginSuffixFromTask(taskId));

    test(
      'submitCall με νέο καλούντα + νέο τηλέφωνο: παράγωγες εγγραφές «από κλήση #N»',
      () async {
        const phone = '2105554411';
        const caller = 'Νέος Καλών Audit';
        const dept = 'Τμήμα UI Origin';

        final container = await createContainer();
        addTearDown(container.dispose);

        final smart = container.read(callSmartEntityProvider.notifier);
        smart.updatePhone(phone);
        smart.checkContent(phoneText: phone);
        smart.updateCallerDisplayText(caller);
        smart.checkContent(callerText: caller);
        smart.updateDepartmentText(dept);
        smart.checkContent(departmentText: dept);

        expect(
          container.read(callSmartEntityProvider).needsNewCallerCreation,
          isTrue,
        );

        await smart.associateCurrentIfNeeded();
        expect(container.read(callSmartEntityProvider).selectedCaller?.id, isNotNull);

        final entry = container.read(callEntryProvider.notifier);
        entry.setNotes('Δοκιμή προέλευσης UI κλήσης');
        entry.setCategory(kTestCategoryName);

        final ok = await entry.submitCall();
        expect(ok, isTrue);

        final db = await DatabaseHelper.instance.database;
        final callId = (await db.query('calls', orderBy: 'id DESC', limit: 1))
            .single['id'] as int;

        final audits = await db.query('audit_log', orderBy: 'id ASC');
        expect(audits.length, greaterThan(1));

        final mainCall = audits.firstWhere(
          (r) => r['action'] == 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
        );
        expect(hasCallOrigin(mainCall['details'] as String?, callId), isFalse);

        final derivatives = audits.where(
          (r) => r['action'] != 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
        );
        expect(derivatives, isNotEmpty);
        for (final row in derivatives) {
          final action = row['action'];
          if (action == 'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ') continue;
          expect(
            hasCallOrigin(row['details'] as String?, callId),
            isTrue,
            reason: 'action=$action details=${row['details']}',
          );
        }
      },
    );

    test(
      'submitOnlyPending με νέο καλούντα: παράγωγες εγγραφές «από εκκρεμότητα #N»',
      () async {
        const phone = '2105554422';
        const caller = 'Quick Task Caller';
        const dept = 'Τμήμα Task Origin';

        final container = await createContainer();
        addTearDown(container.dispose);

        final smart = container.read(callSmartEntityProvider.notifier);
        smart.updatePhone(phone);
        smart.checkContent(phoneText: phone);
        smart.updateCallerDisplayText(caller);
        smart.checkContent(callerText: caller);
        smart.updateDepartmentText(dept);
        smart.checkContent(departmentText: dept);

        await smart.associateCurrentIfNeeded();

        final entry = container.read(callEntryProvider.notifier);
        entry.setNotes('Εκκρεμότητα με προέλευση UI');

        final ok = await entry.submitOnlyPending();
        expect(ok, isTrue);

        final db = await DatabaseHelper.instance.database;
        final taskId = (await db.query('tasks', orderBy: 'id DESC', limit: 1))
            .single['id'] as int;

        final audits = await db.query('audit_log', orderBy: 'id ASC');
        final mainTask = audits.firstWhere(
          (r) => r['action'] == 'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ',
        );
        expect(hasTaskOrigin(mainTask['details'] as String?, taskId), isFalse);

        final derivatives = audits.where(
          (r) => r['action'] != 'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ',
        );
        expect(derivatives, isNotEmpty);
        for (final row in derivatives) {
          if (row['action'] == 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ') continue;
          expect(
            hasTaskOrigin(row['details'] as String?, taskId),
            isTrue,
            reason: 'action=${row['action']} details=${row['details']}',
          );
        }
      },
    );
  });
}
