// Συγκεντρωτικά και περίληψη μαζικής διαγραφής εξοπλισμού, με πραγματική βάση.
//
// Ολόκληρο αρχείο (από ρίζα έργου):
//   flutter test test/features/directory/services/equipment_deletion_totals_test.dart

import 'dart:io';

import 'package:call_logger/core/database/database_helper.dart';
import 'package:call_logger/core/utils/search_text_normalizer.dart';
import 'package:call_logger/core/database/equipment_deletion_summary_repository.dart';
import 'package:call_logger/features/directory/services/equipment_deletion_summary.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../../test_setup.dart';

void main() {
  group('Μαζική διαγραφή εξοπλισμού', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'equipment_deletion_totals_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/totals.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('calls');
      await db.delete('tasks');
      await db.delete('user_equipment');
      await db.delete('equipment');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('users');
      await db.delete('departments');
    });

    Future<int> insertEquipment(String code, {int? departmentId}) {
      return db.insert('equipment', {
        'code_equipment': code,
        'type': 'Desktop',
        'department_id': departmentId,
        'is_deleted': 0,
      });
    }

    Future<int> insertUser(String first, String last) {
      return db.insert('users', {
        'first_name': first,
        'last_name': last,
        'is_deleted': 0,
      });
    }

    Future<int> insertDepartment(String name) {
      return db.insert('departments', {
        'name': name,
        'name_key': SearchTextNormalizer.normalizeForSearch(name),
        'is_deleted': 0,
      });
    }

    Future<void> linkOwner(int equipmentId, int userId) {
      return db.insert('user_equipment', {
        'user_id': userId,
        'equipment_id': equipmentId,
      });
    }

    Future<void> addCall(
      int equipmentId, {
      bool deleted = false,
      String? date,
    }) async {
      await db.insert('calls', {
        'equipment_id': equipmentId,
        'date': date,
        'issue': 'δοκιμή',
        'status': 'completed',
        'is_deleted': deleted ? 1 : 0,
      });
    }

    /// Κλήση που αναφέρει τον εξοπλισμό ΜΟΝΟ ως κείμενο, χωρίς δεσμό.
    Future<void> addTextCall(String code, {String? date}) async {
      await db.insert('calls', {
        'equipment_id': null,
        'equipment_text': code,
        'date': date,
        'issue': 'δοκιμή',
        'status': 'completed',
        'is_deleted': 0,
      });
    }

    Future<void> addTask(
      int equipmentId, {
      bool deleted = false,
      String? updatedAt,
    }) async {
      await db.insert('tasks', {
        'equipment_id': equipmentId,
        'title': 'εκκρεμότητα',
        'status': 'open',
        'updated_at': updatedAt,
        'is_deleted': deleted ? 1 : 0,
      });
    }

    Future<EquipmentDeletionTotals> totalsFor(List<int> ids) async {
      return EquipmentDeletionTotals.fromSummaries(
        await deletionSummaries(db, ids),
      );
    }

    test('συγκεντρωτικά: πλήθος, κάτοχοι, κλήσεις, εκκρεμότητες', () async {
      final e1 = await insertEquipment('1001');
      final e2 = await insertEquipment('1002');
      final e3 = await insertEquipment('1003');
      final owner = await insertUser('Σοφία', 'Παππά');
      await linkOwner(e1, owner);
      await addCall(e1);
      await addCall(e1);
      await addCall(e2);
      await addTask(e2);
      // Διαγραμμένη κλήση δεν μετράει ως ιστορικό που αφήνεται πίσω.
      await addCall(e3, deleted: true);

      final totals = await totalsFor([e1, e2, e3]);

      expect(totals.equipmentCount, 3);
      expect(totals.withOwnerCount, 1);
      expect(totals.callCount, 3);
      expect(totals.taskCount, 1);
    });

    test('κενή επιλογή: όλα μηδέν χωρίς ερώτημα', () async {
      final totals = await totalsFor(const []);

      expect(totals.equipmentCount, 0);
      expect(totals.withOwnerCount, 0);
      expect(totals.callCount, 0);
      expect(totals.taskCount, 0);
    });

    test('η κύρια γραμμή παραλείπει τα μηδενικά σκέλη', () async {
      final e1 = await insertEquipment('2001');

      final totals = await totalsFor([e1]);

      expect(totals.headline(), '1 εξοπλισμός');
    });

    test('η κύρια γραμμή δείχνει κατόχους, κλήσεις και εκκρεμότητες', () async {
      final e1 = await insertEquipment('3001');
      final owner = await insertUser('Μαρία', 'Ορφανού');
      await linkOwner(e1, owner);
      await addCall(e1);
      await addTask(e1);

      final totals = await totalsFor([e1]);

      expect(
        totals.headline(),
        '1 εξοπλισμός · 1 με κάτοχο · 1 κλήση ιστορικού · 1 εκκρεμότητα',
      );
    });

    test('διαγραμμένη εκκρεμότητα δεν μετράει', () async {
      final e1 = await insertEquipment('4001');
      await addTask(e1, deleted: true);

      final summaries = await deletionSummaries(db, [e1]);

      expect(summaries.single.taskCount, 0);
      expect(summaries.single.hasTraces, isFalse);
    });

    test('κλήσεις που αναφέρουν τον κωδικό μόνο ως κείμενο μετράνε', () async {
      final e1 = await insertEquipment('4200');
      await addCall(e1);
      await addTextCall('4200');
      await addTextCall('4200');
      // Άλλος κωδικός — δεν πρέπει να προσμετρηθεί.
      await addTextCall('9999');

      final summaries = await deletionSummaries(db, [e1]);

      expect(summaries.single.callCount, 3);
    });

    test('η τελευταία χρήση είναι η πιο πρόσφατη των δύο πηγών', () async {
      final e1 = await insertEquipment('4300');
      await addCall(e1, date: '2026-01-10');
      await addTextCall('4300', date: '2026-06-12');

      final summaries = await deletionSummaries(db, [e1]);

      expect(summaries.single.lastCallAt, DateTime.parse('2026-06-12'));
    });

    test('χωρίς υπάλληλο-κάτοχο εμφανίζεται το τμήμα', () async {
      final deptId = await insertDepartment('Αιμοδοσία');
      final e1 = await insertEquipment('4400', departmentId: deptId);

      final summaries = await deletionSummaries(db, [e1]);

      expect(summaries.single.ownerName, isNull);
      expect(summaries.single.departmentName, 'Αιμοδοσία');
      expect(summaries.single.titleLine, '4400 → τμήμα Αιμοδοσία');
    });

    test('ο υπάλληλος-κάτοχος υπερισχύει του τμήματος', () async {
      final deptId = await insertDepartment('Αιμοδοσία');
      final e1 = await insertEquipment('4500', departmentId: deptId);
      final owner = await insertUser('Μαρία', 'Ορφανού');
      await linkOwner(e1, owner);

      final summaries = await deletionSummaries(db, [e1]);

      expect(summaries.single.titleLine, '4500 → Μαρία Ορφανού');
    });
  });

  group('Γραμμές λεπτομερειών (batch)', () {
    late Database db;

    setUpAll(() async {
      initSqfliteFfiForTests();
      final dir = await Directory.systemTemp.createTemp(
        'equipment_deletion_lines_',
      );
      await DatabaseHelper.bindTestDatabaseFile('${dir.path}/lines.db');
      db = await DatabaseHelper.instance.database;
    });

    setUp(() async {
      await seedIsolatedTestDatabase();
      await db.delete('calls');
      await db.delete('tasks');
      await db.delete('user_equipment');
      await db.delete('equipment');
      await db.delete('user_phones');
      await db.delete('phones');
      await db.delete('users');
    });

    test(
      'κρατά τη σειρά εισόδου και δένει κάτοχο, τηλέφωνο, ιστορικό',
      () async {
        final first = await db.insert('equipment', {
          'code_equipment': '5001',
          'is_deleted': 0,
        });
        final second = await db.insert('equipment', {
          'code_equipment': '5002',
          'is_deleted': 0,
        });
        final owner = await db.insert('users', {
          'first_name': 'Τίνα',
          'last_name': 'Γεωργάκη',
          'is_deleted': 0,
        });
        await db.insert('user_equipment', {
          'user_id': owner,
          'equipment_id': second,
        });
        final phoneId = await db.insert('phones', {'number': '2898'});
        await db.insert('user_phones', {'user_id': owner, 'phone_id': phoneId});
        await db.insert('calls', {
          'equipment_id': second,
          'date': '2026-06-12',
          'issue': 'δοκιμή',
          'status': 'completed',
          'is_deleted': 0,
        });

        // Ζητούμε ανάποδα από τη σειρά εισαγωγής: πρέπει να τη σεβαστεί.
        final summaries = await deletionSummaries(db, [second, first]);

        expect(summaries.map((s) => s.titleLine).toList(), [
          '5002 → Τίνα Γεωργάκη',
          '5001 → χωρίς κάτοχο και τμήμα',
        ]);
        expect(summaries.first.buildTraceLines(), [
          'τηλ. 2898',
          '1 κλήση ιστορικού (τελευταία 12/06/2026)',
        ]);
        expect(summaries.last.buildTraceLines(), isEmpty);
      },
    );

    test('εξοπλισμός χωρίς κωδικό πέφτει πίσω στο id', () async {
      final id = await db.insert('equipment', {
        'code_equipment': '',
        'is_deleted': 0,
      });

      final summaries = await deletionSummaries(db, [id]);

      expect(summaries.single.code, '$id');
    });

    // Το SQLite έχει σκληρό όριο παραμέτρων ανά δήλωση· με «επιλογή όλων» σε
    // μεγάλο κατάλογο ένα ενιαίο `IN (...)` θα έσκαγε.
    test('περισσότερα ids από το όριο παραμέτρων του SQLite', () async {
      final ids = <int>[];
      for (var i = 0; i < 1200; i++) {
        ids.add(
          await db.insert('equipment', {
            'code_equipment': 'BULK-$i',
            'is_deleted': 0,
          }),
        );
      }

      final summaries = await deletionSummaries(db, ids);
      final totals = EquipmentDeletionTotals.fromSummaries(summaries);

      expect(summaries.length, 1200);
      expect(summaries.first.code, 'BULK-0');
      expect(summaries.last.code, 'BULK-1199');
      expect(totals.equipmentCount, 1200);
    });
  });
}
