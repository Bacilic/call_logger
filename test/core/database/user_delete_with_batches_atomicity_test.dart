// Ατομικότητα διαγραφής υπαλλήλων μαζί με τις διαθέσεις τηλεφώνων/εξοπλισμού.
//
// Συμβόλαιο: κάθε σύνθετη μετάβαση δεδομένων εκτελείται σε ΜΙΑ συναλλαγή —
// διακοπή ανάμεσα σε διαγραφή και διαθέσεις δεν αφήνει διαγραμμένους
// υπαλλήλους με τα τηλέφωνά τους σε ενδιάμεση κατάσταση.
//
//   flutter test test/core/database/user_delete_with_batches_atomicity_test.dart

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/features/directory/screens/widgets/shared_asset_disconnect_dialog.dart';
import 'package:call_logger/features/directory/services/shared_asset_disconnect_apply.dart';
import 'package:flutter_test/flutter_test.dart';

import '../../test_setup.dart';

void main() {
  registerCallLoggerIsolatedDatabaseHooks();

  group('διαγραφή υπαλλήλου + διαθέσεις σε ΜΙΑ συναλλαγή', () {
    setUp(() async {
      await bindCallLoggerIsolatedTestDatabase();
    });

    Future<({int userId, int deptId})> seededUserAndDept() async {
      final db = await DatabaseHelper.instance.database;
      final userRows = await db.query(
        'users',
        where: 'first_name = ? AND last_name = ?',
        whereArgs: [kTestUserFirstName, kTestUserLastName],
        limit: 1,
      );
      expect(userRows, isNotEmpty);
      final deptRows = await db.query(
        'departments',
        where: 'name = ?',
        whereArgs: [kTestDepartmentName],
        limit: 1,
      );
      expect(deptRows, isNotEmpty);
      return (
        userId: userRows.first['id'] as int,
        deptId: deptRows.first['id'] as int,
      );
    }

    test(
      'διακοπή μετά τις διαθέσεις αναιρεί ΚΑΙ τη διαγραφή ΚΑΙ τις διαθέσεις',
      () async {
        final db = await DatabaseHelper.instance.database;
        final seeded = await seededUserAndDept();
        final batch = const SharedAssetDisconnectBatchResult(
          phonesToDelete: [kTestPhoneDigits],
        );

        await expectLater(
          db.transaction((txn) async {
            await UserRepository(
              db,
            ).deleteUsers([seeded.userId], executor: txn);
            await applyPersonalPhoneDisconnectBatch(
              db,
              batch,
              sourceDepartmentId: seeded.deptId,
              executor: txn,
            );
            throw StateError('προσομοίωση διακοπής');
          }),
          throwsA(isA<StateError>()),
        );

        final userRow = (await db.query(
          'users',
          where: 'id = ?',
          whereArgs: [seeded.userId],
        )).first;
        expect(
          userRow['is_deleted'],
          0,
          reason: 'η διαγραφή πρέπει να αναιρεθεί',
        );

        final linkRows = await db.query(
          'user_phones',
          where: 'user_id = ?',
          whereArgs: [seeded.userId],
        );
        expect(
          linkRows,
          isNotEmpty,
          reason: 'η σύνδεση τηλεφώνου πρέπει να επανέλθει με το rollback',
        );

        final phoneRow = (await db.query(
          'phones',
          where: 'number = ?',
          whereArgs: [kTestPhoneDigits],
        )).first;
        expect(
          phoneRow['is_deleted'] ?? 0,
          0,
          reason: 'το τηλέφωνο δεν πρέπει να μείνει διαγραμμένο',
        );
      },
    );

    test('χωρίς διακοπή: διαγραφή και διαθέσεις εφαρμόζονται μαζί', () async {
      final db = await DatabaseHelper.instance.database;
      final seeded = await seededUserAndDept();
      final batch = const SharedAssetDisconnectBatchResult(
        phonesToDelete: [kTestPhoneDigits],
      );

      await db.transaction((txn) async {
        await UserRepository(db).deleteUsers([seeded.userId], executor: txn);
        await applyPersonalPhoneDisconnectBatch(
          db,
          batch,
          sourceDepartmentId: seeded.deptId,
          executor: txn,
        );
      });

      final userRow = (await db.query(
        'users',
        where: 'id = ?',
        whereArgs: [seeded.userId],
      )).first;
      expect(userRow['is_deleted'], 1);

      final phoneRow = (await db.query(
        'phones',
        where: 'number = ?',
        whereArgs: [kTestPhoneDigits],
      )).first;
      expect(
        phoneRow['is_deleted'],
        1,
        reason: 'η διάθεση «διαγραφή» εφαρμόστηκε',
      );
    });
  });
}
