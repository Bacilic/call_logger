import 'dart:io';

import 'package:call_logger/core/database/audit_service.dart';
import 'package:call_logger/core/database/calls_repository.dart';
import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/directory_support.dart';
import 'package:call_logger/core/database/tasks_repository.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/features/audit/models/audit_log_model.dart';
import 'package:call_logger/features/audit/services/audit_formatter_service.dart';
import 'package:call_logger/features/calls/models/call_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

/// Φάση 3 audit: ένδειξη προέλευσης σε παράγωγες εγγραφές αλυσίδας κλήσης/εκκρεμότητας.
void main() {
  group('audit origin chain — repository write path', () {
    late Database db;
    late CallsRepository calls;
    late TasksRepository tasks;
    late UserRepository users;
    late AuditService auditService;
    const formatter = AuditFormatterService();

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('audit_origin_chain_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/audit_origin.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('audit_log');
      await db.delete('tasks');
      await db.delete('calls');
      await db.delete('user_equipment');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('equipment');
      await db.delete('users');
      await db.delete('departments');
      calls = CallsRepository(db);
      tasks = TasksRepository();
      users = UserRepository(db);
      auditService = AuditService(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<List<Map<String, dynamic>>> allAuditRows() =>
        db.query('audit_log', orderBy: 'id ASC');

    bool hasCallOriginSuffix(String? details, int callId) =>
        (details ?? '').contains(DirectorySupport.auditOriginSuffixFromCall(callId));

    bool hasTaskOriginSuffix(String? details, int taskId) =>
        (details ?? '').contains(DirectorySupport.auditOriginSuffixFromTask(taskId));

    test(
      'κλήση με νέο καλούντα + νέο τηλέφωνο: όλες οι παράγωγες έχουν «από κλήση #N»',
      () async {
        const phone = '2107778899';
        const deptName = 'Τμήμα Αλυσίδας';

        late int callId;
        await db.transaction((txn) async {
          callId = await calls.insertCallOnExecutor(
            txn,
            CallModel(
              phoneText: phone,
              departmentText: deptName,
              callerText: 'Προσωρινός',
              issue: 'Δοκιμή αλυσίδας',
            ),
            afterCallInserted: (innerTxn, originSuffix) async {
              final userId = await users.insertUser(
                firstName: 'Νέος',
                lastName: 'Καλών',
                phones: [phone],
                department: deptName,
                executor: innerTxn,
                skipPhonePolicyValidation: true,
                auditOriginSuffix: originSuffix,
              );
              await users.updateAssociationsIfNeeded(
                userId,
                phone,
                'EQ-CHAIN',
                executor: innerTxn,
                auditOriginSuffix: originSuffix,
              );
            },
          );
        });

        final rows = await allAuditRows();
        expect(rows.length, greaterThan(1));

        final mainCall = rows.firstWhere(
          (r) => r['action'] == 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
        );
        expect(mainCall['entity_type'], AuditEntityTypes.call);
        expect(hasCallOriginSuffix(mainCall['details'] as String?, callId), isFalse);

        final derivatives = rows.where(
          (r) => r['action'] != 'ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ',
        );
        expect(derivatives, isNotEmpty);
        for (final row in derivatives) {
          expect(
            hasCallOriginSuffix(row['details'] as String?, callId),
            isTrue,
            reason: 'action=${row['action']} details=${row['details']}',
          );
        }
      },
    );

    test(
      'εκκρεμότητα με γρήγορη προσθήκη καλούντα: παράγωγες έχουν «από εκκρεμότητα #N»',
      () async {
        final row = await tasks.buildCreateFromCallRow(
          callId: null,
          callerName: 'Quick',
          description: '#quickadd Δοκιμή προέλευσης',
          callDate: DateTime(2026, 7, 11, 12),
          origin: 'quick_add',
        );
        late int taskId;
        await db.transaction((txn) async {
          taskId = await tasks.createFromCallOnExecutor(
            txn,
            row: row,
            afterTaskInserted: (innerTxn, originSuffix) async {
              await users.insertUser(
                firstName: 'Γρήγορος',
                lastName: 'Καλών',
                phones: ['2108889900'],
                department: 'Quick Dept',
                executor: innerTxn,
                skipPhonePolicyValidation: true,
                auditOriginSuffix: originSuffix,
              );
            },
          );
        });

        final rows = await allAuditRows();
        final mainTask = rows.firstWhere(
          (r) => r['action'] == 'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ',
        );
        expect(hasTaskOriginSuffix(mainTask['details'] as String?, taskId), isFalse);

        final derivatives = rows.where(
          (r) => r['action'] != 'ΔΗΜΙΟΥΡΓΙΑ ΕΚΚΡΕΜΟΤΗΤΑΣ',
        );
        expect(derivatives, isNotEmpty);
        for (final row in derivatives) {
          expect(hasTaskOriginSuffix(row['details'] as String?, taskId), isTrue);
        }
      },
    );

    test(
      'αυτόνομη επεξεργασία χρήστη από Κατάλογο: χωρίς ένδειξη προέλευσης',
      () async {
        final userId = await users.insertUser(
          firstName: 'Αυτόνομος',
          lastName: 'Χρήστης',
          skipPhonePolicyValidation: true,
        );
        await db.delete('audit_log');

        await users.updateUser(userId, {'first_name': 'Ενημερωμένος'});

        final rows = await allAuditRows();
        expect(rows, hasLength(1));
        final details = rows.single['details'] as String? ?? '';
        expect(details.contains('από κλήση #'), isFalse);
        expect(details.contains('από εκκρεμότητα #'), isFalse);
        expect(formatter.originDisplayLine(
          AuditLogModel(
            id: 1,
            action: rows.single['action'] as String?,
            details: rows.single['details'] as String?,
          ),
        ), isNull);
      },
    );

    test('αναζήτηση με id κλήσης βρίσκει ολόκληρη την αλυσίδα', () async {
      const phone = '2106665544';
      late int callId;

      await db.transaction((txn) async {
        callId = await calls.insertCallOnExecutor(
          txn,
          CallModel(phoneText: phone, issue: 'Αναζήτηση αλυσίδας'),
          afterCallInserted: (innerTxn, originSuffix) async {
            await users.insertUser(
              firstName: 'Α',
              lastName: 'Β',
              phones: [phone],
              department: 'Dept Search',
              executor: innerTxn,
              skipPhonePolicyValidation: true,
              auditOriginSuffix: originSuffix,
            );
          },
        );
      });

      final allRows = await allAuditRows();
      expect(allRows.length, greaterThan(1));

      final keyword = SearchTextNormalizer.normalizeForSearch('$callId');
      final ids = await auditService.queryMatchingIds(keywordNormalized: keyword);
      expect(ids.length, allRows.length);
    });

    test(
      'deferred stamping: παράγωγες πριν το id κλήσης ενημερώνονται στο τέλος συναλλαγής',
      () async {
        const phone = '2103332211';
        final pending = PendingAuditOriginRows();
        late int callId;

        await db.transaction((txn) async {
          final userId = await users.insertUser(
            firstName: 'Deferred',
            lastName: 'Origin',
            phones: [phone],
            department: 'Deferred Dept',
            executor: txn,
            skipPhonePolicyValidation: true,
          );
          final rowsBeforeCall = await txn.query('audit_log', orderBy: 'id ASC');
          for (final r in rowsBeforeCall) {
            pending.track(r['id'] as int?);
          }
          await users.updateAssociationsIfNeeded(
            userId,
            phone,
            'EQ-DEF',
            executor: txn,
          );
          final rowsAfterAssoc = await txn.query('audit_log', orderBy: 'id ASC');
          for (final r in rowsAfterAssoc) {
            pending.track(r['id'] as int?);
          }

          callId = await calls.insertCallOnExecutor(
            txn,
            CallModel(phoneText: phone, issue: 'Deferred stamp'),
          );
          await pending.applyOriginSuffix(
            txn,
            DirectorySupport.auditOriginSuffixFromCall(callId),
          );
        });

        final derivatives = await db.query(
          'audit_log',
          where: 'action != ?',
          whereArgs: ['ΔΗΜΙΟΥΡΓΙΑ ΚΛΗΣΗΣ'],
        );
        expect(derivatives, isNotEmpty);
        for (final row in derivatives) {
          expect(hasCallOriginSuffix(row['details'] as String?, callId), isTrue);
        }
      },
    );

    test(
      'formatter: προέλευση ως διακριτή γραμμή, όχι κολλημένη στο κείμενο λεπτομερειών',
      () async {
        const suffix = ' — από κλήση #2818';
        final row = AuditLogModel(
          id: 1,
          action: 'ΔΗΜΙΟΥΡΓΙΑ ΧΡΗΣΤΗ',
          details: 'users id=3$suffix',
        );
        expect(formatter.originDisplayLine(row), 'Προέλευση: Κλήση #2818');
        expect(formatter.detailsWithoutOrigin(row), 'users id=3');
        expect(formatter.summaryLine(row), isNot(contains('από κλήση')));
      },
    );
  });
}
