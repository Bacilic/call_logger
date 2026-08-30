// Ο έλεγχος «έχει αυτή η βάση διαχειριστή;» στο άνοιγμα.
//
//   flutter test test/features/operators/admin_presence_gate_test.dart

import 'package:call_logger/core/database/database_schema_migrations.dart';
import 'package:call_logger/core/database/database_v1_schema.dart';
import 'package:call_logger/core/database/operator_repository.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/core/services/current_operator.dart';
import 'package:call_logger/features/operators/services/admin_presence_gate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

Operator _operator(
  String name, {
  bool isAdmin = false,
  bool isActive = true,
  int? id,
}) => Operator(
  id: id,
  displayName: name,
  isAdmin: isAdmin,
  isActive: isActive,
  createdAt: DateTime(2026, 8, 26),
);

void main() {
  group('Η κρίση, χωρίς βάση', () {
    test('άδεια βάση δεν χρειάζεται τίποτα', () {
      // Εκεί ο πρώτος που θα συστηθεί γίνεται διαχειριστής της, όπως πάντα.
      expect(
        AdminPresenceGate.evaluate(const <Operator>[]).needsSetup,
        isFalse,
      );
    });

    test('με ενεργό διαχειριστή δεν ρωτιέται τίποτα', () {
      final state = AdminPresenceGate.evaluate([
        _operator('Βαρβάρα', isAdmin: true),
        _operator('Παναγιώτης'),
      ]);

      expect(state.needsSetup, isFalse);
    });

    test('ενεργά προφίλ χωρίς διαχειριστή ζητούν ορισμό', () {
      final state = AdminPresenceGate.evaluate([
        _operator('Βαρβάρα'),
        _operator('Παναγιώτης'),
      ]);

      expect(state.needsSetup, isTrue);
      expect(state.candidates.map((o) => o.displayName), [
        'Βαρβάρα',
        'Παναγιώτης',
      ]);
    });

    test('ο απενεργοποιημένος διαχειριστής δεν μετράει', () {
      // Δεν προσφέρεται πουθενά προς επιλογή, άρα δεν ξεκλειδώνει τίποτα.
      final state = AdminPresenceGate.evaluate([
        _operator('Παναγιώτης', isAdmin: true, isActive: false),
        _operator('Βαρβάρα'),
      ]);

      expect(state.needsSetup, isTrue);
      expect(state.candidates.map((o) => o.displayName), ['Βαρβάρα']);
    });

    test('βάση με μόνο απενεργοποιημένα δεν έχει ποιον να ρωτήσει', () {
      final state = AdminPresenceGate.evaluate([
        _operator('Παναγιώτης', isActive: false),
      ]);

      expect(state.needsSetup, isFalse);
    });
  });

  group('Ο ορισμός στη βάση', () {
    late Database db;
    late OperatorRepository repository;

    setUp(() async {
      initSqfliteFfiForTests();
      db = await openDatabase(inMemoryDatabasePath, singleInstance: false);
      await onDatabaseUpgradeSquashed(db, 46, 47);
      await db.execute(kCreateAuditLogTable);
      repository = OperatorRepository(db);
      CurrentOperator.reset();
    });

    tearDown(() async {
      CurrentOperator.reset();
      await db.close();
    });

    test('η βάση χωρίς διαχειριστή ζητά ορισμό και τον δέχεται', () async {
      final varvara = await repository.insert(_operator('Βαρβάρα'));
      await repository.insert(_operator('Παναγιώτης'));

      final before = await AdminPresenceGate.read(db);
      expect(before.needsSetup, isTrue);

      final result = await AdminPresenceGate.promote(db, varvara);

      expect(result.allowed, isTrue);
      expect((await repository.findById(varvara.id!))!.isAdmin, isTrue);
      expect((await AdminPresenceGate.read(db)).needsSetup, isFalse);
    });

    test('ο ορισμός γράφεται στο Ιστορικό', () async {
      final varvara = await repository.insert(_operator('Βαρβάρα'));

      await AdminPresenceGate.promote(db, varvara);

      final entries = await db.query('audit_log');
      expect(entries, isNotEmpty);
    });

    test('προφίλ που δεν υπάρχει πια δεν ορίζεται', () async {
      // Η λίστα της οθόνης διαβάστηκε πριν από λίγο· στο μεταξύ ο συνάδελφος
      // μπορεί να έχει πειράξει τη βάση.
      final ghost = _operator('Φάντασμα', id: 999);

      final result = await AdminPresenceGate.promote(db, ghost);

      expect(result.allowed, isFalse);
    });
  });
}
