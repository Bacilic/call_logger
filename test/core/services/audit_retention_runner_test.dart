// Η αυτόματη εκκαθάριση Ιστορικού με λάθος ρολόι: δεν σβήνει μονομιάς τα
// περισσότερα. Η χειροκίνητη δείχνει τον αριθμό και ρωτά, οπότε μένει ως έχει.
//
//   flutter test test/core/services/audit_retention_runner_test.dart

import 'dart:io';

import 'package:call_logger/core/config/audit_retention_config.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/services/audit_retention_runner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  final realNow = DateTime(2026, 11, 5, 12);
  const config = AuditRetentionConfig(
    purgeOnAppStart: true,
    volatileMaxAgeDays: 90,
    minimumRowsFloor: 2,
    exportBeforePurge: false,
  );

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('audit_retention_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/audit_retention.db');
    db = await DatabaseHelper.instance.database;
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    await db.delete('audit_log');
  });

  Future<void> insertCalls(int count, {required int daysAgo}) async {
    for (var i = 0; i < count; i++) {
      await db.insert('audit_log', {
        'action': 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
        'entity_type': 'call',
        'timestamp': realNow
            .subtract(Duration(days: daysAgo))
            .toIso8601String(),
      });
    }
  }

  Future<int> rows() async => (await db.query('audit_log')).length;

  test('ρολόι ένα χρόνο μπροστά: η αυτόματη εκκαθάριση δεν σβήνει τίποτα, και '
      'το λέει', () async {
    await insertCalls(20, daysAgo: 1);

    await expectLater(
      AuditRetentionRunner.applyWithConfig(
        config,
        now: realNow.add(const Duration(days: 365)),
      ),
      throwsA(
        isA<AuditRetentionHeldBack>().having(
          (e) => e.toString(),
          'μήνυμα',
          contains('20 από τις 20'),
        ),
      ),
    );

    expect(await rows(), 20);
  });

  test('το πάτωμα δεν κρύβει τον φρουρό: μετρά ό,τι πιάνουν τα όρια', () async {
    await insertCalls(10, daysAgo: 1);

    await expectLater(
      AuditRetentionRunner.applyWithConfig(
        const AuditRetentionConfig(
          volatileMaxAgeDays: 90,
          minimumRowsFloor: 8,
          exportBeforePurge: false,
        ),
        now: realNow.add(const Duration(days: 365)),
      ),
      throwsA(isA<AuditRetentionHeldBack>()),
    );

    expect(await rows(), 10);
  });

  test('κανονική μέρα: σβήνει τις λίγες παλιές γραμμές', () async {
    await insertCalls(4, daysAgo: 100);
    await insertCalls(16, daysAgo: 1);

    final outcome = await AuditRetentionRunner.applyWithConfig(
      config,
      now: realNow,
    );

    expect(outcome.deleted, 4);
    expect(await rows(), 16);
  });

  test('η χειροκίνητη εκκαθάριση εκτελεί το σχέδιο που εγκρίθηκε, όσο μεγάλο '
      'κι αν είναι', () async {
    await insertCalls(20, daysAgo: 100);
    await insertCalls(2, daysAgo: 1);

    final plan = await AuditRetentionRunner.buildPlan(config, now: realNow);
    final outcome = await AuditRetentionRunner.executePlan(plan, config);

    expect(outcome.deleted, 20);
    expect(await rows(), 2);
  });
}
