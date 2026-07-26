// Καθαρή λογική ειδοποίησης παλιάς/ημιτελούς βάσης.
//
//   flutter test test/core/database/database_state_notice_test.dart

import 'package:call_logger/core/database/database_file_classifier.dart';
import 'package:call_logger/core/database/database_state_notice.dart';
import 'package:flutter_test/flutter_test.dart';

DatabaseFileProfile _callLoggerProfile({
  int? callCount,
  int? userCount,
  int? phoneCount,
  int? equipmentCount,
  int? departmentCount,
  String? latestCallDate,
}) {
  return DatabaseFileProfile(
    kind: DatabaseFileKind.callLogger,
    callCount: callCount,
    userCount: userCount,
    phoneCount: phoneCount,
    equipmentCount: equipmentCount,
    departmentCount: departmentCount,
    latestCallDate: latestCallDate,
  );
}

void main() {
  final now = DateTime(2026, 7, 25, 12);
  final modified = DateTime(2026, 7, 20);
  const path = r'C:\data\maria.db';

  group('evaluateDatabaseStateNotice', () {
    test('πλήρως κενή βάση → ημιτελής με όλες τις κατηγορίες', () {
      final notice = evaluateDatabaseStateNotice(
        profile: _callLoggerProfile(
          callCount: 0,
          userCount: 0,
          phoneCount: 0,
          equipmentCount: 0,
          departmentCount: 0,
        ),
        dbPath: path,
        fileModifiedAt: modified,
        now: now,
      );

      expect(notice.kind, DatabaseNoticeKind.emptyDatabase);
      expect(
        notice.message,
        "ημιτελής βάση 'maria.db' - Δεν υπάρχουν καθόλου: "
        'κλήσεις, υπάλληλοι, τηλέφωνα, εξοπλισμός, τμήματα',
      );
    });

    test('μόνο μηδέν εξοπλισμός → στοχευμένο μήνυμα', () {
      final notice = evaluateDatabaseStateNotice(
        profile: _callLoggerProfile(
          callCount: 10,
          userCount: 5,
          phoneCount: 8,
          equipmentCount: 0,
          departmentCount: 2,
        ),
        dbPath: r'C:\data\χωρίς_εξοπλισμό.db',
        fileModifiedAt: modified,
        now: now,
      );

      expect(notice.kind, DatabaseNoticeKind.emptyDatabase);
      expect(
        notice.message,
        "ημιτελής βάση 'χωρίς_εξοπλισμό.db' - Δεν υπάρχουν καθόλου: εξοπλισμός",
      );
    });

    test('μηδέν τηλέφωνα και τμήματα → λίστα δύο κατηγοριών', () {
      final notice = evaluateDatabaseStateNotice(
        profile: _callLoggerProfile(
          callCount: 3,
          userCount: 2,
          phoneCount: 0,
          equipmentCount: 4,
          departmentCount: 0,
        ),
        dbPath: path,
        fileModifiedAt: modified,
        now: now,
      );

      expect(notice.kind, DatabaseNoticeKind.emptyDatabase);
      expect(
        notice.message,
        "ημιτελής βάση 'maria.db' - Δεν υπάρχουν καθόλου: τηλέφωνα, τμήματα",
      );
    });

    test('παλιά βάση ακριβώς στο όριο των 60 ημερών → oldDatabase', () {
      final latest = now.subtract(
        const Duration(days: kOldDatabaseNoticeThresholdDays),
      );
      final notice = evaluateDatabaseStateNotice(
        profile: _callLoggerProfile(
          callCount: 12480,
          userCount: 10,
          phoneCount: 20,
          equipmentCount: 15,
          departmentCount: 3,
          latestCallDate:
              '${latest.year.toString().padLeft(4, '0')}-'
              '${latest.month.toString().padLeft(2, '0')}-'
              '${latest.day.toString().padLeft(2, '0')}',
        ),
        dbPath: path,
        fileModifiedAt: modified,
        now: now,
      );

      expect(notice.kind, DatabaseNoticeKind.oldDatabase);
      expect(notice.message, contains('ΠΑΛΙΑ ΒΑΣΗ'));
      expect(notice.message, contains('maria.db'));
      expect(notice.message, contains('12.480 κλήσεις'));
      expect(
        notice.message,
        contains(
          'τελευταία στις '
          '${latest.day.toString().padLeft(2, '0')}/'
          '${latest.month.toString().padLeft(2, '0')}/'
          '${latest.year}',
        ),
      );
    });

    test('φρέσκια βάση → none', () {
      final latest = now.subtract(const Duration(days: 10));
      final notice = evaluateDatabaseStateNotice(
        profile: _callLoggerProfile(
          callCount: 50,
          userCount: 5,
          phoneCount: 8,
          equipmentCount: 12,
          departmentCount: 2,
          latestCallDate:
              '${latest.year.toString().padLeft(4, '0')}-'
              '${latest.month.toString().padLeft(2, '0')}-'
              '${latest.day.toString().padLeft(2, '0')}',
        ),
        dbPath: path,
        fileModifiedAt: modified,
        now: now,
      );

      expect(notice.kind, DatabaseNoticeKind.none);
      expect(notice.message, isEmpty);
    });

    test('ημιτελής προηγείται της παλιάς', () {
      final notice = evaluateDatabaseStateNotice(
        profile: _callLoggerProfile(
          callCount: 0,
          userCount: 1,
          phoneCount: 1,
          equipmentCount: 1,
          departmentCount: 1,
          latestCallDate: '2020-01-01',
        ),
        dbPath: path,
        fileModifiedAt: modified,
        now: now,
      );

      expect(notice.kind, DatabaseNoticeKind.emptyDatabase);
      expect(notice.message, isNot(contains('ΠΑΛΙΑ ΒΑΣΗ')));
      expect(notice.message, contains('κλήσεις'));
    });
  });

  group('databaseContentIdentity', () {
    test(
      'ίδια διαδρομή με διαφορετικό latestCallDate → διαφορετική ταυτότητα',
      () {
        final a = databaseContentIdentity(
          dbPath: path,
          latestCallDate: '2023-03-14',
          callCount: 100,
          fileModifiedMs: 1000,
        );
        final b = databaseContentIdentity(
          dbPath: path,
          latestCallDate: '2024-01-01',
          callCount: 100,
          fileModifiedMs: 1000,
        );
        expect(a, isNot(equals(b)));
      },
    );

    test('ίδια διαδρομή με διαφορετικό callCount → διαφορετική ταυτότητα', () {
      final a = databaseContentIdentity(
        dbPath: path,
        latestCallDate: '2023-03-14',
        callCount: 100,
        fileModifiedMs: 1000,
      );
      final b = databaseContentIdentity(
        dbPath: path,
        latestCallDate: '2023-03-14',
        callCount: 200,
        fileModifiedMs: 1000,
      );
      expect(a, isNot(equals(b)));
    });

    test(
      'ίδια διαδρομή με διαφορετικό equipmentCount → διαφορετική ταυτότητα',
      () {
        final a = databaseContentIdentity(
          dbPath: path,
          latestCallDate: '2023-03-14',
          callCount: 100,
          equipmentCount: 0,
          fileModifiedMs: 1000,
        );
        final b = databaseContentIdentity(
          dbPath: path,
          latestCallDate: '2023-03-14',
          callCount: 100,
          equipmentCount: 5,
          fileModifiedMs: 1000,
        );
        expect(a, isNot(equals(b)));
      },
    );
  });
}
