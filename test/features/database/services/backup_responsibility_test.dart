// «Είμαι ο πρώτος διαθέσιμος;» (Φάση 4): ο εφεδρικός παραχωρεί το αντίγραφο
// σε ΠΑΡΟΝΤΑ διαχειριστή· ο διαχειριστής δεν παραχωρεί ποτέ. Η παρουσία είναι
// ίχνος με κάτοχο — φρέσκο ΚΑΙ με ζωντανό instance (βλ. μνήμη «παρουσία =
// συνεδρία, όχι πρόσωπο»).
//
//   flutter test test/features/database/services/backup_responsibility_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/models/operator.dart';
import 'package:call_logger/features/database/services/backup_responsibility.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../../test_setup.dart';

Operator _operator(int id, {bool isAdmin = false}) => Operator(
  id: id,
  displayName: 'Χρήστης $id',
  isAdmin: isAdmin,
  createdAt: DateTime(2026, 8, 20),
);

Future<void> _insertOperatorRow(int id, {bool isAdmin = false}) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('operators', {
    'id': id,
    'display_name': 'Χρήστης $id',
    'is_admin': isAdmin ? 1 : 0,
    'is_active': 1,
    'created_at': '2026-08-20T00:00:00.000',
  });
}

Future<void> _insertPresence(
  int operatorId, {
  required DateTime lastSeenAt,
  String station = 'PC-1',
  String? instance = 'inst-1',
}) async {
  final db = await DatabaseHelper.instance.database;
  await db.insert('operator_presence', {
    'operator_id': operatorId,
    'station': station,
    'last_seen_at': lastSeenAt.toIso8601String(),
    'instance': instance,
  });
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  final now = DateTime(2026, 8, 24, 12, 0);

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('operator_presence');
    await db.delete('operators');
  });

  test('εφεδρικός με παρόντα διαχειριστή → παραχωρεί', () async {
    await _insertOperatorRow(1, isAdmin: true);
    await _insertOperatorRow(2);
    await _insertPresence(1, lastSeenAt: now.subtract(const Duration(minutes: 1)));

    expect(
      await BackupResponsibility.shouldDeferToPresentAdmin(
        current: _operator(2),
        now: now,
      ),
      isTrue,
    );
  });

  test('μπαγιάτικο ίχνος διαχειριστή (>3΄) → ο εφεδρικός αναλαμβάνει', () async {
    await _insertOperatorRow(1, isAdmin: true);
    await _insertOperatorRow(2);
    await _insertPresence(1, lastSeenAt: now.subtract(const Duration(minutes: 4)));

    expect(
      await BackupResponsibility.shouldDeferToPresentAdmin(
        current: _operator(2),
        now: now,
      ),
      isFalse,
    );
  });

  test('ίχνος χωρίς ζωντανό instance δεν μετρά ως παρουσία', () async {
    await _insertOperatorRow(1, isAdmin: true);
    await _insertOperatorRow(2);
    await _insertPresence(
      1,
      lastSeenAt: now.subtract(const Duration(seconds: 30)),
      instance: null,
    );

    expect(
      await BackupResponsibility.shouldDeferToPresentAdmin(
        current: _operator(2),
        now: now,
      ),
      isFalse,
      reason: 'Ο σταθμός πέρασε σε άλλον — φρεσκάδα χωρίς κάτοχο δεν αρκεί.',
    );
  });

  test('ο διαχειριστής δεν παραχωρεί ποτέ — ούτε σε άλλον διαχειριστή', () async {
    await _insertOperatorRow(1, isAdmin: true);
    await _insertOperatorRow(3, isAdmin: true);
    await _insertPresence(3, lastSeenAt: now);

    expect(
      await BackupResponsibility.shouldDeferToPresentAdmin(
        current: _operator(1, isAdmin: true),
        now: now,
      ),
      isFalse,
    );
  });

  test('παρών ΑΛΛΟΣ εφεδρικός (όχι διαχειριστής) δεν δίνει προτεραιότητα', () async {
    await _insertOperatorRow(2);
    await _insertOperatorRow(4);
    await _insertPresence(4, lastSeenAt: now);

    expect(
      await BackupResponsibility.shouldDeferToPresentAdmin(
        current: _operator(2),
        now: now,
      ),
      isFalse,
      reason: 'Δύο εφεδρικούς τους χωρίζει η ατομική δέσμευση, όχι η σειρά.',
    );
  });

  test('χωρίς ταυτότητα: κανένας δισταγμός — όλα όπως πριν από τα προφίλ', () async {
    await _insertOperatorRow(1, isAdmin: true);
    await _insertPresence(1, lastSeenAt: now);

    expect(
      await BackupResponsibility.shouldDeferToPresentAdmin(
        current: null,
        now: now,
      ),
      isFalse,
    );
  });
}
