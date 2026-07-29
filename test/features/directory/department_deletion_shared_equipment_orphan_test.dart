// Εξοπλισμός που τον μοιράζονται δύο υπάλληλοι οι οποίοι διαγράφονται ΜΑΖΙ.
//
// Η διαγραφή τμήματος ρωτούσε τη βάση ανά υπάλληλο· επειδή το κριτήριο
// «μένει ορφανό» εξαιρεί τους διαγραφόμενους, σε κάθε ατομική κλήση «υπήρχε
// άλλος κάτοχος» — ο άλλος διαγραφόμενος — και ο εξοπλισμός δεν εμφανιζόταν
// πουθενά, μένοντας χωρίς κάτοχο και χωρίς τμήμα.
//
//   flutter test test/features/directory/department_deletion_shared_equipment_orphan_test.dart

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
    final dir = await Directory.systemTemp.createTemp('dept_orphan_test_');
    await DatabaseHelper.bindTestDatabaseFile('${dir.path}/dept_orphan.db');
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

  /// Δύο υπάλληλοι του ίδιου τμήματος μοιράζονται έναν εκτυπωτή χωρίς τμήμα.
  Future<({int userA, int userB})> seedSharedPrinter() async {
    final deptId = await db.insert('departments', {
      'name': 'Γραμματεία',
      'name_key': SearchTextNormalizer.normalizeForSearch('Γραμματεία'),
      'is_deleted': 0,
    });
    final userA = await db.insert('users', {
      'first_name': 'Νίκος',
      'last_name': 'Παπαδόπουλος',
      'department_id': deptId,
      'is_deleted': 0,
    });
    final userB = await db.insert('users', {
      'first_name': 'Ελένη',
      'last_name': 'Ιωάννου',
      'department_id': deptId,
      'is_deleted': 0,
    });
    final equipmentId = await db.insert('equipment', {
      'code_equipment': '4120',
      'type': 'Printer',
      'department_id': null,
      'is_deleted': 0,
    });
    await db.insert('user_equipment', {
      'user_id': userA,
      'equipment_id': equipmentId,
    });
    await db.insert('user_equipment', {
      'user_id': userB,
      'equipment_id': equipmentId,
    });
    return (userA: userA, userB: userB);
  }

  test(
    'ερώτημα ανά υπάλληλο δεν βλέπει τον κοινό εξοπλισμό (η παλιά αιτία)',
    () async {
      final seeded = await seedSharedPrinter();

      expect(
        await users.findExclusiveEquipmentForUserDelete([seeded.userA]),
        isEmpty,
        reason:
            'ο userB μετράει ως «άλλος κάτοχος» παρότι διαγράφεται κι αυτός',
      );
      expect(
        await users.findExclusiveEquipmentForUserDelete([seeded.userB]),
        isEmpty,
        reason: 'συμμετρικά, ο userA μετράει ως «άλλος κάτοχος»',
      );
    },
  );

  test('ΕΝΑ μαζικό ερώτημα για όλους τον πιάνει ακριβώς μία φορά', () async {
    final seeded = await seedSharedPrinter();

    final found = await users.findExclusiveEquipmentForUserDelete([
      seeded.userA,
      seeded.userB,
    ]);

    expect(found, hasLength(1));
    expect(found.single.codeEquipment, '4120');
  });

  test(
    'υπάλληλος εκτός διαγραφής κρατά τον εξοπλισμό εκτός κινδύνου',
    () async {
      final seeded = await seedSharedPrinter();

      // Μόνο ο Α διαγράφεται — ο Β μένει, άρα ο εκτυπωτής δεν ορφανεύει.
      final found = await users.findExclusiveEquipmentForUserDelete([
        seeded.userA,
      ]);

      expect(found, isEmpty);
    },
  );
}
