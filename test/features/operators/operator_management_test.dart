// Οι κανόνες της διαχείρισης χρηστών: τι επιτρέπεται, τι μπλοκάρεται και γιατί.
//
//   flutter test test/features/operators/operator_management_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/operators/services/operator_management.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Διαχείριση χρηστών εφαρμογής', () {
    late Database db;
    late OperatorRepository repository;
    late OperatorManagement management;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      repository = OperatorRepository(db);
      management = OperatorManagement(repository);
      CurrentOperator.reset();
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    Future<Operator> seedAdmin({String name = 'Διαχειριστής'}) async {
      final result = await management.create(
        displayName: name,
        windowsAccount: 'admin.account',
        isAdmin: true,
        now: DateTime(2026, 8, 19),
      );
      return result.operator!;
    }

    test('δημιουργία αυτόνομου προφίλ χωρίς λογαριασμό Windows', () async {
      final result = await management.create(
        displayName: 'Γραφείο ΤΕΠ',
        now: DateTime(2026, 8, 19),
      );

      expect(result.allowed, isTrue);
      expect(result.operator!.windowsAccount, isNull);
      expect(await repository.count(), 1);
    });

    test('κενό όνομα δεν γίνεται δεκτό', () async {
      final result = await management.create(displayName: '   ');

      expect(result.allowed, isFalse);
      expect(result.message, contains('Ιστορικό'));
      expect(await repository.count(), 0);
    });

    test('δύο χρήστες δεν μοιράζονται όνομα', () async {
      await management.create(
        displayName: 'Μαρία Π.',
        now: DateTime(2026, 8, 19),
      );

      final duplicate = await management.create(displayName: 'μαρία π.');

      expect(duplicate.allowed, isFalse);
      expect(duplicate.message, contains('Υπάρχει ήδη'));
      expect(await repository.count(), 1);
    });

    test('ο λογαριασμός Windows ανήκει σε έναν και λέγεται σε ποιον', () async {
      await seedAdmin(name: 'Βασίλης');

      final clash = await management.create(
        displayName: 'Άλλος',
        windowsAccount: 'ADMIN.ACCOUNT',
      );

      expect(clash.allowed, isFalse);
      expect(clash.message, contains('Βασίλης'));
    });

    test('ο τελευταίος διαχειριστής δεν χάνει τη σήμανση', () async {
      final admin = await seedAdmin();

      final result = await management.save(
        admin,
        displayName: admin.displayName,
        windowsAccount: admin.windowsAccount,
        isAdmin: false,
        isActive: true,
      );

      expect(result.allowed, isFalse);
      expect(result.message, contains('τουλάχιστον ένας διαχειριστής'));
      expect((await repository.findById(admin.id!))!.isAdmin, isTrue);
    });

    test('ο μοναδικός διαχειριστής δεν αρχειοθετείται', () async {
      final admin = await seedAdmin();

      final result = await management.save(
        admin,
        displayName: admin.displayName,
        windowsAccount: admin.windowsAccount,
        isAdmin: true,
        isActive: false,
      );

      expect(result.allowed, isFalse);
      expect((await repository.findById(admin.id!))!.isActive, isTrue);
    });

    test('με δεύτερο διαχειριστή η σήμανση αφαιρείται κανονικά', () async {
      final first = await seedAdmin(name: 'Πρώτος');
      await management.create(
        displayName: 'Δεύτερος',
        windowsAccount: 'second.account',
        isAdmin: true,
        now: DateTime(2026, 8, 19),
      );

      final result = await management.save(
        first,
        displayName: first.displayName,
        windowsAccount: first.windowsAccount,
        isAdmin: false,
        isActive: true,
      );

      expect(result.allowed, isTrue);
      expect((await repository.findById(first.id!))!.isAdmin, isFalse);
    });

    test('η αποσύνδεση λογαριασμού κάνει το προφίλ αυτόνομο', () async {
      final admin = await seedAdmin();

      final result = await management.save(
        admin,
        displayName: admin.displayName,
        windowsAccount: '',
        isAdmin: true,
        isActive: true,
      );

      expect(result.allowed, isTrue);
      expect((await repository.findById(admin.id!))!.windowsAccount, isNull);
    });

    test('μετονομασία του δικού μου προφίλ αλλάζει αμέσως τη σφραγίδα', () async {
      // Αλλιώς το Ιστορικό θα κρατούσε το παλιό όνομα ως την επόμενη εκκίνηση.
      final me = await seedAdmin(name: 'v.drosos');
      CurrentOperator.activate(me);

      await management.save(
        me,
        displayName: 'Βασίλης Δρόσος',
        windowsAccount: me.windowsAccount,
        isAdmin: true,
        isActive: true,
      );

      expect(CurrentOperator.auditName, 'Βασίλης Δρόσος');
    });

    test('μετονομασία ΑΛΛΟΥ προφίλ δεν αγγίζει τη δική μου ταυτότητα', () async {
      final me = await seedAdmin(name: 'Εγώ');
      CurrentOperator.activate(me);
      final other = (await management.create(
        displayName: 'Άλλος',
        windowsAccount: 'other.account',
        now: DateTime(2026, 8, 19),
      )).operator!;

      await management.save(
        other,
        displayName: 'Άλλος Μετονομασμένος',
        windowsAccount: other.windowsAccount,
        isAdmin: false,
        isActive: true,
      );

      expect(CurrentOperator.auditName, 'Εγώ');
    });
  });
}
