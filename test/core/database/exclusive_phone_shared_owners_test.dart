// Τηλέφωνο που το μοιράζονται δύο υπάλληλοι οι οποίοι διαγράφονται ΜΑΖΙ.
//
// Το κριτήριο «αποκλειστικό τηλέφωνο» ρωτούσε «ανήκει σε ακριβώς έναν χρήστη
// συνολικά;» χωρίς να κοιτάζει ποιοι διαγράφονται. Με δύο κατόχους δεν
// θεωρούνταν ποτέ αποκλειστικό, δεν ρωτιόταν, και έμενε χωρίς κάτοχο.
//
//   flutter test test/core/database/exclusive_phone_shared_owners_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  late Database db;
  late UserRepository users;

  setUpAll(() async {
    initSqfliteFfiForTests();
    final dir = await Directory.systemTemp.createTemp('phone_orphan_test_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/phone_orphan.db');
    db = await DatabaseHelper.instance.database;
    users = UserRepository(db);
  });

  setUp(() async {
    await seedIsolatedTestDatabase();
    for (final t in const [
      'audit_log',
      'user_equipment',
      'user_phones',
      'department_phones',
      'phones',
      'equipment',
      'users',
      'departments',
    ]) {
      await db.delete(t);
    }
  });

  tearDownAll(() async {
    await releaseCallLoggerTestDatabase();
  });

  Future<int> insertUser(String last, int deptId, {int isDeleted = 0}) {
    return db.insert('users', {
      'first_name': 'Δοκιμή',
      'last_name': last,
      'department_id': deptId,
      'is_deleted': isDeleted,
    });
  }

  Future<({int dept, int phone, int userA, int userB})> seedSharedPhone({
    int secondOwnerIsDeleted = 0,
  }) async {
    final deptId = await db.insert('departments', {
      'name': 'Γραμματεία',
      'name_key': SearchTextNormalizer.normalizeForSearch('Γραμματεία'),
      'is_deleted': 0,
    });
    final userA = await insertUser('Παπαδόπουλος', deptId);
    final userB = await insertUser(
      'Ιωάννου',
      deptId,
      isDeleted: secondOwnerIsDeleted,
    );
    final phoneId = await db.insert('phones', {'number': '2530'});
    await db.insert('user_phones', {'user_id': userA, 'phone_id': phoneId});
    await db.insert('user_phones', {'user_id': userB, 'phone_id': phoneId});
    return (dept: deptId, phone: phoneId, userA: userA, userB: userB);
  }

  test('δύο κάτοχοι που διαγράφονται μαζί: το τηλέφωνο ρωτιέται', () async {
    final seeded = await seedSharedPhone();

    final found = await users.findExclusivePhonesForUserDelete([
      seeded.userA,
      seeded.userB,
    ]);

    expect(found, hasLength(1), reason: 'μία ερώτηση, όχι μία ανά κάτοχο');
    expect(found.single.number, '2530');
  });

  test(
    'κάτοχος που ΔΕΝ διαγράφεται κρατά το τηλέφωνο εκτός κινδύνου',
    () async {
      final seeded = await seedSharedPhone();

      final found = await users.findExclusivePhonesForUserDelete([
        seeded.userA,
      ]);

      expect(found, isEmpty, reason: 'ο userB μένει και κρατά τον αριθμό');
    },
  );

  test('διαγραμμένος συγκάτοχος δεν εμποδίζει την ερώτηση', () async {
    final seeded = await seedSharedPhone(secondOwnerIsDeleted: 1);

    final found = await users.findExclusivePhonesForUserDelete([seeded.userA]);

    expect(
      found,
      hasLength(1),
      reason: 'ο soft-deleted κάτοχος δεν είναι πραγματικός κάτοχος',
    );
  });

  test('μοναδικός κάτοχος: αμετάβλητη συμπεριφορά', () async {
    final deptId = await db.insert('departments', {
      'name': 'Ακτινολογικό',
      'name_key': SearchTextNormalizer.normalizeForSearch('Ακτινολογικό'),
      'is_deleted': 0,
    });
    final userId = await insertUser('Μόνος', deptId);
    final phoneId = await db.insert('phones', {'number': '2540'});
    await db.insert('user_phones', {'user_id': userId, 'phone_id': phoneId});

    final found = await users.findExclusivePhonesForUserDelete([userId]);

    expect(found, hasLength(1));
    expect(found.single.number, '2540');
    expect(found.single.departmentId, deptId);
    expect(found.single.departmentName, 'Ακτινολογικό');
  });
}
