// Ο μετρητής αφύλακτων αλλαγών (Φάση 3): μετρά εγγραφές Ιστορικού μετά το
// σημάδι, ΧΩΡΙΣ τις εγγραφές του ίδιου του μηχανισμού αντιγράφων — αλλιώς
// κάθε αντίγραφο θα γεννούσε «νέα αλλαγή» και ο κύκλος δεν θα έκλεινε ποτέ.
//
//   flutter test test/core/database/backup_pending_changes_test.dart

import 'package:call_logger/core/database/backup_pending_changes.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

Future<int> _insertAudit({String? entityType}) async {
  final db = await DatabaseHelper.instance.database;
  return db.insert('audit_log', {
    'action': 'ΔΟΚΙΜΑΣΤΙΚΗ ΑΛΛΑΓΗ',
    'timestamp': DateTime.now().toIso8601String(),
    'user_performing': 'τεστ',
    'details': 'x',
    'entity_type': ?entityType,
  });
}

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  setUp(() async {
    final db = await DatabaseHelper.instance.database;
    await db.delete('audit_log');
  });

  test('μετρά μόνο ό,τι ήρθε μετά το σημάδι', () async {
    final db = await DatabaseHelper.instance.database;
    final repo = BackupPendingChangesRepository(db);

    final first = await _insertAudit();
    await _insertAudit();
    await _insertAudit();

    expect(await repo.countPendingSince(null), 3);
    expect(await repo.countPendingSince(first), 2);
    expect(await repo.countPendingSince(await repo.latestAuditId()), 0);
  });

  test('οι εγγραφές του μηχανισμού αντιγράφων δεν μετρούν ως αλλαγές', () async {
    final db = await DatabaseHelper.instance.database;
    final repo = BackupPendingChangesRepository(db);

    final mark = await _insertAudit();
    await _insertAudit(entityType: 'backup');
    await _insertAudit(entityType: 'backup');

    expect(
      await repo.countPendingSince(mark),
      0,
      reason: 'Μόνο πραγματικές αλλαγές ξαναοπλίζουν τον μετρητή.',
    );

    await _insertAudit(entityType: 'user');
    expect(await repo.countPendingSince(mark), 1);
  });

  group('χωρίς σημάδι: μέτρημα από το τελευταίο γνωστό αντίγραφο', () {
    Future<void> insertAuditAt(DateTime at, {String? entityType}) async {
      final db = await DatabaseHelper.instance.database;
      await db.insert('audit_log', {
        'action': 'ΔΟΚΙΜΑΣΤΙΚΗ ΑΛΛΑΓΗ',
        'timestamp': at.toIso8601String(),
        'user_performing': 'τεστ',
        'details': 'x',
        'entity_type': ?entityType,
      });
    }

    test('μετρά μόνο ό,τι ήρθε μετά τη στιγμή του αντιγράφου', () async {
      final db = await DatabaseHelper.instance.database;
      final repo = BackupPendingChangesRepository(db);
      final backupAt = DateTime(2026, 7, 23, 14, 40);

      // Ιστορικό μηνών πριν από το αντίγραφο — ΔΕΝ είναι αφύλακτο.
      await insertAuditAt(DateTime(2026, 6, 5, 9, 0));
      await insertAuditAt(DateTime(2026, 7, 1, 12, 0));
      await insertAuditAt(backupAt.subtract(const Duration(minutes: 1)));
      // Μετά το αντίγραφο — αυτά είναι τα αφύλακτα.
      await insertAuditAt(DateTime(2026, 7, 24, 8, 0));
      await insertAuditAt(DateTime(2026, 8, 24, 12, 57));
      // Εγγραφή του ίδιου του μηχανισμού: δεν μετρά ποτέ.
      await insertAuditAt(DateTime(2026, 8, 24, 13, 0), entityType: 'backup');

      expect(
        await repo.countPendingSince(null, fallbackSince: backupAt),
        2,
        reason:
            'Χωρίς fallback θα μετρούσε ΟΛΟ το Ιστορικό — «1775 αφύλακτες» '
            'σε βάση που είχε αντίγραφο πριν από έναν μήνα.',
      );
      expect(
        await repo.countPendingSince(null),
        5,
        reason: 'Χωρίς καμία αναφορά, τίποτα δεν είναι αποδεδειγμένα φυλαγμένο.',
      );
    });

    test('το σημάδι υπερισχύει του fallback όταν υπάρχει', () async {
      final db = await DatabaseHelper.instance.database;
      final repo = BackupPendingChangesRepository(db);

      await insertAuditAt(DateTime(2026, 8, 24, 10, 0));
      final mark = await repo.latestAuditId();
      await insertAuditAt(DateTime(2026, 8, 24, 11, 0));

      expect(
        await repo.countPendingSince(
          mark,
          fallbackSince: DateTime(2020, 1, 1),
        ),
        1,
        reason: 'Το ακριβές σημάδι δεν παρακάμπτεται από τον χρόνο.',
      );
    });
  });

  test('latestAuditId: 0 σε άδειο Ιστορικό, αλλιώς το μέγιστο id', () async {
    final db = await DatabaseHelper.instance.database;
    final repo = BackupPendingChangesRepository(db);

    expect(await repo.latestAuditId(), 0);
    await _insertAudit();
    final last = await _insertAudit(entityType: 'backup');
    expect(
      await repo.latestAuditId(),
      last,
      reason:
          'Το σημάδι μετά από αντίγραφο καλύπτει ΚΑΙ την audit εγγραφή του — '
          'δεν την ξαναμετρά ως αφύλακτη.',
    );
  });
}
