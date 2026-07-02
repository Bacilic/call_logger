// Έλεγχος: μετά από directory mutations από smart entity selector, οι sibling
// κατάλογοι ανανεώνονται χωρίς χειροκίνητο reload.
//
//   flutter test test/features/calls/smart_entity_directory_refresh_test.dart

import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/calls/provider/smart_entity_selector_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../helpers/association_two_step_runner.dart';
import '../../test_setup.dart';

Future<ProviderContainer> _containerWithFreshCatalog() async {
  await AssociationTwoStepRunner.resetCatalog();
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  await container.read(lookupServiceProvider.future);
  return container;
}

Future<void> _preloadSiblingCatalogs(ProviderContainer container) async {
  await container.read(directoryProvider.notifier).loadUsers();
  await container.read(equipmentDirectoryProvider.notifier).load();
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('Smart entity — refreshDirectoryCaches sibling catalogs', () {
    test(
      'associateCurrentIfNeeded προσθέτει νέο χρήστη και εξοπλισμό στον κατάλογο',
      () async {
        final container = await _containerWithFreshCatalog();
        await _preloadSiblingCatalogs(container);

        final usersBefore = container.read(directoryProvider).allUsers.length;
        final equipmentBefore =
            container.read(equipmentDirectoryProvider).allItems.length;

        const callerName = 'Νέος Κατάλογος';
        const phone = '208881';
        const equipmentCode = 'NEW-EQ-881';

        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.updateCallerDisplayText(callerName);
        notifier.checkContent(callerText: callerName);
        notifier.updatePhone(phone);
        notifier.checkContent(phoneText: phone);
        notifier.checkContent(equipmentText: equipmentCode);

        expect(
          container.read(callSmartEntityProvider).needsNewCallerCreation,
          isTrue,
        );

        final message = await notifier.associateCurrentIfNeeded();
        expect(message, isNotNull);
        expect(message!.contains('Σφάλμα'), isFalse);

        final usersAfter = container.read(directoryProvider).allUsers;
        expect(usersAfter.length, greaterThan(usersBefore));
        expect(
          usersAfter.any(
            (u) =>
                (u.name ?? '').contains('Νέος') &&
                (u.name ?? '').contains('Κατάλογος'),
          ),
          isTrue,
          reason:
              'directoryProvider πρέπει να περιέχει τον νέο χρήστη χωρίς loadUsers()',
        );

        final equipmentAfter =
            container.read(equipmentDirectoryProvider).allItems;
        expect(equipmentAfter.length, greaterThan(equipmentBefore));
        expect(
          equipmentAfter.any((row) => (row.$1.code ?? '').trim() == equipmentCode),
          isTrue,
          reason:
              'equipmentDirectoryProvider πρέπει να περιέχει τον νέο εξοπλισμό χωρίς load()',
        );

        container.dispose();
      },
    );

    test(
      'quickAddOrphanToDepartment προσθέτει κοινόχρηστο τηλέφωνο στον κατάλογο χρηστών',
      () async {
        final container = await _containerWithFreshCatalog();
        await _preloadSiblingCatalogs(container);

        const orphanPhone = '7771';
        const deptName = 'Τμήμα Κοινόχρηστου Τηλεφώνου';

        final phonesBefore =
            container.read(directoryProvider).allNonUserPhones.length;

        final notifier = container.read(callSmartEntityProvider.notifier);
        notifier.updatePhone(orphanPhone);
        notifier.checkContent(phoneText: orphanPhone);
        notifier.updateDepartmentText(deptName);
        notifier.checkContent(departmentText: deptName);

        expect(
          container.read(callSmartEntityProvider).needsOrphanDepartmentQuickAdd,
          isTrue,
        );

        final result = await notifier.quickAddOrphanToDepartment(
          forceSharedOnConflict: true,
        );
        expect(result, isNotNull);
        expect(result!.requiresConfirmation, isFalse);
        expect(result.successMessage, isNotNull);

        final phonesAfter = container.read(directoryProvider).allNonUserPhones;
        expect(phonesAfter.length, greaterThan(phonesBefore));
        expect(
          phonesAfter.any((p) => p.number.contains(orphanPhone)),
          isTrue,
          reason:
              'directoryProvider.allNonUserPhones πρέπει να περιέχει το κοινόχρηστο τηλέφωνο χωρίς loadUsers()',
        );

        container.dispose();
      },
    );
  });
}
