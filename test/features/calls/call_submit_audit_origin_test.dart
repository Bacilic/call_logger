import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/database/directory_support.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/features/calls/provider/call_entry_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/tasks/providers/task_service_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../helpers/association_two_step_runner.dart';
import '../../test_setup.dart';

/// Η εγγραφή της γρήγορης εκκρεμότητας αποτυγχάνει — όλα τα άλλα δουλεύουν.
class _QuickTaskWriteFails extends TasksRepository {
  @override
  Future<int> createFromCall({
    int? callId,
    required String? callerName,
    required String description,
    required DateTime callDate,
    int? callerId,
    int? equipmentId,
    int? departmentId,
    int? phoneId,
    String? phoneText,
    String? userText,
    String? equipmentText,
    String? departmentText,
    String? categoryName,
    DateTime? titleTimestamp,
    int? priority,
    String? origin,
  }) => Future.error(StateError('η βάση απέρριψε την εκκρεμότητα'));
}

/// Καλωδίωση Φάσης 3: προέλευση audit από πραγματικές ροές UI (associate + submit).
///
/// Και η αποτυχία της γρήγορης εκκρεμότητας: υπενθύμιση, ποτέ εμπόδιο — ούτε
/// το μήνυμα του «+» ούτε το ίχνος στο Ιστορικό χάνονται εξαιτίας της.
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

    Future<ProviderContainer> createContainerWhereQuickTaskFails() =>
        AssociationTwoStepRunner.createContainer(
          overrides: [
            taskServiceProvider.overrideWithValue(_QuickTaskWriteFails()),
          ],
        );

    bool hasCallOrigin(String? details, int callId) => (details ?? '').contains(
      DirectorySupport.auditOriginSuffixFromCall(callId),
    );

    bool hasTaskOrigin(String? details, int taskId) => (details ?? '').contains(
      DirectorySupport.auditOriginSuffixFromTask(taskId),
    );

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
        expect(
          container.read(callSmartEntityProvider).selectedCaller?.id,
          isNotNull,
        );

        final entry = container.read(callEntryProvider.notifier);
        entry.setNotes('Δοκιμή προέλευσης UI κλήσης');
        entry.setCategory(kTestCategoryName);

        final ok = await entry.submitCall();
        expect(ok, isTrue);

        final db = await DatabaseHelper.instance.database;
        final callId =
            (await db.query('calls', orderBy: 'id DESC', limit: 1)).single['id']
                as int;

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
        final taskId =
            (await db.query('tasks', orderBy: 'id DESC', limit: 1)).single['id']
                as int;

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

    /// Καταχωρεί κλήση και επιστρέφει τις παράγωγες εγγραφές Ιστορικού που
    /// ΔΕΝ πήραν «από κλήση #N» — άδεια λίστα σημαίνει ότι το «+» τις κράτησε.
    Future<List<Map<String, Object?>>> derivativesMissingCallOrigin(
      ProviderContainer container,
    ) async {
      final entry = container.read(callEntryProvider.notifier);
      entry.setNotes('Κλήση μετά από «+» με αποτυχημένη εκκρεμότητα');
      entry.setCategory(kTestCategoryName);
      expect(await entry.submitCall(), isTrue);

      final db = await DatabaseHelper.instance.database;
      final callId =
          (await db.query('calls', orderBy: 'id DESC', limit: 1)).single['id']
              as int;
      final derivatives = (await db.query(
        'audit_log',
        orderBy: 'id ASC',
      )).where((r) => r['action'] != 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ').toList();
      expect(derivatives, isNotEmpty);
      return derivatives
          .where((r) => !hasCallOrigin(r['details'] as String?, callId))
          .toList();
    }

    test(
      'νέος καλών: η αποτυχία της γρήγορης εκκρεμότητας δεν διαψεύδει την καταχώρηση',
      () async {
        final container = await createContainerWhereQuickTaskFails();
        addTearDown(container.dispose);

        final smart = container.read(callSmartEntityProvider.notifier);
        smart.updatePhone('2105554433');
        smart.checkContent(phoneText: '2105554433');
        smart.updateCallerDisplayText('Καλών Χωρίς Εκκρεμότητα');
        smart.checkContent(callerText: 'Καλών Χωρίς Εκκρεμότητα');
        smart.updateDepartmentText('Τμήμα Χωρίς Εκκρεμότητα');
        smart.checkContent(departmentText: 'Τμήμα Χωρίς Εκκρεμότητα');

        final message = await smart.associateCurrentIfNeeded();

        expect(message, startsWith('Δημιουργήθηκε νέος χρήστης'));
        expect(
          container.read(callSmartEntityProvider).selectedCaller?.id,
          isNotNull,
        );
        expect(await derivativesMissingCallOrigin(container), isEmpty);
      },
    );

    test(
      'υπάρχων καλών: η αποτυχία της γρήγορης εκκρεμότητας δεν διαψεύδει την καταχώρηση',
      () async {
        final db = await DatabaseHelper.instance.database;
        final departmentId = await DepartmentRepository(
          db,
        ).getOrCreateDepartmentIdByName('Τμήμα Γνωστού');
        await UserRepository(db).insertUser(
          firstName: 'Γνωστός',
          lastName: 'Καλών',
          phones: const ['2105554444'],
          departmentId: departmentId,
        );
        await db.delete('audit_log');

        final container = await createContainerWhereQuickTaskFails();
        addTearDown(container.dispose);

        final smart = container.read(callSmartEntityProvider.notifier);
        smart.updatePhone('2105554444');
        smart.performPhoneLookup('2105554444');
        smart.updateEquipmentText('PC-ΝΕΟ-Δ');
        smart.checkContent(equipmentText: 'PC-ΝΕΟ-Δ');

        final message = await smart.associateCurrentIfNeeded();

        expect(message, startsWith('Προσθήκη εξοπλισμού: PC-ΝΕΟ-Δ'));
        expect(await derivativesMissingCallOrigin(container), isEmpty);
      },
    );

    test(
      'κοινόχρηστα τμήματος: η αποτυχία της γρήγορης εκκρεμότητας δεν διαψεύδει την καταχώρηση',
      () async {
        final container = await createContainerWhereQuickTaskFails();
        addTearDown(container.dispose);

        final smart = container.read(callSmartEntityProvider.notifier);
        smart.updatePhone('8883');
        smart.checkContent(phoneText: '8883');
        smart.updateDepartmentText('Τμήμα Κοινόχρηστου');
        smart.checkContent(departmentText: 'Τμήμα Κοινόχρηστου');

        final result = await smart.quickAddOrphanToDepartment(
          forceSharedOnConflict: true,
        );

        expect(result?.successMessage, isNotNull);
      },
    );
  });
}
