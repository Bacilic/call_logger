// Οι τρεις καρτέλες του Καταλόγου —υπάλληλος, τμήμα, εξοπλισμός— γράφονται
// ΟΛΟΚΛΗΡΕΣ από την εικόνα που φόρτωσε η φόρμα. Όποιος σώσει δεύτερος έσβηνε
// αμίλητα ό,τι είχε αλλάξει ο πρώτος: τμήμα, τηλέφωνο, σημειώσεις.
//
//   flutter test test/features/directory/directory_card_stale_write_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/database/department_repository.dart';
import 'package:call_logger/core/database/equipment_repository.dart';
import 'package:call_logger/core/database/user_repository.dart';
import 'package:call_logger/features/calls/models/user_model.dart';
import 'package:call_logger/features/directory/providers/directory_provider.dart';
import 'package:call_logger/features/directory/services/directory_save_conflict.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../test_setup.dart';

void main() {
  group('Καρτέλες Καταλόγου — φρουρός μπαγιάτικης εγγραφής', () {
    late Database db;
    late UserRepository users;
    late DepartmentRepository departments;
    late EquipmentRepository equipment;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp('directory_stale_');
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/directory.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      users = UserRepository(db);
      departments = DepartmentRepository(db);
      equipment = EquipmentRepository(db);
    });

    tearDownAll(() async {
      await releaseCallLoggerTestDatabase();
    });

    Future<Map<String, Object?>> rowById(String table, int id) async {
      final rows = await db.query(
        table,
        where: 'id = ?',
        whereArgs: [id],
        limit: 1,
      );
      return Map<String, Object?>.from(rows.first);
    }

    // ------------------------------------------------------------------
    // Υπάλληλος
    // ------------------------------------------------------------------

    test('η διόρθωση ονόματος δεν σβήνει το τμήμα που έβαλε ο άλλος', () async {
      final deptA = (await departments.getOrCreateDepartmentIdByName(
        'Χειρουργική',
      ))!;
      final deptB = (await departments.getOrCreateDepartmentIdByName(
        'Ακτινολογικό',
      ))!;
      final id = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
        'department_id': deptA,
      });

      // Η φόρμα μου φόρτωσε την καρτέλα με το πρώτο τμήμα.
      final asFormSawIt = <String, Object?>{
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
        'department_id': deptA,
        'phones': UserRepository.phonesFingerprint(const []),
      };

      // Ο συνάδελφος τη μεταφέρει σε άλλο τμήμα.
      await users.updateUser(id, {'department_id': deptB}, expected: null);

      // Εγώ διορθώνω μόνο το όνομα, πάνω στην παλιά μου εικόνα.
      await expectLater(
        () => users.updateUser(id, {
          'first_name': 'Σοφια',
          'last_name': 'Ψαρρά',
          'department_id': deptA,
          'phones': const <String>[],
        }, expected: asFormSawIt),
        throwsA(isA<DirectoryStaleException>()),
      );

      expect(
        (await rowById('users', id))['department_id'],
        deptB,
        reason: 'το τμήμα που έβαλε ο συνάδελφος δεν επιτρέπεται να επανέλθει',
      );
    });

    test('η εξαίρεση λέει ποιο πεδίο άγγιξε ο άλλος', () async {
      final id = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
      });
      final asFormSawIt = <String, Object?>{
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
        'notes': null,
      };
      await users.updateUser(id, {
        'notes': 'Βάρδια απογεύματος',
      }, expected: null);

      try {
        await users.updateUser(id, {
          'first_name': 'Σοφια',
          'last_name': 'Ψαρρά',
          'notes': null,
        }, expected: asFormSawIt);
        fail('Έπρεπε να απορριφθεί η μπαγιάτικη εγγραφή');
      } on DirectoryStaleException catch (e) {
        expect(e.conflict.changedKeys, ['notes']);
        expect(e.conflict.overwriteWarning, contains('σημει'));
      }
    });

    test('το τηλέφωνο που πρόσθεσε ο άλλος δεν χάνεται αμίλητα', () async {
      final id = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
        'phones': const <String>['2534'],
      });
      final asFormSawIt = <String, Object?>{
        'first_name': 'Σοφία',
        'phones': UserRepository.phonesFingerprint(const ['2534']),
      };

      await users.updateUser(id, {
        'phones': const <String>['2534', '2565'],
      }, expected: null);

      await expectLater(
        () => users.updateUser(id, {
          'first_name': 'Σοφία',
          'phones': const <String>['2534'],
        }, expected: asFormSawIt),
        throwsA(isA<DirectoryStaleException>()),
      );

      expect(
        await users.userPhoneNumbersOrdered(db, id),
        containsAll(<String>['2534', '2565']),
      );
    });

    test('η σειρά των τηλεφώνων δεν είναι διένεξη', () async {
      final id = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
        'phones': const <String>['2565', '2534'],
      });
      // Η φόρμα τα κρατά με τη σειρά που πληκτρολογήθηκαν, η βάση αλφαβητικά.
      final asFormSawIt = <String, Object?>{
        'first_name': 'Σοφία',
        'phones': UserRepository.phonesFingerprint(const ['2565', '2534']),
      };

      await users.updateUser(id, {
        'first_name': 'Σοφια',
        'phones': const <String>['2565', '2534'],
      }, expected: asFormSawIt);

      expect((await rowById('users', id))['first_name'], 'Σοφια');
    });

    test('με force γράφεται η δική μου εικόνα', () async {
      final id = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
      });
      final asFormSawIt = <String, Object?>{
        'first_name': 'Σοφία',
        'notes': null,
      };
      await users.updateUser(id, {'notes': 'ξένη σημείωση'}, expected: null);

      await users.updateUser(
        id,
        {'first_name': 'Σοφια', 'notes': null},
        expected: asFormSawIt,
        force: true,
      );

      final row = await rowById('users', id);
      expect(row['first_name'], 'Σοφια');
      expect(row['notes'], isNull);
    });

    test('χωρίς ξένη αλλαγή η αποθήκευση περνά κανονικά', () async {
      final id = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
      });
      final fresh = <String, Object?>{'first_name': 'Σοφία'};

      await users.updateUser(id, {'first_name': 'Σοφια'}, expected: fresh);

      expect((await rowById('users', id))['first_name'], 'Σοφια');
    });

    // ------------------------------------------------------------------
    // Τμήμα
    // ------------------------------------------------------------------

    test('η μετονομασία τμήματος δεν σβήνει το κτίριο του άλλου', () async {
      final id = (await departments.getOrCreateDepartmentIdByName('ΤΕΠ'))!;
      final asFormSawIt = <String, Object?>{'name': 'ΤΕΠ', 'building': null};

      await departments.updateDepartment(id, {
        'building': 'Νέα Πτέρυγα',
      }, expected: null);

      await expectLater(
        () => departments.updateDepartment(id, {
          'name': 'Τμήμα Επειγόντων',
          'building': null,
        }, expected: asFormSawIt),
        throwsA(isA<DirectoryStaleException>()),
      );

      expect((await rowById('departments', id))['building'], 'Νέα Πτέρυγα');
    });

    // ------------------------------------------------------------------
    // Εξοπλισμός
    // ------------------------------------------------------------------

    test('η διόρθωση κωδικού δεν σβήνει τη θέση που έγραψε ο άλλος', () async {
      final id = await equipment.insertEquipmentFromMap({
        'code_equipment': '5067',
        'type': 'Υπολογιστής',
      });
      final asFormSawIt = <String, Object?>{
        'code_equipment': '5067',
        'location': null,
      };

      await equipment.updateEquipment(id, {
        'location': 'Γραφείο 3',
      }, expected: null);

      await expectLater(
        () => equipment.updateEquipment(id, {
          'code_equipment': '5068',
          'location': null,
        }, expected: asFormSawIt),
        throwsA(isA<DirectoryStaleException>()),
      );

      expect((await rowById('equipment', id))['location'], 'Γραφείο 3');
    });

    test('η χρέωση που έκανε ο άλλος δεν σβήνεται αμίλητα', () async {
      final eqId = await equipment.insertEquipmentFromMap({
        'code_equipment': '5067',
        'type': 'Υπολογιστής',
      });
      final ownerId = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
      });
      // Η καρτέλα άνοιξε όσο ο εξοπλισμός ήταν αχρέωτος.
      final asFormSawIt = <String, Object?>{
        'code_equipment': '5067',
        'notes': null,
        'owner': EquipmentRepository.ownersFingerprint(const <int>[]),
      };

      // Ο συνάδελφος τον χρεώνει στην Ψαρρά.
      await equipment.replaceEquipmentUsers(eqId, [ownerId]);

      await expectLater(
        () => equipment.updateEquipment(eqId, {
          'code_equipment': '5067',
          'notes': 'Άλλαξε μνήμη',
          'owner': const <int>[],
        }, expected: asFormSawIt),
        throwsA(isA<DirectoryStaleException>()),
      );

      expect(
        await equipment.countUsersLinkedToEquipment(eqId),
        1,
        reason: 'η χρέωση του συναδέλφου μένει',
      );
      expect(
        (await rowById('equipment', eqId))['notes'],
        isNull,
        reason: 'τίποτα δεν γράφεται όταν η αποθήκευση σταματά',
      );
    });

    test('ο ίδιος κάτοχος δεν είναι διένεξη', () async {
      final ownerId = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
      });
      final eqId = await equipment.insertEquipmentFromMap({
        'code_equipment': '5067',
      });
      await equipment.replaceEquipmentUsers(eqId, [ownerId]);

      final asFormSawIt = <String, Object?>{
        'code_equipment': '5067',
        'notes': null,
        'owner': EquipmentRepository.ownersFingerprint([ownerId]),
      };

      await equipment.updateEquipment(eqId, {
        'code_equipment': '5067',
        'notes': 'Καθαρίστηκε',
        'owner': [ownerId],
      }, expected: asFormSawIt);

      expect((await rowById('equipment', eqId))['notes'], 'Καθαρίστηκε');
      expect(await equipment.countUsersLinkedToEquipment(eqId), 1);
    });

    test('η αλλαγή χρέωσης περνά όταν κανείς άλλος δεν την άγγιξε', () async {
      final ownerId = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
      });
      final eqId = await equipment.insertEquipmentFromMap({
        'code_equipment': '5067',
      });
      final asFormSawIt = <String, Object?>{
        'code_equipment': '5067',
        'owner': EquipmentRepository.ownersFingerprint(const <int>[]),
      };

      await equipment.updateEquipment(eqId, {
        'code_equipment': '5067',
        'owner': [ownerId],
      }, expected: asFormSawIt);

      expect(await equipment.countUsersLinkedToEquipment(eqId), 1);
    });

    test('η στοχευμένη εγγραφή χωρίς κάτοχο δεν αγγίζει τη χρέωση', () async {
      final ownerId = await users.insertUserFromMap({
        'first_name': 'Σοφία',
        'last_name': 'Ψαρρά',
      });
      final eqId = await equipment.insertEquipmentFromMap({
        'code_equipment': '5067',
      });
      await equipment.replaceEquipmentUsers(eqId, [ownerId]);

      // Μαζική μετακίνηση τμήματος: γράφει μία στήλη, δεν ξέρει από κάτοχο.
      await equipment.updateEquipment(eqId, {
        'location': 'Γραφείο 3',
      }, expected: null);

      expect(
        await equipment.countUsersLinkedToEquipment(eqId),
        1,
        reason: 'χωρίς κλειδί κατόχου η χρέωση μένει άθικτη',
      );
      expect((await rowById('equipment', eqId))['location'], 'Γραφείο 3');
    });
  });

  group('DirectorySaveConflict — τι κρίνεται', () {
    test('πεδίο που δεν γράφω δεν είναι διένεξη', () {
      final conflict = DirectorySaveConflict.between(
        entityType: 'user',
        expected: const {'first_name': 'Σοφία', 'notes': null},
        fresh: const {'first_name': 'Σοφία', 'notes': 'ξένη'},
        // Η εγγραφή μου δεν αγγίζει καθόλου τις σημειώσεις.
        attempted: const {'first_name': 'Σοφια'},
      );

      expect(conflict, isNull);
    });

    test('χωρίς αφετηρία δεν κρίνεται τίποτα (fail-open)', () {
      final conflict = DirectorySaveConflict.between(
        entityType: 'user',
        expected: null,
        fresh: const {'first_name': 'άλλο'},
        attempted: const {'first_name': 'δικό μου'},
      );

      expect(conflict, isNull);
    });

    test('το is_deleted δεν μετρά ως αλλαγή', () {
      final conflict = DirectorySaveConflict.between(
        entityType: 'user',
        expected: const {'first_name': 'Σοφία', 'is_deleted': 0},
        fresh: const {'first_name': 'Σοφία', 'is_deleted': 1},
        attempted: const {'first_name': 'Σοφία', 'is_deleted': 0},
      );

      expect(conflict, isNull);
    });

    test('η αφετηρία της καρτέλας υπαλλήλου έχει τα κλειδιά που γράφονται', () {
      final baseline = DirectoryNotifier.userConflictBaseline(
        UserModel(
          firstName: 'Σοφία',
          lastName: 'Ψαρρά',
          phones: const ['2534'],
        ),
      );

      expect(
        baseline.keys,
        containsAll(<String>[
          'first_name',
          'last_name',
          'department_id',
          'location',
          'notes',
          'lansweeper_username',
          'phones',
        ]),
      );
    });
  });
}
