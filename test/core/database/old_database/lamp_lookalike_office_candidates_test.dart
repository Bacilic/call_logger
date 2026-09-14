// Πέντε ομώνυμα γραφεία στον οδηγό επίλυσης: τι βλέπει ο χρήστης.
//
// Σενάριο 14/09 (Σ12): για την τιμή «ΑΙΜΑΤΟΛΟΓΙΚΟ» του εξοπλισμού 5005
// προτείνονταν πέντε γραφεία, όλα με «Ομοιότητα: 72%» και όλα με
// «τμήμα=Αιματολογικό Εργαστήριο». Το ποσοστό ήταν σταθερά και το τμήμα ίδιο
// παντού — καμία από τις δύο ενδείξεις δεν βοηθούσε στην επιλογή, ενώ το
// γραφείο με τα 14 μηχανήματα εμφανιζόταν τέταρτο.
//
//   flutter test test/core/database/old_database/lamp_lookalike_office_candidates_test.dart

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

  // Τα πραγματικά γραφεία της βάσης: κοινό τμήμα, κοινό κτίριο, κοινός
  // όροφος. Διαφέρουν στον εξοπλισμό, στον υπεύθυνο και στο τηλέφωνο.
  const offices = <({int id, String name, int responsible, String phones})>[
    (
      id: 66,
      name: 'Αιματολογικό Εργαστήριο',
      responsible: 2853,
      phones: '2517',
    ),
    (id: 282, name: 'Αιματολογικό (Χρόνοι)', responsible: 2853, phones: '2417'),
    (
      id: 283,
      name: 'Αίθουσα Αιματολογικού#1',
      responsible: 226,
      phones: '2517',
    ),
    (
      id: 281,
      name: 'Αίθουσα Αιματολογικού#2',
      responsible: 226,
      phones: '2517',
    ),
    (id: 186, name: 'Διευθυντής Αιματολογικού', responsible: 226, phones: ''),
  ];
  const equipmentPerOffice = <int, int>{66: 14, 282: 7, 283: 5, 281: 1, 186: 0};

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lamp-lookalike-office-');
    dbPath = p.join(tempDir.path, 'lamp.db');
    final db = await openDatabase(dbPath, singleInstance: false);
    try {
      await createOldDatabaseSchema(db);
      await db.insert('owners', <String, Object?>{
        'owner': 2853,
        'last_name': 'Μουράτης',
        'first_name': 'Γεώργιος',
        'office': 66,
      });
      await db.insert('owners', <String, Object?>{
        'owner': 226,
        'last_name': 'Καράμ',
        'first_name': 'Χάνα',
        'office': 186,
      });
      for (final office in offices) {
        await db.insert('offices', <String, Object?>{
          'office': office.id,
          'office_name': office.name,
          'department_name': 'Αιματολογικό Εργαστήριο',
          'organization_name': 'Νοσοκομειακή Μονάδα',
          'responsible': office.responsible,
          'phones': office.phones.isEmpty ? null : office.phones,
          'building': 'Α',
          'level': 1,
        });
      }

      var code = 9000;
      for (final entry in equipmentPerOffice.entries) {
        for (var i = 0; i < entry.value; i++) {
          await db.insert('equipment', <String, Object?>{
            'code': code++,
            'description': 'Σταθμός $i',
            'office': entry.key,
          });
        }
      }

      // Ο εξοπλισμός του σεναρίου: ωμό κείμενο «ΑΙΜΑΤΟΛΟΓΙΚΟ», χωρίς γραφείο.
      await db.insert('equipment', <String, Object?>{
        'code': 5005,
        'description': 'DELL',
        'office_original_text': 'ΑΙΜΑΤΟΛΟΓΙΚΟ',
      });
      await db.insert('data_issues', <String, Object?>{
        'issue_type': 'non_numeric_fk',
        'sheet': 'integrity_scan',
        'row_number': 5005,
        'column_name': 'office',
        'raw_value': 'ΑΙΜΑΤΟΛΟΓΙΚΟ',
        'status': 'open',
        'created_at': '2026-09-14T09:00:00.000',
      });
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

  Future<List<LampIssueResolutionOption>> candidateOptions() async {
    final proposals = await LampIssueResolutionService().analyzeIssues(
      databasePath: dbPath,
      issueType: LampIssueType.nonNumericFk,
    );
    return proposals.single.options
        .where((o) => o.proposedId != null)
        .toList(growable: false);
  }

  test('και οι πέντε ομώνυμοι φτάνουν στην επιλογή', () async {
    final options = await candidateOptions();
    expect(options, hasLength(5));
  });

  test('το κοινό τμήμα δεν καταλαμβάνει χώρο σε καμία γραμμή', () async {
    for (final option in await candidateOptions()) {
      expect(
        option.description,
        isNot(contains('τμήμα')),
        reason: 'Ίδιο και στους πέντε — δεν ξεχωρίζει κανέναν',
      );
      expect(option.description, isNot(contains('κτίριο')));
      expect(option.description, isNot(contains('όροφος')));
    }
  });

  test('ούτε ο τίτλος του υποψηφίου κουβαλά το κοινό τμήμα', () async {
    // Το τμήμα μπαίνει στον τίτλο από άλλο μονοπάτι — και επιβίωνε εκεί ακόμη
    // κι όταν είχε φύγει από τη γραμμή των χαρακτηριστικών.
    for (final option in await candidateOptions()) {
      expect(option.label, isNot(contains('τμήμα')));
    }
  });

  test('ο εξοπλισμός κάθε γραφείου φαίνεται και είναι ο σωστός', () async {
    final byId = <int, String>{
      for (final o in await candidateOptions())
        o.proposedId!: o.description ?? '',
    };
    expect(byId[66], contains('εξοπλισμοί: 14'));
    expect(byId[282], contains('εξοπλισμοί: 7'));
    expect(byId[186], contains('εξοπλισμοί: 0'));
  });

  test('ο υπεύθυνος ξεχωρίζει τα δύο ζευγάρια', () async {
    final byId = <int, String>{
      for (final o in await candidateOptions())
        o.proposedId!: o.description ?? '',
    };
    expect(byId[66], contains('Μουράτης Γεώργιος'));
    expect(byId[283], contains('Καράμ Χάνα'));
  });

  test('το γραφείο χωρίς τηλέφωνο απλώς δεν το αναφέρει', () async {
    final byId = <int, String>{
      for (final o in await candidateOptions())
        o.proposedId!: o.description ?? '',
    };
    expect(byId[281], contains('τηλέφωνο: 2517'));
    expect(byId[186], isNot(contains('τηλέφωνο')));
  });

  test('το ίδιο για όλους ποσοστό δεν εμφανίζεται πουθενά', () async {
    for (final option in await candidateOptions()) {
      expect(
        option.description,
        isNot(contains('Ομοιότητα')),
        reason: 'Σταθερά 72% σε κάθε υποψήφιο — δεν είναι μέτρηση',
      );
    }
  });

  test('πρώτο έρχεται το γραφείο με τον περισσότερο εξοπλισμό', () async {
    final options = await candidateOptions();
    expect(options.first.proposedId, 66);
    expect(options.last.proposedId, 186);
  });
}
