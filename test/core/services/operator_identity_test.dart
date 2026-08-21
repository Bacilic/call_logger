// Ποιος χρησιμοποιεί την εφαρμογή: αναγνώριση από τον λογαριασμό Windows και η
// σφραγίδα που αφήνει στο Ιστορικό.
//
//   flutter test test/core/services/operator_identity_test.dart

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/core/services/operator_identity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Αναγνώριση χρήστη από τον λογαριασμό Windows', () {
    late Database db;
    late OperatorRepository repository;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      repository = OperatorRepository(db);
      CurrentOperator.reset();
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    test('άγνωστος λογαριασμός ΔΕΝ δημιουργεί προφίλ σιωπηλά', () async {
      // Σε κοινόχρηστο λογαριασμό Windows η αυτόματη δημιουργία θα χρέωνε τις
      // ενέργειες όλων σε ένα πρόσωπο. Αποφασίζει ο άνθρωπος.
      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: 'VDrosos',
      );

      expect(resolved, isNull);
      expect(CurrentOperator.active, isNull);
      expect(await repository.count(), 0);
    });

    test('γνωστός λογαριασμός αναγνωρίζεται χωρίς ερώτηση', () async {
      final created = await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Βασίλης',
        bindCurrentAccount: true,
        windowsAccount: 'VDrosos',
        now: DateTime(2026, 8, 20),
      );
      CurrentOperator.reset();

      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: 'vdrosos',
      );

      expect(resolved!.id, created.id);
      expect(CurrentOperator.active?.id, created.id);
      expect(await repository.count(), 1);
    });

    test('η γραφή του λογαριασμού δεν φτιάχνει δεύτερο πρόσωπο', () async {
      // Τα Windows δεν ξεχωρίζουν πεζά από κεφαλαία στα ονόματα λογαριασμών.
      await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Βασίλης',
        bindCurrentAccount: true,
        windowsAccount: 'VDrosos',
        now: DateTime(2026, 8, 20),
      );

      expect(
        (await OperatorIdentity.resolveAndActivate(
          db,
          windowsAccount: 'ΝΟΣΟΚΟΜΕΙΟ\\VDROSOS',
        ))?.displayName,
        'Βασίλης',
      );
      expect(await repository.count(), 1);
    });

    test('χωρίς λογαριασμό δεν αναγνωρίζεται κανείς', () async {
      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: '   ',
      );

      expect(resolved, isNull);
      expect(CurrentOperator.active, isNull);
    });

    test('η αναγνώριση μηδενίζει πρώτα τον προηγούμενο χρήστη', () async {
      // Μετά από αλλαγή βάσης τα προφίλ είναι άλλα: ο χρήστης της προηγούμενης
      // δεν επιτρέπεται να μείνει ενεργός.
      await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Βασίλης',
        bindCurrentAccount: true,
        windowsAccount: 'vdrosos',
        now: DateTime(2026, 8, 20),
      );
      expect(CurrentOperator.active, isNotNull);

      await OperatorIdentity.resolveAndActivate(db, windowsAccount: '');

      expect(CurrentOperator.active, isNull);
    });
  });

  group('Δημιουργία προφίλ από την οθόνη επιλογής', () {
    late Database db;
    late OperatorRepository repository;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      repository = OperatorRepository(db);
      CurrentOperator.reset();
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    test('με δέσιμο: η επόμενη εκκίνηση δεν ξαναρωτά', () async {
      await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Βασίλης Δρόσος',
        bindCurrentAccount: true,
        windowsAccount: 'v.drosos',
        now: DateTime(2026, 8, 20),
      );
      CurrentOperator.reset();

      final resolved = await OperatorIdentity.resolveAndActivate(
        db,
        windowsAccount: 'v.drosos',
      );

      expect(resolved?.displayName, 'Βασίλης Δρόσος');
    });

    test('χωρίς δέσιμο: κοινόχρηστος υπολογιστής ξαναρωτά', () async {
      // Αλλιώς όλοι όσοι μοιράζονται τον λογαριασμό θα έμπαιναν ως ο πρώτος.
      await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Γραφείο ΤΕΠ',
        bindCurrentAccount: false,
        windowsAccount: 'koino',
        now: DateTime(2026, 8, 20),
      );
      CurrentOperator.reset();

      expect(
        await OperatorIdentity.resolveAndActivate(db, windowsAccount: 'koino'),
        isNull,
      );
      expect((await repository.getAll()).single.windowsAccount, isNull);
    });

    test('ο πρώτος που στήνει τη βάση σημειώνεται διαχειριστής', () async {
      final first = await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Πρώτος',
        bindCurrentAccount: false,
        now: DateTime(2026, 8, 20),
      );
      final second = await OperatorIdentity.createAndActivate(
        db,
        displayName: 'Δεύτερος',
        bindCurrentAccount: false,
        now: DateTime(2026, 8, 20),
      );

      expect(first.isAdmin, isTrue);
      expect(second.isAdmin, isFalse);
    });

    test('η λίστα επιλογής κρύβει τους αρχειοθετημένους', () async {
      await repository.insert(
        Operator(displayName: 'Ενεργός', createdAt: DateTime(2026, 8, 20)),
      );
      await repository.insert(
        Operator(
          displayName: 'Αρχειοθετημένος',
          isActive: false,
          createdAt: DateTime(2026, 8, 20),
        ),
      );

      final selectable = await OperatorIdentity.selectableProfiles(db);

      expect(selectable.map((o) => o.displayName), ['Ενεργός']);
    });

    test('ο ήδη συνδεδεμένος δεν προσφέρεται προς επιλογή', () async {
      final me = await repository.insert(
        Operator(displayName: 'Βασίλης', createdAt: DateTime(2026, 8, 21)),
      );
      await repository.insert(
        Operator(displayName: 'Δοκιμαστικός', createdAt: DateTime(2026, 8, 21)),
      );
      CurrentOperator.activate(me);

      final selectable = await OperatorIdentity.selectableProfiles(db);

      expect(
        selectable.map((o) => o.displayName),
        ['Δοκιμαστικός'],
        reason:
            '«Αλλαγή χρήστη» σε αυτόν που είναι ήδη ο χρήστης δεν κάνει τίποτα',
      );
    });

    test('στην εκκίνηση, χωρίς συνδεδεμένο, προσφέρονται όλοι', () async {
      await repository.insert(
        Operator(displayName: 'Βασίλης', createdAt: DateTime(2026, 8, 21)),
      );
      await repository.insert(
        Operator(displayName: 'Δοκιμαστικός', createdAt: DateTime(2026, 8, 21)),
      );

      final selectable = await OperatorIdentity.selectableProfiles(db);

      expect(selectable, hasLength(2));
    });
  });

  group('Η σφραγίδα του Ιστορικού', () {
    setUp(CurrentOperator.reset);
    tearDown(CurrentOperator.reset);

    test('χωρίς αναγνωρισμένο χρήστη γράφεται παύλα', () async {
      expect(await AuditService.performingUser(), '—');
    });

    test('με ενεργό χρήστη γράφεται το όνομά του', () async {
      activateTestOperator('Βασίλης Δρόσος');

      expect(await AuditService.performingUser(), 'Βασίλης Δρόσος');
    });

    test('κενό όνομα δεν αφήνει κενή σφραγίδα', () async {
      CurrentOperator.activate(
        Operator(displayName: '   ', createdAt: DateTime(2026, 1, 1)),
      );

      expect(await AuditService.performingUser(), '—');
    });
  });
}
