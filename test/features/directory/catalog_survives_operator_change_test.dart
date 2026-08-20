// Η «Αλλαγή χρήστη» ανανεώνει ΠΡΟΤΙΜΗΣΕΙΣ ΠΡΟΒΟΛΗΣ — ποτέ δεδομένα.
//
// Ο Κατάλογος ξεκινά από κενή κατάσταση και γεμίζει μόνο όταν ανοίγει η
// καρτέλα. Σκέτο `invalidate` στην αλλαγή χρήστη άδειαζε τον πίνακα μπροστά
// στα μάτια του χρήστη — η βάση όμως δεν άλλαξε (αναφορά 20/08/2026).
//
//   flutter test test/features/directory/catalog_survives_operator_change_test.dart

import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/providers/equipment_directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Operator _operator(int id) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  createdAt: DateTime(2026, 8, 20),
);

Future<ProviderContainer> _container() async {
  final container = ProviderContainer(
    overrides: callLoggerTestProviderOverrides(),
  );
  addTearDown(container.dispose);
  await container.read(lookupServiceProvider.future);
  return container;
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUp(CurrentOperator.reset);
  tearDown(CurrentOperator.reset);

  test('οι Υπάλληλοι δεν χάνονται στην αλλαγή χρήστη', () async {
    final container = await _container();
    final notifier = container.read(directoryProvider.notifier);

    await notifier.loadUsers();
    final loaded = container.read(directoryProvider).allUsers.length;
    expect(
      loaded,
      greaterThan(0),
      reason: 'Προϋπόθεση: ο κατάλογος έχει εγγραφές.',
    );

    // Αλλαγή χρήστη: ξαναδιαβάζονται οι στήλες του νέου.
    CurrentOperator.activate(_operator(2));
    await notifier.reloadColumnLayoutForCurrentOperator();

    expect(
      container.read(directoryProvider).allUsers.length,
      loaded,
      reason: 'Η βάση δεν άλλαξε — οι εγγραφές δεν επιτρέπεται να χαθούν.',
    );
    expect(
      container.read(directoryProvider).filteredUsers.length,
      greaterThan(0),
      reason: 'Ο πίνακας πρέπει να παραμείνει ορατός, όχι άδειος.',
    );
  });

  test('ο Εξοπλισμός δεν χάνεται στην αλλαγή χρήστη', () async {
    final container = await _container();
    final notifier = container.read(equipmentDirectoryProvider.notifier);

    await notifier.load();
    final loaded = container.read(equipmentDirectoryProvider).allItems.length;
    expect(loaded, greaterThan(0), reason: 'Προϋπόθεση: υπάρχει εξοπλισμός.');

    CurrentOperator.activate(_operator(2));
    await notifier.reloadColumnLayoutForCurrentOperator();

    expect(
      container.read(equipmentDirectoryProvider).allItems.length,
      loaded,
      reason: 'Η βάση δεν άλλαξε — ο εξοπλισμός δεν επιτρέπεται να χαθεί.',
    );
  });

  test(
    'χωρίς δικές του στήλες, ο νέος χρήστης παίρνει τις προεπιλογές',
    () async {
      final container = await _container();
      final notifier = container.read(directoryProvider.notifier);
      await notifier.loadUsers();

      // Ο πρώτος χρήστης κρύβει μια στήλη.
      CurrentOperator.activate(_operator(1));
      final all = container.read(directoryProvider).columnOrder;
      final hiddenColumn = all.last;
      await notifier.setUserColumnVisible(hiddenColumn, false);
      expect(
        container.read(directoryProvider).visibleColumnKeys,
        isNot(contains(hiddenColumn.key)),
      );

      // Ο δεύτερος δεν έχει δικές του: πρέπει να δει ΠΡΟΕΠΙΛΟΓΕΣ, όχι τις
      // κρυμμένες στήλες του πρώτου.
      CurrentOperator.activate(_operator(2));
      await notifier.reloadColumnLayoutForCurrentOperator();

      expect(
        container.read(directoryProvider).visibleColumnKeys,
        contains(hiddenColumn.key),
        reason:
            'Οι επιλογές του προηγούμενου δεν επιτρέπεται να διαρρεύσουν στον '
            'επόμενο.',
      );
    },
  );
}
