// Οι προτιμήσεις προβολής του Καταλόγου ανήκουν στον κάθε χρήστη, όχι
// στο μηχάνημα και όχι στην κοινή βάση.
//
// Το συμβόλαιο: κλειδί δηλωμένο ως προσωπικό διαβάζεται και γράφεται ΜΟΝΟ
// από την πύλη των προσωπικών ρυθμίσεων. Όσο οι Κατηγορίες, τα Τμήματα και οι
// διακόπτες «συνεχής κύλιση» έγραφαν κατευθείαν στα κοινά, κρύβοντας μια στήλη
// στο σπίτι έκρυβε και την οθόνη του συναδέλφου.
//
//   flutter test test/features/directory/catalog_preferences_are_personal_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/operator_settings_repository.dart';
import 'package:call_logger/core/database/settings_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/settings_service.dart';
import 'package:call_logger/features/calls/provider/lookup_provider.dart';
import 'package:call_logger/features/directory/providers/catalog_continuous_scroll_provider.dart';
import 'package:call_logger/features/directory/providers/category_directory_provider.dart';
import 'package:call_logger/features/directory/providers/department_directory_provider.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../test_setup.dart';

Operator _operator(int id) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  createdAt: DateTime(2026, 9, 17),
);

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  late Database db;

  setUp(() async {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    CurrentOperator.reset();
    db = await DatabaseHelper.instance.database;
    await db.delete('app_settings');
    await db.delete(OperatorSettingsRepository.tableName);
    SettingsService.registerAppSettingsProvider(
      (key) => SettingsRepository(db).getSetting(key),
      (key, value) => SettingsRepository(db).saveSetting(key, value),
      (key, change) async =>
          change(await SettingsRepository(db).getSetting(key)),
    );
  });

  tearDown(CurrentOperator.reset);

  Future<ProviderContainer> container() async {
    final c = ProviderContainer(overrides: callLoggerTestProviderOverrides());
    addTearDown(c.dispose);
    await c.read(lookupServiceProvider.future);
    return c;
  }

  test('οι στήλες των Τμημάτων δεν ταξιδεύουν στον επόμενο χρήστη', () async {
    final c = await container();
    final notifier = c.read(departmentDirectoryProvider.notifier);
    await notifier.loadDepartments();

    CurrentOperator.activate(_operator(1));
    await notifier.reloadColumnLayoutForCurrentOperator();
    final hidden = c.read(departmentDirectoryProvider).columnOrder.last;
    await notifier.setDepartmentColumnVisible(hidden, false);
    expect(
      c.read(departmentDirectoryProvider).visibleColumnKeys,
      isNot(contains(hidden.key)),
      reason: 'Προϋπόθεση: ο πρώτος έκρυψε τη στήλη.',
    );

    CurrentOperator.activate(_operator(2));
    await notifier.reloadColumnLayoutForCurrentOperator();

    expect(
      c.read(departmentDirectoryProvider).visibleColumnKeys,
      contains(hidden.key),
      reason: 'Ο δεύτερος δεν έκρυψε τίποτα — βλέπει τις προεπιλογές.',
    );
  });

  test('οι στήλες των Κατηγοριών δεν ταξιδεύουν στον επόμενο χρήστη', () async {
    final c = await container();
    final notifier = c.read(categoryDirectoryProvider.notifier);
    await notifier.loadCategories();

    CurrentOperator.activate(_operator(1));
    await notifier.reloadColumnLayoutForCurrentOperator();
    final shown = c
        .read(categoryDirectoryProvider)
        .columnOrder
        .firstWhere(
          (col) => !c
              .read(categoryDirectoryProvider)
              .visibleColumnKeys
              .contains(col.key),
        );
    await notifier.setCategoryColumnVisible(shown, true);
    expect(
      c.read(categoryDirectoryProvider).visibleColumnKeys,
      contains(shown.key),
      reason: 'Προϋπόθεση: ο πρώτος εμφάνισε τη στήλη.',
    );

    CurrentOperator.activate(_operator(2));
    await notifier.reloadColumnLayoutForCurrentOperator();

    expect(
      c.read(categoryDirectoryProvider).visibleColumnKeys,
      isNot(contains(shown.key)),
      reason: 'Ο δεύτερος ξεκινά από τις προεπιλογές.',
    );
  });

  test('η συνεχής κύλιση ανήκει στον κάθε χρήστη ξεχωριστά', () async {
    final c = await container();

    CurrentOperator.activate(_operator(1));
    await c.read(catalogDepartmentsContinuousScrollProvider.future);
    await c
        .read(catalogDepartmentsContinuousScrollProvider.notifier)
        .setEnabled(false);

    CurrentOperator.activate(_operator(2));
    c.invalidate(catalogDepartmentsContinuousScrollProvider);

    expect(
      await c.read(catalogDepartmentsContinuousScrollProvider.future),
      isTrue,
      reason:
          'Ο δεύτερος δεν έκλεισε τη συνεχή κύλιση — η επιλογή του πρώτου '
          'δεν τον αφορά.',
    );

    CurrentOperator.activate(_operator(1));
    c.invalidate(catalogDepartmentsContinuousScrollProvider);
    expect(
      await c.read(catalogDepartmentsContinuousScrollProvider.future),
      isFalse,
      reason: 'Η επιλογή του πρώτου τον ακολουθεί.',
    );
  });

  test('κάθε καρτέλα έχει δικό της διακόπτη κύλισης', () async {
    final c = await container();
    CurrentOperator.activate(_operator(1));

    await c.read(catalogUsersContinuousScrollProvider.future);
    await c
        .read(catalogUsersContinuousScrollProvider.notifier)
        .setEnabled(false);

    expect(
      await c.read(catalogEquipmentContinuousScrollProvider.future),
      isTrue,
      reason: 'Ο διακόπτης των Υπαλλήλων δεν αγγίζει τον Εξοπλισμό.',
    );
  });
}
