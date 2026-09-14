// Ομώνυμοι υποψήφιοι σε υπαλλήλους, συμβάσεις και μοντέλα.
//
// Τα σενάρια είναι μετρημένα στη ζωντανή βάση (14/09):
//   · 4 μοντέλα «TURBO-X» με ΤΟΝ ΙΔΙΟ κατασκευαστή (ΠΛΑΙΣΙΟ) — τα χωρίζει
//     μόνο η υποκατηγορία, που δεν φαινόταν πουθενά.
//   · 3 συμβάσεις «ΕΔΕΤ» με ίδια κατηγορία «Δωρεά» και κενές ημερομηνίες —
//     τις χωρίζει ο προμηθευτής, και δύο από αυτές μόνο ο εξοπλισμός.
//   · 4 υπάλληλοι «Σούκουλη», δύο με ίδιο μικρό όνομα — τους χωρίζει το
//     γραφείο.
//
//   flutter test test/core/database/old_database/lamp_lookalike_owner_contract_model_test.dart

import 'dart:io';

import 'package:call_logger/core/database/old_database/lamp_database_provider.dart';
import 'package:call_logger/core/database/old_database/lamp_issue_resolution_service.dart';
import 'package:call_logger/core/database/old_database/old_database_schema.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  sqfliteFfiInit();
  databaseFactory = databaseFactoryFfi;

  late Directory tempDir;
  late String dbPath;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-lookalike-rest-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
    } finally {
      await db.close();
    }
  });

  tearDown(() async {
    await LampDatabaseProvider.instance.close();
    try {
      if (await tempDir.exists()) await tempDir.delete(recursive: true);
    } catch (_) {}
  });

  Future<void> withDb(Future<void> Function(Database db) action) async {
    await LampDatabaseProvider.instance.close();
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await action(db);
    } finally {
      await db.close();
    }
  }

  Future<void> raiseIssue({
    required String column,
    required String rawValue,
    int code = 5005,
  }) async {
    await withDb((db) async {
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'non_numeric_fk',
        'sheet': 'integrity_scan',
        'row_number': code,
        'column_name': column,
        'raw_value': rawValue,
        'status': 'open',
        'created_at': '2026-09-14T09:00:00.000',
      });
    });
  }

  Future<Map<int, String>> descriptionsById() async {
    final proposals = await LampIssueResolutionService().analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.nonNumericFk,
    );
    return <int, String>{
      for (final option in proposals.single.options)
        if (option.proposedId != null)
          option.proposedId!: option.description ?? '',
    };
  }

  Future<Map<int, String>> labelsById() async {
    final proposals = await LampIssueResolutionService().analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.nonNumericFk,
    );
    return <int, String>{
      for (final option in proposals.single.options)
        if (option.proposedId != null) option.proposedId!: option.label,
    };
  }

  group('μοντέλα «TURBO-X»', () {
    setUp(() async {
      await withDb((db) async {
        const rows = <({int id, String category, String subcategory})>[
          (id: 184, category: 'Περιφερειακό', subcategory: 'Πληκτρολόγιο'),
          (id: 320, category: 'Οθόνη', subcategory: 'LCD 19"'),
          (id: 321, category: 'Υπολογιστής', subcategory: 'Σταθερός'),
          (id: 322, category: 'Περιφερειακό', subcategory: 'Ποντίκι'),
        ];
        for (final row in rows) {
          await db.insert('model', <String, Object?>{
            'model': row.id,
            'model_name': 'TURBO-X',
            'manufacturer_name': 'ΠΛΑΙΣΙΟ',
            'category_name': row.category,
            'subcategory_name': row.subcategory,
          });
        }
        await db.insert('equipment', <String, Object?>{
          'code': 5005,
          'description': 'DELL',
          'model_original_text': 'TURBO-X',
        });
      });
      await raiseIssue(column: 'model', rawValue: 'TURBO-X');
    });

    test('ο κοινός κατασκευαστής δεν τυπώνεται σε καμία γραμμή', () async {
      for (final entry in (await descriptionsById()).entries) {
        expect(
          entry.value,
          isNot(contains('ΠΛΑΙΣΙΟ')),
          reason: 'Ίδιος και στα τέσσερα — δεν ξεχωρίζει κανένα',
        );
      }
      for (final label in (await labelsById()).values) {
        expect(label, isNot(contains('κατασκευαστής')));
      }
    });

    test('η υποκατηγορία που τα χωρίζει φαίνεται', () async {
      final byId = await descriptionsById();
      expect(byId[184], contains('Πληκτρολόγιο'));
      expect(byId[320], contains('LCD 19"'));
      expect(byId[322], contains('Ποντίκι'));
    });
  });

  group('συμβάσεις «ΕΔΕΤ»', () {
    setUp(() async {
      await withDb((db) async {
        const rows = <({int id, String supplier})>[
          (id: 73, supplier: 'NEUROSOFT A.E.'),
          (id: 74, supplier: 'NEUROSOFT A.E.'),
          (id: 77, supplier: 'ΕΔΕΤ Α.Ε.'),
        ];
        for (final row in rows) {
          await db.insert('contracts', <String, Object?>{
            'contract': row.id,
            'contract_name': 'ΕΔΕΤ',
            'supplier_name': row.supplier,
            'category_name': 'Δωρεά',
          });
        }
        // Ο εξοπλισμός είναι το μόνο που χωρίζει τις δύο NEUROSOFT.
        await db.insert('equipment', <String, Object?>{
          'code': 7001,
          'description': 'Σταθμός',
          'contract': 73,
        });
        await db.insert('equipment', <String, Object?>{
          'code': 5005,
          'description': 'DELL',
          'contract_original_text': 'ΕΔΕΤ',
        });
      });
      await raiseIssue(column: 'contract', rawValue: 'ΕΔΕΤ');
    });

    test('η κοινή κατηγορία και οι κενές ημερομηνίες δεν τυπώνονται', () async {
      for (final description in (await descriptionsById()).values) {
        expect(description, isNot(contains('Δωρεά')));
        expect(description, isNot(contains('από:')));
        expect(description, isNot(contains('έως:')));
      }
    });

    test('ο προμηθευτής και ο εξοπλισμός ξεχωρίζουν τις τρεις', () async {
      final byId = await descriptionsById();
      expect(byId[77], contains('ΕΔΕΤ Α.Ε.'));
      expect(byId[73], contains('εξοπλισμοί: 1'));
      expect(byId[74], contains('εξοπλισμοί: 0'));
    });
  });

  group('υπάλληλοι «Σούκουλη»', () {
    setUp(() async {
      await withDb((db) async {
        const offices = <({int id, String name, String department})>[
          (id: 1, name: 'Γραφείο Υλικού #1', department: 'Οικονομικό Τμήμα'),
          (id: 2, name: 'Μαστογράφος #1', department: 'Ακτινολογικό Τμήμα'),
          (
            id: 3,
            name: 'Διευθυντής ΚΥ Λουτρακίου',
            department: 'ΚΥ Λουτρακίου',
          ),
        ];
        for (final office in offices) {
          await db.insert('offices', <String, Object?>{
            'office': office.id,
            'office_name': office.name,
            'department_name': office.department,
          });
        }
        // Τρία διαφορετικά μικρά ονόματα: το σχήμα απαγορεύει δύο ταυτόσημα
        // ονοματεπώνυμα (μοναδικός δείκτης ταυτότητας), αν και η ζωντανή βάση
        // κρατά ένα τέτοιο ζεύγος από παλιότερη εισαγωγή.
        const people = <({int id, String first, int office})>[
          (id: 109, first: 'Παρασκευή', office: 1),
          (id: 163, first: 'Κων/να', office: 2),
          (id: 2857, first: 'Βασιλική', office: 3),
        ];
        for (final person in people) {
          await db.insert('owners', <String, Object?>{
            'owner': person.id,
            'last_name': 'Σούκουλη',
            'first_name': person.first,
            'office': person.office,
          });
        }
        await db.insert('equipment', <String, Object?>{
          'code': 5005,
          'description': 'DELL',
          'owner_original_text': 'Σούκουλη',
        });
      });
      await raiseIssue(column: 'owner', rawValue: 'Σούκουλη');
    });

    test('το γραφείο ξεχωρίζει τους συνωνύμους', () async {
      final byId = await descriptionsById();
      expect(byId[109], contains('Γραφείο Υλικού #1'));
      expect(byId[2857], contains('Διευθυντής ΚΥ Λουτρακίου'));
    });

    test('το γραφείο δεν κολλάει πια μόνιμα στο όνομα', () async {
      for (final label in (await labelsById()).values) {
        expect(
          label,
          isNot(contains('γραφείο=')),
          reason: 'Μπαίνει από κάτω, και μόνο όταν ξεχωρίζει',
        );
      }
    });
  });
}
