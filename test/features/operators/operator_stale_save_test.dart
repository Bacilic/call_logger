// Δύο διαχειριστές, η ίδια καρτέλα χρήστη: ο δεύτερος που σώζει δεν
// επιτρέπεται να σβήσει σιωπηλά τα δικαιώματα που έδωσε ο πρώτος.
//
//   flutter test test/features/operators/operator_stale_save_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/app_permission.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/operators/services/operator_management.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Προφίλ — φρουρός μπαγιάτικης αποθήκευσης', () {
    late Database db;
    late OperatorRepository repository;
    late OperatorManagement management;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      await db.execute(kCreateAuditLogTable);
      repository = OperatorRepository(db);
      management = OperatorManagement(repository);
      CurrentOperator.reset();
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    /// Στήνει το σενάριο: η καρτέλα του Βλάση είναι ανοιχτή σε δύο οθόνες, και
    /// ο πρώτος διαχειριστής προλαβαίνει να του δώσει δικαίωμα και σήμανση.
    Future<({Operator stale, Operator afterOther})> openTwiceThenOtherSaves() async {
      await management.create(
        displayName: 'Διαχειριστής',
        windowsAccount: 'admin.account',
        isAdmin: true,
      );
      final created = await management.create(displayName: 'Βλάσης');
      final vlasis = created.operator!;

      // Η εικόνα που κρατά η ΔΕΥΤΕΡΗ οθόνη — φορτώθηκε πριν από όλα.
      final stale = (await repository.findById(vlasis.id!))!;

      // Ο πρώτος διαχειριστής σώζει από τη δική του οθόνη.
      final first = await management.save(
        stale,
        displayName: 'Βλάσης',
        windowsAccount: null,
        isAdmin: true,
        isActive: true,
        permissionOverrides: {AppPermission.browseDatabase.key: false},
      );
      expect(first.allowed, isTrue);

      final afterOther = (await repository.findById(vlasis.id!))!;
      expect(afterOther.isAdmin, isTrue);
      expect(afterOther.permissionOverrides, isNotEmpty);
      return (stale: stale, afterOther: afterOther);
    }

    test('η δεύτερη αποθήκευση δεν σβήνει δικαίωμα και σήμανση', () async {
      final scenario = await openTwiceThenOtherSaves();

      // Η δεύτερη οθόνη αλλάζει μόνο το όνομα — με τη ΜΠΑΓΙΑΤΙΚΗ εικόνα.
      final result = await management.save(
        scenario.stale,
        displayName: 'Βλάσης Δ.',
        windowsAccount: null,
        isAdmin: scenario.stale.isAdmin,
        isActive: scenario.stale.isActive,
        permissionOverrides: scenario.stale.permissionOverrides,
      );

      expect(
        result.allowed,
        isFalse,
        reason: 'Η αποθήκευση πάνω σε αλλαγμένη καρτέλα πρέπει να σταματά',
      );
      expect(result.conflict, isNotNull);

      final stored = (await repository.findById(scenario.stale.id!))!;
      expect(
        stored.isAdmin,
        isTrue,
        reason: 'Η σήμανση διαχειριστή του πρώτου πρέπει να έχει μείνει',
      );
      expect(
        stored.permissionOverrides,
        {AppPermission.browseDatabase.key: false},
        reason: 'Το δικαίωμα που έδωσε ο πρώτος πρέπει να έχει μείνει',
      );
      expect(stored.displayName, 'Βλάσης');
    });

    test('η διένεξη λέει τι άλλαξε ο άλλος', () async {
      final scenario = await openTwiceThenOtherSaves();

      final result = await management.save(
        scenario.stale,
        displayName: 'Βλάσης Δ.',
        windowsAccount: null,
        isAdmin: false,
        isActive: true,
        permissionOverrides: const <String, bool>{},
      );

      final conflict = result.conflict!;
      expect(conflict.fresh.isAdmin, isTrue);
      expect(conflict.attempted.displayName, 'Βλάσης Δ.');
      expect(
        conflict.changedFields,
        contains('δικαιώματα'),
        reason: 'Ο χρήστης πρέπει να δει ότι πειράχτηκαν τα δικαιώματα',
      );
      expect(conflict.changedFields, contains('σήμανση διαχειριστή'));
    });

    test('με force ο διαχειριστής γράφει εν γνώσει του', () async {
      final scenario = await openTwiceThenOtherSaves();

      final result = await management.save(
        scenario.stale,
        displayName: 'Βλάσης Δ.',
        windowsAccount: null,
        isAdmin: scenario.stale.isAdmin,
        isActive: scenario.stale.isActive,
        permissionOverrides: scenario.stale.permissionOverrides,
        force: true,
      );

      expect(result.allowed, isTrue);
      final stored = (await repository.findById(scenario.stale.id!))!;
      expect(stored.displayName, 'Βλάσης Δ.');
      expect(stored.isAdmin, isFalse);
    });

    test('χωρίς ξένη αλλαγή η αποθήκευση περνά κανονικά', () async {
      await management.create(
        displayName: 'Διαχειριστής',
        windowsAccount: 'admin.account',
        isAdmin: true,
      );
      final created = await management.create(displayName: 'Βλάσης');
      final vlasis = (await repository.findById(created.operator!.id!))!;

      final result = await management.save(
        vlasis,
        displayName: 'Βλάσης Δ.',
        windowsAccount: null,
        isAdmin: false,
        isActive: true,
        permissionOverrides: const <String, bool>{},
      );

      expect(result.allowed, isTrue);
      expect(result.conflict, isNull);
      expect(
        (await repository.findById(vlasis.id!))!.displayName,
        'Βλάσης Δ.',
      );
    });

    test('ο έλεγχος τελευταίου διαχειριστή κρίνει με τη ΒΑΣΗ, όχι με την οθόνη', () async {
      // Ο μοναδικός διαχειριστής προάγει τον Βλάση από άλλη οθόνη· η μπαγιάτικη
      // καρτέλα δεν το ξέρει και πάει να του αφαιρέσει τη σήμανση που δεν
      // «βλέπει» — χωρίς φρουρό, το προφίλ έχανε τη σήμανση αμίλητα.
      final scenario = await openTwiceThenOtherSaves();

      final result = await management.save(
        scenario.stale,
        displayName: 'Βλάσης',
        windowsAccount: null,
        isAdmin: false,
        isActive: true,
        permissionOverrides: const <String, bool>{},
      );

      expect(result.allowed, isFalse);
      expect(
        (await repository.findById(scenario.stale.id!))!.isAdmin,
        isTrue,
      );
    });
  });
}
